create or replace function public.platform_signup_circuit_breaker_check(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_breaker_code text := lower(coalesce(nullif(btrim(coalesce(p_params->>'breaker_code', '')), ''), 'primary'));
  v_breaker public.platform_signup_circuit_breaker%rowtype;
  v_now timestamptz := timezone('utc', now());
  v_is_allowed boolean := true;
begin
  select * into v_breaker
  from public.platform_signup_circuit_breaker
  where breaker_code = v_breaker_code
  for update;

  if not found then
    return public.platform_json_response(false, 'BREAKER_NOT_FOUND', 'Signup circuit breaker not found.', jsonb_build_object('breaker_code', v_breaker_code));
  end if;

  if v_breaker.breaker_state = 'open'
     and v_breaker.last_opened_at is not null
     and v_breaker.last_opened_at + make_interval(secs => v_breaker.cooldown_seconds) <= v_now then
    update public.platform_signup_circuit_breaker
    set breaker_state = 'half_open',
        success_count = 0,
        last_state_changed_at = v_now,
        updated_at = v_now
    where breaker_code = v_breaker_code
    returning * into v_breaker;
  elsif v_breaker.breaker_state = 'open' then
    v_is_allowed := false;
  end if;

  return public.platform_json_response(true, 'OK', 'Signup circuit breaker evaluated.', jsonb_build_object(
    'breaker_code', v_breaker.breaker_code,
    'breaker_state', v_breaker.breaker_state,
    'is_allowed', v_is_allowed,
    'failure_count', v_breaker.failure_count,
    'success_count', v_breaker.success_count,
    'error_threshold', v_breaker.error_threshold,
    'success_threshold', v_breaker.success_threshold,
    'cooldown_seconds', v_breaker.cooldown_seconds,
    'last_opened_at', v_breaker.last_opened_at,
    'last_failure_at', v_breaker.last_failure_at,
    'last_success_at', v_breaker.last_success_at
  ));
end;
$function$;

create or replace function public.platform_signup_circuit_breaker_record_success(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_breaker_code text := lower(coalesce(nullif(btrim(coalesce(p_params->>'breaker_code', '')), ''), 'primary'));
  v_now timestamptz := timezone('utc', now());
  v_breaker public.platform_signup_circuit_breaker%rowtype;
  v_next_success_count integer;
begin
  select * into v_breaker
  from public.platform_signup_circuit_breaker
  where breaker_code = v_breaker_code
  for update;

  if not found then
    return public.platform_json_response(false, 'BREAKER_NOT_FOUND', 'Signup circuit breaker not found.', jsonb_build_object('breaker_code', v_breaker_code));
  end if;

  v_next_success_count := v_breaker.success_count + 1;

  if v_breaker.breaker_state = 'half_open' and v_next_success_count >= v_breaker.success_threshold then
    update public.platform_signup_circuit_breaker
    set breaker_state = 'closed',
        failure_count = 0,
        success_count = 0,
        last_success_at = v_now,
        last_state_changed_at = v_now,
        updated_at = v_now,
        last_error_code = null,
        last_error_message = null
    where breaker_code = v_breaker_code
    returning * into v_breaker;
  else
    update public.platform_signup_circuit_breaker
    set success_count = case when breaker_state = 'half_open' then v_next_success_count else 0 end,
        failure_count = case when breaker_state = 'closed' then 0 else failure_count end,
        last_success_at = v_now,
        updated_at = v_now
    where breaker_code = v_breaker_code
    returning * into v_breaker;
  end if;

  return public.platform_json_response(true, 'OK', 'Signup circuit breaker success recorded.', jsonb_build_object(
    'breaker_code', v_breaker.breaker_code,
    'breaker_state', v_breaker.breaker_state,
    'failure_count', v_breaker.failure_count,
    'success_count', v_breaker.success_count
  ));
end;
$function$;

create or replace function public.platform_signup_circuit_breaker_record_failure(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_breaker_code text := lower(coalesce(nullif(btrim(coalesce(p_params->>'breaker_code', '')), ''), 'primary'));
  v_error_code text := coalesce(nullif(btrim(coalesce(p_params->>'error_code', '')), ''), 'UNKNOWN_ERROR');
  v_error_message text := coalesce(nullif(btrim(coalesce(p_params->>'error_message', '')), ''), 'Signup worker failure');
  v_now timestamptz := timezone('utc', now());
  v_breaker public.platform_signup_circuit_breaker%rowtype;
  v_next_failure_count integer;
  v_target_state text;
begin
  select * into v_breaker
  from public.platform_signup_circuit_breaker
  where breaker_code = v_breaker_code
  for update;

  if not found then
    return public.platform_json_response(false, 'BREAKER_NOT_FOUND', 'Signup circuit breaker not found.', jsonb_build_object('breaker_code', v_breaker_code));
  end if;

  v_next_failure_count := v_breaker.failure_count + 1;
  v_target_state := case
    when v_breaker.breaker_state = 'half_open' then 'open'
    when v_next_failure_count >= v_breaker.error_threshold then 'open'
    else 'closed'
  end;

  update public.platform_signup_circuit_breaker
  set breaker_state = v_target_state,
      failure_count = v_next_failure_count,
      success_count = 0,
      last_error_code = v_error_code,
      last_error_message = v_error_message,
      last_failure_at = v_now,
      last_opened_at = case when v_target_state = 'open' then v_now else last_opened_at end,
      last_state_changed_at = case when breaker_state <> v_target_state then v_now else last_state_changed_at end,
      updated_at = v_now
  where breaker_code = v_breaker_code
  returning * into v_breaker;

  return public.platform_json_response(true, 'OK', 'Signup circuit breaker failure recorded.', jsonb_build_object(
    'breaker_code', v_breaker.breaker_code,
    'breaker_state', v_breaker.breaker_state,
    'failure_count', v_breaker.failure_count,
    'last_error_code', v_breaker.last_error_code
  ));
end;
$function$;

create or replace function public.platform_enqueue_signup_request(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_signup_request_id uuid := public.platform_try_uuid(p_params->>'signup_request_id');
  v_full_name text := nullif(btrim(coalesce(p_params->>'full_name', '')), '');
  v_role_code text := nullif(lower(btrim(coalesce(p_params->>'role_code', ''))), '');
  v_encrypted_credentials jsonb := coalesce(p_params->'encrypted_credentials', '{}'::jsonb);
  v_priority integer := greatest(coalesce((p_params->>'priority')::integer, 100), 1);
  v_max_attempts integer := greatest(coalesce((p_params->>'max_attempts')::integer, 5), 1);
  v_signup_request public.platform_signup_request%rowtype;
  v_invitation public.platform_membership_invitation%rowtype;
  v_existing_job public.platform_async_job%rowtype;
  v_enqueue_result jsonb;
  v_enqueue_details jsonb;
  v_job_id uuid;
  v_now timestamptz := timezone('utc', now());
begin
  if v_signup_request_id is null then
    return public.platform_json_response(false, 'SIGNUP_REQUEST_ID_REQUIRED', 'signup_request_id is required.', '{}'::jsonb);
  end if;
  if v_full_name is null then
    return public.platform_json_response(false, 'FULL_NAME_REQUIRED', 'full_name is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_encrypted_credentials) <> 'object' then
    return public.platform_json_response(false, 'INVALID_ENCRYPTED_CREDENTIALS', 'encrypted_credentials must be a JSON object.', '{}'::jsonb);
  end if;

  select * into v_signup_request
  from public.platform_signup_request
  where signup_request_id = v_signup_request_id
  for update;

  if not found then
    return public.platform_json_response(false, 'SIGNUP_REQUEST_NOT_FOUND', 'Signup request not found.', jsonb_build_object('signup_request_id', v_signup_request_id));
  end if;
  if v_signup_request.request_status = 'denied' then
    return public.platform_json_response(false, 'SIGNUP_REQUEST_DENIED', 'Signup request is not queueable.', jsonb_build_object('request_status', v_signup_request.request_status));
  end if;
  if v_signup_request.request_status in ('completed', 'failed') then
    return public.platform_json_response(false, 'SIGNUP_REQUEST_NOT_QUEUEABLE', 'Signup request is already terminal.', jsonb_build_object('request_status', v_signup_request.request_status));
  end if;
  if v_signup_request.invitation_id is null then
    return public.platform_json_response(false, 'SIGNUP_REQUEST_NOT_INVITED', 'Signup request has no invitation binding.', jsonb_build_object('signup_request_id', v_signup_request_id));
  end if;

  select * into v_invitation
  from public.platform_membership_invitation
  where invitation_id = v_signup_request.invitation_id;

  if not found then
    return public.platform_json_response(false, 'INVITATION_NOT_FOUND', 'Invitation not found.', jsonb_build_object('invitation_id', v_signup_request.invitation_id));
  end if;

  if v_signup_request.async_job_id is not null then
    select * into v_existing_job
    from public.platform_async_job
    where job_id = v_signup_request.async_job_id;

    if found and v_existing_job.job_state in ('queued', 'claimed', 'running', 'retry_wait', 'completed') then
      return public.platform_json_response(true, 'OK', 'Signup request already has an async job.', jsonb_build_object(
        'signup_request_id', v_signup_request.signup_request_id,
        'job_id', v_existing_job.job_id,
        'job_state', v_existing_job.job_state,
        'worker_code', v_existing_job.worker_code
      ));
    end if;
  end if;

  v_enqueue_result := public.platform_async_enqueue_job(jsonb_build_object(
    'tenant_id', v_invitation.tenant_id,
    'worker_code', 'i01_signup_worker',
    'job_type', 'invited_signup',
    'priority', v_priority,
    'max_attempts', v_max_attempts,
    'origin_source', 'identity-signup-request',
    'idempotency_key', 'signup_request:' || v_signup_request.signup_request_id::text,
    'deduplication_key', 'signup_request:' || v_signup_request.signup_request_id::text,
    'payload', jsonb_build_object(
      'signup_request_id', v_signup_request.signup_request_id,
      'invitation_id', v_signup_request.invitation_id,
      'email', v_signup_request.email,
      'mobile_no', v_signup_request.mobile_no,
      'full_name', v_full_name,
      'role_code', coalesce(v_role_code, v_invitation.role_code),
      'encrypted_credentials', v_encrypted_credentials
    ),
    'metadata', jsonb_build_object('signup_request_id', v_signup_request.signup_request_id)
  ));

  if coalesce((v_enqueue_result->>'success')::boolean, false) = false then
    return v_enqueue_result;
  end if;

  v_enqueue_details := coalesce(v_enqueue_result->'details', '{}'::jsonb);
  v_job_id := public.platform_try_uuid(v_enqueue_details->>'job_id');

  update public.platform_signup_request
  set request_status = 'queued',
      async_job_id = v_job_id,
      decision_reason = 'SIGNUP_QUEUED',
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'last_async_enqueue_at', to_jsonb(v_now),
        'last_async_worker_code', 'i01_signup_worker'
      ),
      updated_at = v_now
  where signup_request_id = v_signup_request.signup_request_id;

  perform public.platform_identity_write_event(jsonb_build_object(
    'event_type', 'signup_request_queued',
    'tenant_id', v_invitation.tenant_id,
    'invitation_id', v_signup_request.invitation_id,
    'signup_request_id', v_signup_request.signup_request_id,
    'message', 'Signup request queued for async processing.',
    'details', jsonb_build_object('job_id', v_job_id, 'worker_code', 'i01_signup_worker')
  ));

  return public.platform_json_response(true, 'OK', 'Signup request queued.', jsonb_build_object(
    'signup_request_id', v_signup_request.signup_request_id,
    'job_id', v_job_id,
    'job_state', 'queued',
    'worker_code', 'i01_signup_worker'
  ));
end;
$function$;

create or replace function public.platform_capture_signup_metrics(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_parallel_invocation_target integer := greatest(coalesce((p_params->>'parallel_invocation_target')::integer, 1), 1);
  v_configured_batch_size integer := greatest(coalesce((p_params->>'configured_batch_size')::integer, 1), 1);
  v_queue record;
  v_breaker public.platform_signup_circuit_breaker%rowtype;
  v_worker public.platform_async_worker_registry%rowtype;
  v_metric_id bigint;
begin
  select * into v_queue
  from public.platform_async_queue_health_view
  where worker_code = 'i01_signup_worker'
  limit 1;

  select * into v_breaker
  from public.platform_signup_circuit_breaker
  where breaker_code = 'primary';

  select * into v_worker
  from public.platform_async_worker_registry
  where worker_code = 'i01_signup_worker';

  insert into public.platform_signup_metrics (
    queue_depth,
    retry_wait_depth,
    running_depth,
    dead_letter_depth,
    stale_lease_depth,
    oldest_due_at,
    parallel_invocation_target,
    configured_batch_size,
    breaker_state,
    worker_active,
    metadata
  ) values (
    coalesce(v_queue.queued_count, 0),
    coalesce(v_queue.retry_wait_count, 0),
    coalesce(v_queue.running_count, 0),
    coalesce(v_queue.dead_letter_count, 0),
    coalesce(v_queue.stale_lease_count, 0),
    v_queue.oldest_due_at,
    v_parallel_invocation_target,
    v_configured_batch_size,
    coalesce(v_breaker.breaker_state, 'closed'),
    coalesce(v_worker.is_active, false),
    coalesce(p_params->'metadata', '{}'::jsonb)
  )
  returning metric_id into v_metric_id;

  return public.platform_json_response(true, 'OK', 'Signup metrics captured.', jsonb_build_object(
    'metric_id', v_metric_id,
    'queue_depth', coalesce(v_queue.queued_count, 0),
    'retry_wait_depth', coalesce(v_queue.retry_wait_count, 0),
    'running_depth', coalesce(v_queue.running_count, 0),
    'dead_letter_depth', coalesce(v_queue.dead_letter_count, 0)
  ));
end;
$function$;

create or replace function public.platform_cleanup_signin_runtime(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_attempt_retention_days integer := greatest(coalesce((p_params->>'attempt_retention_days')::integer, 30), 1);
  v_challenge_retention_days integer := greatest(coalesce((p_params->>'challenge_retention_days')::integer, 7), 1);
  v_now timestamptz := timezone('utc', now());
  v_expired_count integer := 0;
  v_deleted_challenge_count integer := 0;
  v_deleted_attempt_count integer := 0;
begin
  update public.platform_signin_challenge
  set challenge_status = 'expired',
      updated_at = v_now
  where challenge_status = 'issued'
    and expires_at <= v_now;
  get diagnostics v_expired_count = row_count;

  delete from public.platform_signin_challenge
  where challenge_status in ('consumed', 'expired', 'cancelled')
    and updated_at < v_now - make_interval(days => v_challenge_retention_days);
  get diagnostics v_deleted_challenge_count = row_count;

  delete from public.platform_signin_attempt_log
  where created_at < v_now - make_interval(days => v_attempt_retention_days);
  get diagnostics v_deleted_attempt_count = row_count;

  perform public.platform_identity_write_event(jsonb_build_object(
    'event_type', 'signin_runtime_cleanup_completed',
    'message', 'Signin runtime cleanup completed.',
    'details', jsonb_build_object(
      'expired_count', v_expired_count,
      'deleted_challenge_count', v_deleted_challenge_count,
      'deleted_attempt_count', v_deleted_attempt_count,
      'attempt_retention_days', v_attempt_retention_days,
      'challenge_retention_days', v_challenge_retention_days
    )
  ));

  return public.platform_json_response(true, 'OK', 'Signin runtime cleanup completed.', jsonb_build_object(
    'expired_count', v_expired_count,
    'deleted_challenge_count', v_deleted_challenge_count,
    'deleted_attempt_count', v_deleted_attempt_count
  ));
end;
$function$;

revoke all on function public.platform_signup_circuit_breaker_check(jsonb) from public, anon, authenticated;
revoke all on function public.platform_signup_circuit_breaker_record_success(jsonb) from public, anon, authenticated;
revoke all on function public.platform_signup_circuit_breaker_record_failure(jsonb) from public, anon, authenticated;
revoke all on function public.platform_enqueue_signup_request(jsonb) from public, anon, authenticated;
revoke all on function public.platform_capture_signup_metrics(jsonb) from public, anon, authenticated;
revoke all on function public.platform_cleanup_signin_runtime(jsonb) from public, anon, authenticated;

grant execute on function public.platform_signup_circuit_breaker_check(jsonb) to service_role;
grant execute on function public.platform_signup_circuit_breaker_record_success(jsonb) to service_role;
grant execute on function public.platform_signup_circuit_breaker_record_failure(jsonb) to service_role;
grant execute on function public.platform_enqueue_signup_request(jsonb) to service_role;
grant execute on function public.platform_capture_signup_metrics(jsonb) to service_role;
grant execute on function public.platform_cleanup_signin_runtime(jsonb) to service_role;
