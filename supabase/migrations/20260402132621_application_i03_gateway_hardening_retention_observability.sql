create table if not exists public.platform_gateway_maintenance_run (
  run_id uuid primary key default gen_random_uuid(),
  maintenance_code text not null,
  run_status text not null default 'running'
    check (run_status in ('running', 'succeeded', 'failed')),
  request_log_retention_days integer not null default 7
    check (request_log_retention_days > 0),
  idempotency_grace_hours integer not null default 24
    check (idempotency_grace_hours > 0),
  request_log_deleted_count integer not null default 0
    check (request_log_deleted_count >= 0),
  idempotency_deleted_count integer not null default 0
    check (idempotency_deleted_count >= 0),
  oldest_deleted_request_created_at timestamptz null,
  oldest_deleted_claim_expires_at timestamptz null,
  details jsonb not null default '{}'::jsonb
    check (jsonb_typeof(details) = 'object'),
  started_at timestamptz not null default timezone('utc', now()),
  completed_at timestamptz null
);

create index if not exists idx_platform_gateway_maintenance_run_started_at
  on public.platform_gateway_maintenance_run (started_at desc);

create index if not exists idx_platform_gateway_request_log_created_at
  on public.platform_gateway_request_log (created_at desc);

alter table public.platform_gateway_maintenance_run enable row level security;

drop policy if exists platform_gateway_maintenance_run_service_role_all
  on public.platform_gateway_maintenance_run;
create policy platform_gateway_maintenance_run_service_role_all
on public.platform_gateway_maintenance_run
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create or replace function public.platform_cleanup_gateway_request_log(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_retention_days integer := 7;
  v_cutoff timestamptz;
  v_deleted_count integer := 0;
  v_oldest_deleted timestamptz;
  v_newest_deleted timestamptz;
begin
  if p_params is not null and jsonb_typeof(p_params) <> 'object' then
    return public.platform_json_response(false, 'INVALID_PARAMS', 'p_params must be a JSON object.', '{}'::jsonb);
  end if;

  if nullif(coalesce(p_params, '{}'::jsonb)->>'retention_days', '') is not null then
    begin
      v_retention_days := greatest(((coalesce(p_params, '{}'::jsonb)->>'retention_days')::integer), 1);
    exception
      when others then
        return public.platform_json_response(false, 'INVALID_RETENTION_DAYS', 'retention_days must be a positive integer.', '{}'::jsonb);
    end;
  end if;

  v_cutoff := timezone('utc', now()) - make_interval(days => v_retention_days);

  with deleted_rows as (
    delete from public.platform_gateway_request_log
    where created_at < v_cutoff
    returning created_at
  )
  select count(*)::integer,
         min(created_at),
         max(created_at)
  into v_deleted_count,
       v_oldest_deleted,
       v_newest_deleted
  from deleted_rows;

  return public.platform_json_response(
    true,
    'OK',
    'Gateway request log cleanup completed.',
    jsonb_build_object(
      'retention_days', v_retention_days,
      'cutoff', v_cutoff,
      'deleted_count', coalesce(v_deleted_count, 0),
      'oldest_deleted_created_at', v_oldest_deleted,
      'newest_deleted_created_at', v_newest_deleted
    )
  );
end;
$function$;

create or replace function public.platform_cleanup_gateway_idempotency_claim(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_grace_hours integer := 24;
  v_cutoff timestamptz;
  v_deleted_count integer := 0;
  v_oldest_deleted timestamptz;
  v_newest_deleted timestamptz;
begin
  if p_params is not null and jsonb_typeof(p_params) <> 'object' then
    return public.platform_json_response(false, 'INVALID_PARAMS', 'p_params must be a JSON object.', '{}'::jsonb);
  end if;

  if nullif(coalesce(p_params, '{}'::jsonb)->>'grace_hours', '') is not null then
    begin
      v_grace_hours := greatest(((coalesce(p_params, '{}'::jsonb)->>'grace_hours')::integer), 1);
    exception
      when others then
        return public.platform_json_response(false, 'INVALID_GRACE_HOURS', 'grace_hours must be a positive integer.', '{}'::jsonb);
    end;
  end if;

  v_cutoff := timezone('utc', now()) - make_interval(hours => v_grace_hours);

  with deleted_rows as (
    delete from public.platform_gateway_idempotency_claim
    where expires_at < v_cutoff
    returning expires_at
  )
  select count(*)::integer,
         min(expires_at),
         max(expires_at)
  into v_deleted_count,
       v_oldest_deleted,
       v_newest_deleted
  from deleted_rows;

  return public.platform_json_response(
    true,
    'OK',
    'Gateway idempotency cleanup completed.',
    jsonb_build_object(
      'grace_hours', v_grace_hours,
      'cutoff', v_cutoff,
      'deleted_count', coalesce(v_deleted_count, 0),
      'oldest_deleted_expires_at', v_oldest_deleted,
      'newest_deleted_expires_at', v_newest_deleted
    )
  );
end;
$function$;

create or replace function public.platform_i03_run_gateway_maintenance_scheduler()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_run_id uuid;
  v_request_cleanup jsonb;
  v_idempotency_cleanup jsonb;
  v_request_deleted integer := 0;
  v_idempotency_deleted integer := 0;
  v_oldest_request_created_at timestamptz;
  v_oldest_claim_expires_at timestamptz;
begin
  insert into public.platform_gateway_maintenance_run (
    maintenance_code,
    run_status,
    request_log_retention_days,
    idempotency_grace_hours,
    details
  )
  values (
    'i03_gateway_maintenance',
    'running',
    7,
    24,
    jsonb_build_object('trigger', 'pg_cron')
  )
  returning run_id
  into v_run_id;

  v_request_cleanup := public.platform_cleanup_gateway_request_log(
    jsonb_build_object('retention_days', 7)
  );

  if coalesce((v_request_cleanup->>'success')::boolean, false) is not true then
    update public.platform_gateway_maintenance_run
    set run_status = 'failed',
        completed_at = timezone('utc', now()),
        details = coalesce(details, '{}'::jsonb) || jsonb_build_object('request_cleanup', v_request_cleanup)
    where run_id = v_run_id;

    return v_request_cleanup;
  end if;

  v_idempotency_cleanup := public.platform_cleanup_gateway_idempotency_claim(
    jsonb_build_object('grace_hours', 24)
  );

  if coalesce((v_idempotency_cleanup->>'success')::boolean, false) is not true then
    update public.platform_gateway_maintenance_run
    set run_status = 'failed',
        completed_at = timezone('utc', now()),
        details = coalesce(details, '{}'::jsonb)
          || jsonb_build_object(
            'request_cleanup', v_request_cleanup,
            'idempotency_cleanup', v_idempotency_cleanup
          )
    where run_id = v_run_id;

    return v_idempotency_cleanup;
  end if;

  v_request_deleted := coalesce((v_request_cleanup->'details'->>'deleted_count')::integer, 0);
  v_idempotency_deleted := coalesce((v_idempotency_cleanup->'details'->>'deleted_count')::integer, 0);
  v_oldest_request_created_at := nullif(v_request_cleanup->'details'->>'oldest_deleted_created_at', '')::timestamptz;
  v_oldest_claim_expires_at := nullif(v_idempotency_cleanup->'details'->>'oldest_deleted_expires_at', '')::timestamptz;

  update public.platform_gateway_maintenance_run
  set run_status = 'succeeded',
      request_log_deleted_count = v_request_deleted,
      idempotency_deleted_count = v_idempotency_deleted,
      oldest_deleted_request_created_at = v_oldest_request_created_at,
      oldest_deleted_claim_expires_at = v_oldest_claim_expires_at,
      details = coalesce(details, '{}'::jsonb)
        || jsonb_build_object(
          'request_cleanup', v_request_cleanup,
          'idempotency_cleanup', v_idempotency_cleanup
        ),
      completed_at = timezone('utc', now())
  where run_id = v_run_id;

  return public.platform_json_response(
    true,
    'OK',
    'I03 gateway maintenance completed.',
    jsonb_build_object(
      'run_id', v_run_id,
      'request_log_deleted_count', v_request_deleted,
      'idempotency_deleted_count', v_idempotency_deleted,
      'request_cleanup', v_request_cleanup,
      'idempotency_cleanup', v_idempotency_cleanup
    )
  );
exception
  when others then
    if v_run_id is not null then
      update public.platform_gateway_maintenance_run
      set run_status = 'failed',
          completed_at = timezone('utc', now()),
          details = coalesce(details, '{}'::jsonb)
            || jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
      where run_id = v_run_id;
    end if;

    return public.platform_json_response(
      false,
      'UNEXPECTED_ERROR',
      'Unexpected error in platform_i03_run_gateway_maintenance_scheduler.',
      jsonb_build_object('run_id', v_run_id, 'sqlstate', sqlstate, 'sqlerrm', sqlerrm)
    );
end;
$function$;

create or replace view public.platform_rm_gateway_runtime_overview
with (security_invoker = true)
as
with operation_stats as (
  select
    count(*)::integer as registered_operation_count,
    count(*) filter (where operation_status = 'active')::integer as active_operation_count,
    count(*) filter (where dispatch_kind = 'read_surface')::integer as read_surface_count,
    count(*) filter (where dispatch_kind = 'mutation_adapter')::integer as mutation_adapter_count,
    count(*) filter (where dispatch_kind = 'function_action')::integer as function_action_count
  from public.platform_gateway_operation
),
request_stats as (
  select
    count(*)::integer as request_log_total_count,
    count(*) filter (where created_at >= timezone('utc', now()) - interval '24 hours')::integer as request_count_24h,
    count(*) filter (where created_at >= timezone('utc', now()) - interval '7 days')::integer as request_count_7d,
    count(*) filter (where created_at >= timezone('utc', now()) - interval '24 hours' and request_status = 'succeeded')::integer as succeeded_count_24h,
    count(*) filter (where created_at >= timezone('utc', now()) - interval '24 hours' and request_status = 'blocked')::integer as blocked_count_24h,
    count(*) filter (where created_at >= timezone('utc', now()) - interval '24 hours' and request_status = 'failed')::integer as failed_count_24h,
    count(*) filter (where created_at >= timezone('utc', now()) - interval '24 hours' and request_status = 'replayed')::integer as replayed_count_24h,
    count(distinct actor_user_id) filter (where created_at >= timezone('utc', now()) - interval '24 hours')::integer as distinct_actor_count_24h,
    min(created_at) as oldest_request_log_at,
    max(created_at) as newest_request_log_at
  from public.platform_gateway_request_log
),
idempotency_stats as (
  select
    count(*)::integer as idempotency_total_count,
    count(*) filter (where expires_at < timezone('utc', now()))::integer as expired_idempotency_count,
    count(*) filter (where claim_status = 'claimed' and expires_at >= timezone('utc', now()))::integer as claimed_unexpired_count,
    min(expires_at) filter (where expires_at < timezone('utc', now())) as oldest_expired_expires_at
  from public.platform_gateway_idempotency_claim
),
latest_maintenance as (
  select
    run_id,
    run_status,
    started_at,
    completed_at,
    request_log_deleted_count,
    idempotency_deleted_count
  from public.platform_gateway_maintenance_run
  order by started_at desc
  limit 1
)
select
  timezone('utc', now()) as captured_at,
  os.registered_operation_count,
  os.active_operation_count,
  os.read_surface_count,
  os.mutation_adapter_count,
  os.function_action_count,
  rs.request_log_total_count,
  rs.request_count_24h,
  rs.request_count_7d,
  rs.succeeded_count_24h,
  rs.blocked_count_24h,
  rs.failed_count_24h,
  rs.replayed_count_24h,
  rs.distinct_actor_count_24h,
  rs.oldest_request_log_at,
  rs.newest_request_log_at,
  ids.idempotency_total_count,
  ids.expired_idempotency_count,
  ids.claimed_unexpired_count,
  ids.oldest_expired_expires_at,
  lm.run_id as latest_maintenance_run_id,
  lm.run_status as latest_maintenance_status,
  lm.started_at as latest_maintenance_started_at,
  lm.completed_at as latest_maintenance_completed_at,
  lm.request_log_deleted_count as latest_request_log_deleted_count,
  lm.idempotency_deleted_count as latest_idempotency_deleted_count
from operation_stats os
cross join request_stats rs
cross join idempotency_stats ids
left join latest_maintenance lm on true;

create or replace view public.platform_rm_gateway_error_breakdown
with (security_invoker = true)
as
select
  error_code,
  request_status,
  count(*) filter (where created_at >= timezone('utc', now()) - interval '24 hours')::integer as error_count_24h,
  count(*) filter (where created_at >= timezone('utc', now()) - interval '7 days')::integer as error_count_7d,
  max(created_at) as latest_seen_at
from public.platform_gateway_request_log
where error_code is not null
group by error_code, request_status;

create or replace view public.platform_rm_gateway_maintenance_status
with (security_invoker = true)
as
with latest_maintenance as (
  select
    run_id,
    maintenance_code,
    run_status,
    request_log_retention_days,
    idempotency_grace_hours,
    request_log_deleted_count,
    idempotency_deleted_count,
    oldest_deleted_request_created_at,
    oldest_deleted_claim_expires_at,
    started_at,
    completed_at,
    details
  from public.platform_gateway_maintenance_run
  order by started_at desc
  limit 1
),
request_backlog as (
  select
    count(*)::integer as request_log_past_retention_count,
    min(created_at) as oldest_request_log_created_at
  from public.platform_gateway_request_log
  where created_at < timezone('utc', now()) - interval '7 days'
),
idempotency_backlog as (
  select
    count(*)::integer as idempotency_claim_past_grace_count,
    min(expires_at) as oldest_expired_claim_expires_at
  from public.platform_gateway_idempotency_claim
  where expires_at < timezone('utc', now()) - interval '24 hours'
)
select
  timezone('utc', now()) as captured_at,
  lm.run_id,
  lm.maintenance_code,
  lm.run_status,
  lm.request_log_retention_days,
  lm.idempotency_grace_hours,
  lm.request_log_deleted_count,
  lm.idempotency_deleted_count,
  lm.oldest_deleted_request_created_at,
  lm.oldest_deleted_claim_expires_at,
  lm.started_at,
  lm.completed_at,
  lm.details,
  rb.request_log_past_retention_count,
  rb.oldest_request_log_created_at,
  ib.idempotency_claim_past_grace_count,
  ib.oldest_expired_claim_expires_at
from (select 1 as marker) seed
left join latest_maintenance lm on true
left join request_backlog rb on true
left join idempotency_backlog ib on true;

insert into public.platform_read_model_catalog (
  read_model_code,
  module_code,
  read_model_name,
  schema_placement,
  storage_kind,
  ownership_scope,
  object_name,
  refresh_strategy,
  refresh_mode,
  refresh_owner_code,
  refresh_function_name,
  freshness_sla_seconds,
  notes,
  metadata
)
values
  ('gateway_runtime_overview', 'I03', 'Gateway Runtime Overview', 'public', 'view', 'platform_shared', 'platform_rm_gateway_runtime_overview', 'none', 'none', 'I03', null, null, 'I03 gateway runtime observability baseline.', jsonb_build_object('phase', 'I03_HARDENING_FOUNDATION')),
  ('gateway_error_breakdown', 'I03', 'Gateway Error Breakdown', 'public', 'view', 'platform_shared', 'platform_rm_gateway_error_breakdown', 'none', 'none', 'I03', null, null, 'I03 gateway runtime observability baseline.', jsonb_build_object('phase', 'I03_HARDENING_FOUNDATION')),
  ('gateway_maintenance_status', 'I03', 'Gateway Maintenance Status', 'public', 'view', 'platform_shared', 'platform_rm_gateway_maintenance_status', 'none', 'none', 'I03', null, null, 'I03 gateway maintenance baseline.', jsonb_build_object('phase', 'I03_HARDENING_FOUNDATION'))
on conflict (read_model_code) do update
set module_code = excluded.module_code,
    read_model_name = excluded.read_model_name,
    schema_placement = excluded.schema_placement,
    storage_kind = excluded.storage_kind,
    ownership_scope = excluded.ownership_scope,
    object_name = excluded.object_name,
    refresh_strategy = excluded.refresh_strategy,
    refresh_mode = excluded.refresh_mode,
    refresh_owner_code = excluded.refresh_owner_code,
    refresh_function_name = excluded.refresh_function_name,
    freshness_sla_seconds = excluded.freshness_sla_seconds,
    notes = excluded.notes,
    metadata = excluded.metadata,
    updated_at = timezone('utc', now());

revoke all on public.platform_gateway_maintenance_run from public, anon, authenticated;
revoke all on public.platform_rm_gateway_runtime_overview from public, anon, authenticated;
revoke all on public.platform_rm_gateway_error_breakdown from public, anon, authenticated;
revoke all on public.platform_rm_gateway_maintenance_status from public, anon, authenticated;

revoke all on function public.platform_cleanup_gateway_request_log(jsonb) from public, anon, authenticated;
revoke all on function public.platform_cleanup_gateway_idempotency_claim(jsonb) from public, anon, authenticated;
revoke all on function public.platform_i03_run_gateway_maintenance_scheduler() from public, anon, authenticated;

grant all on public.platform_gateway_maintenance_run to service_role;
grant select on public.platform_rm_gateway_runtime_overview to service_role;
grant select on public.platform_rm_gateway_error_breakdown to service_role;
grant select on public.platform_rm_gateway_maintenance_status to service_role;

grant execute on function public.platform_cleanup_gateway_request_log(jsonb) to service_role;
grant execute on function public.platform_cleanup_gateway_idempotency_claim(jsonb) to service_role;
grant execute on function public.platform_i03_run_gateway_maintenance_scheduler() to service_role;

do $do$
declare
  v_command text := 'select public.platform_i03_run_gateway_maintenance_scheduler();';
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'i03-gateway-maintenance'
  ) then
    update cron.job
    set schedule = '0 * * * *',
        command = v_command,
        database = current_database(),
        username = current_user,
        active = true
    where jobname = 'i03-gateway-maintenance';
  else
    perform cron.schedule('i03-gateway-maintenance', '0 * * * *', v_command);
  end if;
end;
$do$;

do $do$
declare
  v_result jsonb;
begin
  v_result := public.platform_i03_run_gateway_maintenance_scheduler();

  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'I03 gateway maintenance bootstrap run failed: %', v_result::text;
  end if;
end;
$do$;

