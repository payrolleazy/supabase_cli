create or replace function public.platform_async_claim_jobs(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_worker_code text := lower(btrim(coalesce(p_params->>'worker_code', '')));
  v_claimed_by_worker text := coalesce(nullif(btrim(coalesce(p_params->>'claimed_by_worker', '')), ''), v_worker_code);
  v_batch_size integer;
  v_worker public.platform_async_worker_registry%rowtype;
  v_rows jsonb;
begin
  if v_worker_code = '' then
    return public.platform_json_response(false, 'WORKER_CODE_REQUIRED', 'worker_code is required.', '{}'::jsonb);
  end if;

  select * into v_worker
  from public.platform_async_worker_registry
  where worker_code = v_worker_code;

  if not found then
    return public.platform_json_response(false, 'WORKER_NOT_REGISTERED', 'Worker route is not registered.', jsonb_build_object('worker_code', v_worker_code));
  end if;
  if v_worker.is_active = false then
    return public.platform_json_response(false, 'WORKER_ROUTE_DISABLED', 'Worker route is disabled.', jsonb_build_object('worker_code', v_worker_code));
  end if;

  v_batch_size := least(greatest(coalesce((p_params->>'batch_size')::integer, v_worker.max_batch_size), 1), v_worker.max_batch_size);

  with due_rows as (
    select paj.job_id
    from public.platform_async_job paj
    join public.platform_tenant_registry_view ptrv on ptrv.tenant_id = paj.tenant_id
    where paj.worker_code = v_worker.worker_code
      and paj.job_state in ('queued', 'retry_wait')
      and ptrv.ready_for_routing = true
      and ptrv.background_processing_allowed = true
      and (
        (paj.job_state = 'queued' and paj.available_at <= timezone('utc', now()))
        or
        (paj.job_state = 'retry_wait' and coalesce(paj.next_retry_at, paj.available_at) <= timezone('utc', now()))
      )
    order by paj.priority asc, coalesce(paj.next_retry_at, paj.available_at) asc, paj.created_at asc
    limit v_batch_size
    for update skip locked
  ),
  claimed as (
    update public.platform_async_job paj
    set job_state = 'claimed',
        claimed_at = timezone('utc', now()),
        lease_expires_at = timezone('utc', now()) + make_interval(secs => v_worker.default_lease_seconds),
        heartbeat_at = timezone('utc', now()),
        claimed_by_worker = v_claimed_by_worker,
        attempt_count = paj.attempt_count + 1,
        next_retry_at = null,
        updated_at = timezone('utc', now())
    from due_rows
    where paj.job_id = due_rows.job_id
    returning paj.*
  ),
  attempt_insert as (
    insert into public.platform_async_job_attempt (
      job_id, attempt_number, worker_code, started_at, attempt_state
    )
    select
      claimed.job_id, claimed.attempt_count, claimed.worker_code, timezone('utc', now()), 'started'
    from claimed
    returning job_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'job_id', claimed.job_id,
    'tenant_id', claimed.tenant_id,
    'tenant_schema', claimed.tenant_schema,
    'module_code', claimed.module_code,
    'worker_code', claimed.worker_code,
    'job_type', claimed.job_type,
    'job_state', claimed.job_state,
    'attempt_count', claimed.attempt_count,
    'claimed_by_worker', claimed.claimed_by_worker,
    'lease_expires_at', claimed.lease_expires_at,
    'payload', claimed.payload
  ) order by claimed.priority asc, claimed.created_at asc), '[]'::jsonb)
  into v_rows
  from claimed;

  return public.platform_json_response(true, 'OK', 'Async jobs claimed.', jsonb_build_object(
    'worker_code', v_worker.worker_code,
    'claimed_count', jsonb_array_length(v_rows),
    'jobs', v_rows
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_async_claim_jobs.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_async_heartbeat_job(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_job_id uuid := public.platform_try_uuid(p_params->>'job_id');
  v_claimed_by_worker text := nullif(btrim(coalesce(p_params->>'claimed_by_worker', '')), '');
  v_lease_seconds integer := greatest(coalesce((p_params->>'lease_seconds')::integer, 0), 0);
  v_job public.platform_async_job%rowtype;
  v_worker public.platform_async_worker_registry%rowtype;
begin
  if v_job_id is null then
    return public.platform_json_response(false, 'JOB_ID_REQUIRED', 'job_id is required.', '{}'::jsonb);
  end if;

  select * into v_job from public.platform_async_job where job_id = v_job_id;
  if not found then
    return public.platform_json_response(false, 'JOB_NOT_FOUND', 'Async job not found.', jsonb_build_object('job_id', v_job_id));
  end if;
  if v_job.job_state not in ('claimed', 'running') then
    return public.platform_json_response(false, 'JOB_NOT_CLAIMED', 'Async job is not in a heartbeat-eligible state.', jsonb_build_object('job_id', v_job_id, 'job_state', v_job.job_state));
  end if;
  if v_claimed_by_worker is not null and coalesce(v_job.claimed_by_worker, '') <> v_claimed_by_worker then
    return public.platform_json_response(false, 'LEASE_OWNERSHIP_MISMATCH', 'claimed_by_worker does not own the job lease.', jsonb_build_object('job_id', v_job_id));
  end if;

  select * into v_worker
  from public.platform_async_worker_registry
  where worker_code = v_job.worker_code;

  update public.platform_async_job
  set heartbeat_at = timezone('utc', now()),
      lease_expires_at = timezone('utc', now()) + make_interval(secs => case when v_lease_seconds > 0 then v_lease_seconds else coalesce(v_worker.default_lease_seconds, 120) end),
      job_state = 'running',
      updated_at = timezone('utc', now())
  where job_id = v_job_id;

  return public.platform_json_response(true, 'OK', 'Async job heartbeat recorded.', jsonb_build_object('job_id', v_job_id, 'worker_code', v_job.worker_code));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_async_heartbeat_job.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_async_complete_job(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_job_id uuid := public.platform_try_uuid(p_params->>'job_id');
  v_claimed_by_worker text := nullif(btrim(coalesce(p_params->>'claimed_by_worker', '')), '');
  v_result_summary jsonb := coalesce(p_params->'result_summary', '{}'::jsonb);
  v_job public.platform_async_job%rowtype;
  v_completed_at timestamptz := timezone('utc', now());
begin
  if v_job_id is null then
    return public.platform_json_response(false, 'JOB_ID_REQUIRED', 'job_id is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_result_summary) <> 'object' then
    return public.platform_json_response(false, 'INVALID_RESULT_SUMMARY', 'result_summary must be a JSON object.', '{}'::jsonb);
  end if;

  select * into v_job from public.platform_async_job where job_id = v_job_id;
  if not found then
    return public.platform_json_response(false, 'JOB_NOT_FOUND', 'Async job not found.', jsonb_build_object('job_id', v_job_id));
  end if;
  if v_job.job_state in ('completed', 'dead_lettered', 'failed_terminal', 'cancelled') then
    return public.platform_json_response(false, 'JOB_ALREADY_COMPLETED', 'Async job is already in a terminal state.', jsonb_build_object('job_id', v_job_id, 'job_state', v_job.job_state));
  end if;
  if v_job.job_state not in ('claimed', 'running') then
    return public.platform_json_response(false, 'JOB_NOT_CLAIMED', 'Async job is not claimed.', jsonb_build_object('job_id', v_job_id, 'job_state', v_job.job_state));
  end if;
  if v_claimed_by_worker is not null and coalesce(v_job.claimed_by_worker, '') <> v_claimed_by_worker then
    return public.platform_json_response(false, 'LEASE_OWNERSHIP_MISMATCH', 'claimed_by_worker does not own the job lease.', jsonb_build_object('job_id', v_job_id));
  end if;

  update public.platform_async_job
  set job_state = 'completed',
      completed_at = v_completed_at,
      lease_expires_at = null,
      heartbeat_at = null,
      claimed_by_worker = null,
      result_summary = v_result_summary,
      last_error_code = null,
      last_error_message = null,
      last_error_details = null,
      updated_at = v_completed_at
  where job_id = v_job_id;

  update public.platform_async_job_attempt
  set attempt_state = 'succeeded',
      completed_at = v_completed_at,
      result_summary = v_result_summary,
      duration_ms = greatest(0, floor(extract(epoch from (v_completed_at - started_at)) * 1000)::integer)
  where attempt_id = (
    select attempt_id from public.platform_async_job_attempt
    where job_id = v_job_id and completed_at is null
    order by attempt_number desc
    limit 1
  );

  return public.platform_json_response(true, 'OK', 'Async job completed.', jsonb_build_object('job_id', v_job_id, 'job_state', 'completed'));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_async_complete_job.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_async_fail_job(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_job_id uuid := public.platform_try_uuid(p_params->>'job_id');
  v_claimed_by_worker text := nullif(btrim(coalesce(p_params->>'claimed_by_worker', '')), '');
  v_terminal boolean := case when p_params ? 'terminal' then (p_params->>'terminal')::boolean else false end;
  v_dead_letter boolean := case when p_params ? 'dead_letter' then (p_params->>'dead_letter')::boolean else true end;
  v_error_code text := btrim(coalesce(nullif(p_params->>'error_code', ''), 'UNKNOWN_ERROR'));
  v_error_message text := btrim(coalesce(nullif(p_params->>'error_message', ''), 'Async job failed.'));
  v_error_details jsonb := coalesce(p_params->'error_details', '{}'::jsonb);
  v_job public.platform_async_job%rowtype;
  v_worker public.platform_async_worker_registry%rowtype;
  v_completed_at timestamptz := timezone('utc', now());
  v_target_state text;
  v_next_retry_at timestamptz;
  v_attempt_state text;
begin
  if v_job_id is null then
    return public.platform_json_response(false, 'JOB_ID_REQUIRED', 'job_id is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_error_details) <> 'object' then
    return public.platform_json_response(false, 'INVALID_ERROR_DETAILS', 'error_details must be a JSON object.', '{}'::jsonb);
  end if;

  select * into v_job from public.platform_async_job where job_id = v_job_id;
  if not found then
    return public.platform_json_response(false, 'JOB_NOT_FOUND', 'Async job not found.', jsonb_build_object('job_id', v_job_id));
  end if;
  if v_job.job_state in ('completed', 'dead_lettered', 'failed_terminal', 'cancelled') then
    return public.platform_json_response(false, 'JOB_ALREADY_COMPLETED', 'Async job is already in a terminal state.', jsonb_build_object('job_id', v_job_id, 'job_state', v_job.job_state));
  end if;
  if v_job.job_state not in ('claimed', 'running') then
    return public.platform_json_response(false, 'JOB_NOT_CLAIMED', 'Async job is not claimed.', jsonb_build_object('job_id', v_job_id, 'job_state', v_job.job_state));
  end if;
  if v_claimed_by_worker is not null and coalesce(v_job.claimed_by_worker, '') <> v_claimed_by_worker then
    return public.platform_json_response(false, 'LEASE_OWNERSHIP_MISMATCH', 'claimed_by_worker does not own the job lease.', jsonb_build_object('job_id', v_job_id));
  end if;

  select * into v_worker
  from public.platform_async_worker_registry
  where worker_code = v_job.worker_code;

  if v_terminal or v_job.attempt_count >= v_job.max_attempts then
    v_target_state := case when v_dead_letter then 'dead_lettered' else 'failed_terminal' end;
    v_attempt_state := 'failed_terminal';
    v_next_retry_at := null;
  else
    v_target_state := 'retry_wait';
    v_attempt_state := 'failed_retryable';
    v_next_retry_at := public.platform_async_calculate_next_retry_at(v_job.attempt_count, coalesce(v_worker.retry_backoff_policy, '{}'::jsonb));
  end if;

  update public.platform_async_job
  set job_state = v_target_state,
      next_retry_at = v_next_retry_at,
      lease_expires_at = null,
      heartbeat_at = null,
      claimed_by_worker = null,
      last_error_code = v_error_code,
      last_error_message = v_error_message,
      last_error_details = v_error_details,
      dead_lettered_at = case when v_target_state = 'dead_lettered' then v_completed_at else dead_lettered_at end,
      updated_at = v_completed_at
  where job_id = v_job_id;

  update public.platform_async_job_attempt
  set attempt_state = v_attempt_state,
      completed_at = v_completed_at,
      error_code = v_error_code,
      error_message = v_error_message,
      error_details = v_error_details,
      duration_ms = greatest(0, floor(extract(epoch from (v_completed_at - started_at)) * 1000)::integer)
  where attempt_id = (
    select attempt_id from public.platform_async_job_attempt
    where job_id = v_job_id and completed_at is null
    order by attempt_number desc
    limit 1
  );

  return public.platform_json_response(true, 'OK', 'Async job failure recorded.', jsonb_build_object(
    'job_id', v_job_id,
    'job_state', v_target_state,
    'next_retry_at', v_next_retry_at,
    'error_code', v_error_code
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_async_fail_job.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
