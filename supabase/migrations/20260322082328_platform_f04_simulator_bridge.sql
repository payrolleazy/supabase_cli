create or replace function public.platform_sim_resolve_async_job_id(
  p_tenant_id uuid,
  p_worker_code text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_job_id uuid;
begin
  if p_tenant_id is null or p_worker_code is null or btrim(p_worker_code) = '' or p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return null;
  end if;

  select paj.job_id
  into v_job_id
  from public.platform_async_job paj
  where paj.tenant_id = p_tenant_id
    and paj.worker_code = lower(btrim(p_worker_code))
    and paj.idempotency_key = btrim(p_idempotency_key)
  order by paj.created_at desc
  limit 1;

  return v_job_id;
end;
$function$;

create or replace function public.platform_sim_heartbeat_async_job_by_idempotency(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_worker_code text := lower(btrim(coalesce(p_params->>'worker_code', '')));
  v_idempotency_key text := btrim(coalesce(p_params->>'idempotency_key', ''));
  v_claimed_by_worker text := nullif(btrim(coalesce(p_params->>'claimed_by_worker', '')), '');
  v_lease_seconds integer := greatest(coalesce((p_params->>'lease_seconds')::integer, 0), 0);
  v_job_id uuid;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;
  if v_worker_code = '' then
    return public.platform_json_response(false, 'WORKER_CODE_REQUIRED', 'worker_code is required.', '{}'::jsonb);
  end if;
  if v_idempotency_key = '' then
    return public.platform_json_response(false, 'IDEMPOTENCY_KEY_REQUIRED', 'idempotency_key is required.', '{}'::jsonb);
  end if;

  v_job_id := public.platform_sim_resolve_async_job_id(v_tenant_id, v_worker_code, v_idempotency_key);
  if v_job_id is null then
    return public.platform_json_response(false, 'ASYNC_JOB_NOT_FOUND', 'Async job not found for the tenant worker/idempotency locator.', jsonb_build_object(
      'tenant_id', v_tenant_id,
      'worker_code', v_worker_code,
      'idempotency_key', v_idempotency_key
    ));
  end if;

  return public.platform_async_heartbeat_job(jsonb_build_object(
    'job_id', v_job_id,
    'claimed_by_worker', v_claimed_by_worker,
    'lease_seconds', v_lease_seconds
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_sim_heartbeat_async_job_by_idempotency.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_sim_complete_async_job_by_idempotency(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_worker_code text := lower(btrim(coalesce(p_params->>'worker_code', '')));
  v_idempotency_key text := btrim(coalesce(p_params->>'idempotency_key', ''));
  v_claimed_by_worker text := nullif(btrim(coalesce(p_params->>'claimed_by_worker', '')), '');
  v_result_summary jsonb := coalesce(p_params->'result_summary', '{}'::jsonb);
  v_job_id uuid;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;
  if v_worker_code = '' then
    return public.platform_json_response(false, 'WORKER_CODE_REQUIRED', 'worker_code is required.', '{}'::jsonb);
  end if;
  if v_idempotency_key = '' then
    return public.platform_json_response(false, 'IDEMPOTENCY_KEY_REQUIRED', 'idempotency_key is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_result_summary) <> 'object' then
    return public.platform_json_response(false, 'INVALID_RESULT_SUMMARY', 'result_summary must be a JSON object.', '{}'::jsonb);
  end if;

  v_job_id := public.platform_sim_resolve_async_job_id(v_tenant_id, v_worker_code, v_idempotency_key);
  if v_job_id is null then
    return public.platform_json_response(false, 'ASYNC_JOB_NOT_FOUND', 'Async job not found for the tenant worker/idempotency locator.', jsonb_build_object(
      'tenant_id', v_tenant_id,
      'worker_code', v_worker_code,
      'idempotency_key', v_idempotency_key
    ));
  end if;

  return public.platform_async_complete_job(jsonb_build_object(
    'job_id', v_job_id,
    'claimed_by_worker', v_claimed_by_worker,
    'result_summary', v_result_summary
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_sim_complete_async_job_by_idempotency.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_sim_fail_async_job_by_idempotency(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_worker_code text := lower(btrim(coalesce(p_params->>'worker_code', '')));
  v_idempotency_key text := btrim(coalesce(p_params->>'idempotency_key', ''));
  v_claimed_by_worker text := nullif(btrim(coalesce(p_params->>'claimed_by_worker', '')), '');
  v_terminal boolean := case when p_params ? 'terminal' then (p_params->>'terminal')::boolean else false end;
  v_dead_letter boolean := case when p_params ? 'dead_letter' then (p_params->>'dead_letter')::boolean else true end;
  v_error_code text := btrim(coalesce(nullif(p_params->>'error_code', ''), 'UNKNOWN_ERROR'));
  v_error_message text := btrim(coalesce(nullif(p_params->>'error_message', ''), 'Async job failed.'));
  v_error_details jsonb := coalesce(p_params->'error_details', '{}'::jsonb);
  v_job_id uuid;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;
  if v_worker_code = '' then
    return public.platform_json_response(false, 'WORKER_CODE_REQUIRED', 'worker_code is required.', '{}'::jsonb);
  end if;
  if v_idempotency_key = '' then
    return public.platform_json_response(false, 'IDEMPOTENCY_KEY_REQUIRED', 'idempotency_key is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_error_details) <> 'object' then
    return public.platform_json_response(false, 'INVALID_ERROR_DETAILS', 'error_details must be a JSON object.', '{}'::jsonb);
  end if;

  v_job_id := public.platform_sim_resolve_async_job_id(v_tenant_id, v_worker_code, v_idempotency_key);
  if v_job_id is null then
    return public.platform_json_response(false, 'ASYNC_JOB_NOT_FOUND', 'Async job not found for the tenant worker/idempotency locator.', jsonb_build_object(
      'tenant_id', v_tenant_id,
      'worker_code', v_worker_code,
      'idempotency_key', v_idempotency_key
    ));
  end if;

  return public.platform_async_fail_job(jsonb_build_object(
    'job_id', v_job_id,
    'claimed_by_worker', v_claimed_by_worker,
    'terminal', v_terminal,
    'dead_letter', v_dead_letter,
    'error_code', v_error_code,
    'error_message', v_error_message,
    'error_details', v_error_details
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_sim_fail_async_job_by_idempotency.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_sim_set_async_job_next_retry_at(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_worker_code text := lower(btrim(coalesce(p_params->>'worker_code', '')));
  v_idempotency_key text := btrim(coalesce(p_params->>'idempotency_key', ''));
  v_next_retry_at timestamptz := coalesce((p_params->>'next_retry_at')::timestamptz, timezone('utc', now()) - interval '1 minute');
  v_job_id uuid;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;
  if v_worker_code = '' then
    return public.platform_json_response(false, 'WORKER_CODE_REQUIRED', 'worker_code is required.', '{}'::jsonb);
  end if;
  if v_idempotency_key = '' then
    return public.platform_json_response(false, 'IDEMPOTENCY_KEY_REQUIRED', 'idempotency_key is required.', '{}'::jsonb);
  end if;

  v_job_id := public.platform_sim_resolve_async_job_id(v_tenant_id, v_worker_code, v_idempotency_key);
  if v_job_id is null then
    return public.platform_json_response(false, 'ASYNC_JOB_NOT_FOUND', 'Async job not found for the tenant worker/idempotency locator.', jsonb_build_object(
      'tenant_id', v_tenant_id,
      'worker_code', v_worker_code,
      'idempotency_key', v_idempotency_key
    ));
  end if;

  update public.platform_async_job
  set next_retry_at = v_next_retry_at,
      updated_at = timezone('utc', now())
  where job_id = v_job_id;

  return public.platform_json_response(true, 'OK', 'Async job next_retry_at updated for simulator proof.', jsonb_build_object(
    'job_id', v_job_id,
    'next_retry_at', v_next_retry_at
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_sim_set_async_job_next_retry_at.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_sim_set_async_job_lease_expired(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_worker_code text := lower(btrim(coalesce(p_params->>'worker_code', '')));
  v_idempotency_key text := btrim(coalesce(p_params->>'idempotency_key', ''));
  v_lease_expires_at timestamptz := coalesce((p_params->>'lease_expires_at')::timestamptz, timezone('utc', now()) - interval '1 minute');
  v_job_id uuid;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;
  if v_worker_code = '' then
    return public.platform_json_response(false, 'WORKER_CODE_REQUIRED', 'worker_code is required.', '{}'::jsonb);
  end if;
  if v_idempotency_key = '' then
    return public.platform_json_response(false, 'IDEMPOTENCY_KEY_REQUIRED', 'idempotency_key is required.', '{}'::jsonb);
  end if;

  v_job_id := public.platform_sim_resolve_async_job_id(v_tenant_id, v_worker_code, v_idempotency_key);
  if v_job_id is null then
    return public.platform_json_response(false, 'ASYNC_JOB_NOT_FOUND', 'Async job not found for the tenant worker/idempotency locator.', jsonb_build_object(
      'tenant_id', v_tenant_id,
      'worker_code', v_worker_code,
      'idempotency_key', v_idempotency_key
    ));
  end if;

  update public.platform_async_job
  set lease_expires_at = v_lease_expires_at,
      updated_at = timezone('utc', now())
  where job_id = v_job_id;

  return public.platform_json_response(true, 'OK', 'Async job lease_expires_at updated for simulator proof.', jsonb_build_object(
    'job_id', v_job_id,
    'lease_expires_at', v_lease_expires_at
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_sim_set_async_job_lease_expired.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

revoke all on function public.platform_sim_resolve_async_job_id(uuid, text, text) from public, anon, authenticated, service_role;
revoke all on function public.platform_sim_heartbeat_async_job_by_idempotency(jsonb) from public, anon, authenticated;
revoke all on function public.platform_sim_complete_async_job_by_idempotency(jsonb) from public, anon, authenticated;
revoke all on function public.platform_sim_fail_async_job_by_idempotency(jsonb) from public, anon, authenticated;
revoke all on function public.platform_sim_set_async_job_next_retry_at(jsonb) from public, anon, authenticated;
revoke all on function public.platform_sim_set_async_job_lease_expired(jsonb) from public, anon, authenticated;

grant execute on function public.platform_sim_heartbeat_async_job_by_idempotency(jsonb) to service_role;
grant execute on function public.platform_sim_complete_async_job_by_idempotency(jsonb) to service_role;
grant execute on function public.platform_sim_fail_async_job_by_idempotency(jsonb) to service_role;
grant execute on function public.platform_sim_set_async_job_next_retry_at(jsonb) to service_role;
grant execute on function public.platform_sim_set_async_job_lease_expired(jsonb) to service_role;;
