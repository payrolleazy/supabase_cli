create or replace function public.platform_async_recover_stale_jobs(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_worker_code text := nullif(lower(btrim(coalesce(p_params->>'worker_code', ''))), '');
  v_module_code text := nullif(upper(btrim(coalesce(p_params->>'module_code', ''))), '');
  v_max_rows integer := greatest(coalesce((p_params->>'max_rows')::integer, 100), 1);
  v_now timestamptz := timezone('utc', now());
  v_rows jsonb;
begin
  with stale_rows as (
    select
      paj.job_id,
      paj.worker_code,
      paj.attempt_count,
      paj.max_attempts,
      pawr.retry_backoff_policy,
      ptrv.background_processing_allowed,
      ptrv.access_state
    from public.platform_async_job paj
    join public.platform_async_worker_registry pawr on pawr.worker_code = paj.worker_code
    join public.platform_tenant_registry_view ptrv on ptrv.tenant_id = paj.tenant_id
    where paj.job_state in ('claimed', 'running')
      and paj.lease_expires_at is not null
      and paj.lease_expires_at < v_now
      and (v_worker_code is null or paj.worker_code = v_worker_code)
      and (v_module_code is null or paj.module_code = v_module_code)
    order by paj.lease_expires_at asc
    limit v_max_rows
    for update skip locked
  ),
  resolved as (
    update public.platform_async_job paj
    set job_state = case
          when stale_rows.background_processing_allowed = false then 'retry_wait'
          when stale_rows.attempt_count >= stale_rows.max_attempts then 'dead_lettered'
          else 'retry_wait'
        end,
        next_retry_at = case
          when stale_rows.background_processing_allowed = false then null
          when stale_rows.attempt_count >= stale_rows.max_attempts then null
          else public.platform_async_calculate_next_retry_at(stale_rows.attempt_count, stale_rows.retry_backoff_policy)
        end,
        lease_expires_at = null,
        heartbeat_at = null,
        claimed_by_worker = null,
        last_error_code = case
          when stale_rows.background_processing_allowed = false then 'TENANT_BACKGROUND_BLOCKED_DORMANT'
          when stale_rows.attempt_count >= stale_rows.max_attempts then 'LEASE_EXPIRED_RETRY_EXHAUSTED'
          else 'LEASE_EXPIRED'
        end,
        last_error_message = case
          when stale_rows.background_processing_allowed = false then 'Tenant background processing is blocked before stale lease recovery.'
          when stale_rows.attempt_count >= stale_rows.max_attempts then 'Lease expired and retry budget is exhausted.'
          else 'Lease expired before job completion.'
        end,
        last_error_details = jsonb_build_object('recovery_reason', 'lease_expired', 'access_state', stale_rows.access_state),
        dead_lettered_at = case when stale_rows.attempt_count >= stale_rows.max_attempts then v_now else paj.dead_lettered_at end,
        updated_at = v_now
    from stale_rows
    where paj.job_id = stale_rows.job_id
    returning paj.job_id, paj.worker_code, paj.job_state
  ),
  attempt_update as (
    update public.platform_async_job_attempt aja
    set attempt_state = case when r.job_state = 'dead_lettered' then 'failed_terminal' else 'failed_retryable' end,
        completed_at = v_now,
        error_code = case when r.job_state = 'dead_lettered' then 'LEASE_EXPIRED_RETRY_EXHAUSTED' else 'LEASE_EXPIRED' end,
        error_message = case when r.job_state = 'dead_lettered' then 'Lease expired and retry budget is exhausted.' else 'Lease expired before job completion.' end,
        error_details = jsonb_build_object('recovery_reason', 'lease_expired'),
        duration_ms = greatest(0, floor(extract(epoch from (v_now - aja.started_at)) * 1000)::integer)
    from resolved r
    where aja.attempt_id = (
      select attempt_id from public.platform_async_job_attempt
      where job_id = r.job_id and completed_at is null
      order by attempt_number desc
      limit 1
    )
    returning aja.job_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'job_id', r.job_id,
    'worker_code', r.worker_code,
    'job_state', r.job_state
  ) order by r.job_id), '[]'::jsonb)
  into v_rows
  from resolved r;

  return public.platform_json_response(true, 'OK', 'Stale async jobs recovered.', jsonb_build_object(
    'recovered_count', jsonb_array_length(v_rows),
    'jobs', v_rows
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_async_recover_stale_jobs.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_async_capture_health_snapshot(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_module_code text := nullif(upper(btrim(coalesce(p_params->>'module_code', ''))), '');
  v_worker_code text := nullif(lower(btrim(coalesce(p_params->>'worker_code', ''))), '');
  v_tenant_id uuid := public.platform_try_uuid(p_params->>'tenant_id');
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'tenant_id', paqhv.tenant_id,
    'tenant_code', paqhv.tenant_code,
    'tenant_schema', paqhv.tenant_schema,
    'module_code', paqhv.module_code,
    'worker_code', paqhv.worker_code,
    'queued_count', paqhv.queued_count,
    'running_count', paqhv.running_count,
    'retry_wait_count', paqhv.retry_wait_count,
    'dead_letter_count', paqhv.dead_letter_count,
    'stale_lease_count', paqhv.stale_lease_count,
    'oldest_due_at', paqhv.oldest_due_at,
    'last_completed_at', paqhv.last_completed_at
  ) order by paqhv.module_code, paqhv.worker_code, paqhv.tenant_code), '[]'::jsonb)
  into v_rows
  from public.platform_async_queue_health_view paqhv
  where (v_module_code is null or paqhv.module_code = v_module_code)
    and (v_worker_code is null or paqhv.worker_code = v_worker_code)
    and (v_tenant_id is null or paqhv.tenant_id = v_tenant_id);

  return public.platform_json_response(true, 'OK', 'Async queue health snapshot captured.', jsonb_build_object(
    'rows', v_rows,
    'row_count', jsonb_array_length(v_rows)
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_async_capture_health_snapshot.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

revoke all on public.platform_async_worker_registry from public, anon, authenticated;
revoke all on public.platform_async_job from public, anon, authenticated;
revoke all on public.platform_async_job_attempt from public, anon, authenticated;
revoke all on public.platform_async_dispatch_readiness_view from public, anon, authenticated;
revoke all on public.platform_async_stale_lease_view from public, anon, authenticated;
revoke all on public.platform_async_dead_letter_view from public, anon, authenticated;
revoke all on public.platform_async_queue_health_view from public, anon, authenticated;

revoke all on function public.platform_async_calculate_next_retry_at(integer, jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_async_worker(jsonb) from public, anon, authenticated;
revoke all on function public.platform_async_enqueue_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_async_dispatch_due_jobs(jsonb) from public, anon, authenticated;
revoke all on function public.platform_async_claim_jobs(jsonb) from public, anon, authenticated;
revoke all on function public.platform_async_heartbeat_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_async_complete_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_async_fail_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_async_recover_stale_jobs(jsonb) from public, anon, authenticated;
revoke all on function public.platform_async_capture_health_snapshot(jsonb) from public, anon, authenticated;

grant select on public.platform_async_dispatch_readiness_view to service_role;
grant select on public.platform_async_stale_lease_view to service_role;
grant select on public.platform_async_dead_letter_view to service_role;
grant select on public.platform_async_queue_health_view to service_role;

grant execute on function public.platform_async_calculate_next_retry_at(integer, jsonb) to service_role;
grant execute on function public.platform_register_async_worker(jsonb) to service_role;
grant execute on function public.platform_async_enqueue_job(jsonb) to service_role;
grant execute on function public.platform_async_dispatch_due_jobs(jsonb) to service_role;
grant execute on function public.platform_async_claim_jobs(jsonb) to service_role;
grant execute on function public.platform_async_heartbeat_job(jsonb) to service_role;
grant execute on function public.platform_async_complete_job(jsonb) to service_role;
grant execute on function public.platform_async_fail_job(jsonb) to service_role;
grant execute on function public.platform_async_recover_stale_jobs(jsonb) to service_role;
grant execute on function public.platform_async_capture_health_snapshot(jsonb) to service_role;;
