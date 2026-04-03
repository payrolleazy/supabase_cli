create table if not exists public.platform_extensible_maintenance_run (
  run_id uuid primary key default gen_random_uuid(),
  maintenance_code text not null,
  run_status text not null default 'running'
    check (run_status in ('running', 'succeeded', 'failed')),
  cache_grace_seconds integer not null default 0
    check (cache_grace_seconds >= 0),
  cache_deleted_count integer not null default 0
    check (cache_deleted_count >= 0),
  distinct_entity_count integer not null default 0
    check (distinct_entity_count >= 0),
  oldest_deleted_expires_at timestamptz null,
  newest_deleted_expires_at timestamptz null,
  details jsonb not null default '{}'::jsonb
    check (jsonb_typeof(details) = 'object'),
  started_at timestamptz not null default timezone('utc', now()),
  completed_at timestamptz null
);

create index if not exists idx_platform_extensible_maintenance_run_started_at
  on public.platform_extensible_maintenance_run (started_at desc);

alter table public.platform_extensible_maintenance_run enable row level security;

drop policy if exists platform_extensible_maintenance_run_service_role_all
  on public.platform_extensible_maintenance_run;
create policy platform_extensible_maintenance_run_service_role_all
on public.platform_extensible_maintenance_run
for all
using (auth.role() = 'service_role')
with check (auth.role() = 'service_role');

create or replace function public.platform_cleanup_extensible_schema_cache(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_grace_seconds integer := 0;
  v_cutoff timestamptz;
  v_deleted_count integer := 0;
  v_distinct_entity_count integer := 0;
  v_oldest_deleted timestamptz;
  v_newest_deleted timestamptz;
begin
  if p_params is not null and jsonb_typeof(p_params) <> 'object' then
    return public.platform_json_response(false, 'INVALID_PARAMS', 'p_params must be a JSON object.', '{}'::jsonb);
  end if;

  if nullif(coalesce(p_params, '{}'::jsonb)->>'grace_seconds', '') is not null then
    begin
      v_grace_seconds := greatest(((coalesce(p_params, '{}'::jsonb)->>'grace_seconds')::integer), 0);
    exception
      when others then
        return public.platform_json_response(false, 'INVALID_GRACE_SECONDS', 'grace_seconds must be a non-negative integer.', '{}'::jsonb);
    end;
  end if;

  v_cutoff := timezone('utc', now()) - make_interval(secs => v_grace_seconds);

  with deleted_rows as (
    delete from public.platform_extensible_schema_cache
    where expires_at <= v_cutoff
    returning entity_id, expires_at
  )
  select count(*)::integer,
         count(distinct entity_id)::integer,
         min(expires_at),
         max(expires_at)
  into v_deleted_count,
       v_distinct_entity_count,
       v_oldest_deleted,
       v_newest_deleted
  from deleted_rows;

  return public.platform_json_response(
    true,
    'OK',
    'Extensible schema cache cleanup completed.',
    jsonb_build_object(
      'grace_seconds', v_grace_seconds,
      'cutoff', v_cutoff,
      'deleted_count', coalesce(v_deleted_count, 0),
      'distinct_entity_count', coalesce(v_distinct_entity_count, 0),
      'oldest_deleted_expires_at', v_oldest_deleted,
      'newest_deleted_expires_at', v_newest_deleted
    )
  );
end;
$function$;

create or replace function public.platform_i04_run_extensible_maintenance_scheduler()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_run_id uuid;
  v_cleanup jsonb;
  v_deleted_count integer := 0;
  v_distinct_entity_count integer := 0;
  v_oldest_deleted timestamptz;
  v_newest_deleted timestamptz;
begin
  insert into public.platform_extensible_maintenance_run (
    maintenance_code,
    run_status,
    cache_grace_seconds,
    details
  )
  values (
    'i04_extensible_cache_maintenance',
    'running',
    0,
    jsonb_build_object('trigger', 'pg_cron')
  )
  returning run_id
  into v_run_id;

  v_cleanup := public.platform_cleanup_extensible_schema_cache(
    jsonb_build_object('grace_seconds', 0)
  );

  if coalesce((v_cleanup->>'success')::boolean, false) is not true then
    update public.platform_extensible_maintenance_run
    set run_status = 'failed',
        completed_at = timezone('utc', now()),
        details = coalesce(details, '{}'::jsonb) || jsonb_build_object('cleanup', v_cleanup)
    where run_id = v_run_id;

    return v_cleanup;
  end if;

  v_deleted_count := coalesce((v_cleanup->'details'->>'deleted_count')::integer, 0);
  v_distinct_entity_count := coalesce((v_cleanup->'details'->>'distinct_entity_count')::integer, 0);
  v_oldest_deleted := nullif(v_cleanup->'details'->>'oldest_deleted_expires_at', '')::timestamptz;
  v_newest_deleted := nullif(v_cleanup->'details'->>'newest_deleted_expires_at', '')::timestamptz;

  update public.platform_extensible_maintenance_run
  set run_status = 'succeeded',
      cache_deleted_count = v_deleted_count,
      distinct_entity_count = v_distinct_entity_count,
      oldest_deleted_expires_at = v_oldest_deleted,
      newest_deleted_expires_at = v_newest_deleted,
      details = coalesce(details, '{}'::jsonb) || jsonb_build_object('cleanup', v_cleanup),
      completed_at = timezone('utc', now())
  where run_id = v_run_id;

  return public.platform_json_response(
    true,
    'OK',
    'I04 extensible maintenance completed.',
    jsonb_build_object(
      'run_id', v_run_id,
      'cache_deleted_count', v_deleted_count,
      'distinct_entity_count', v_distinct_entity_count,
      'cleanup', v_cleanup
    )
  );
exception
  when others then
    if v_run_id is not null then
      update public.platform_extensible_maintenance_run
      set run_status = 'failed',
          completed_at = timezone('utc', now()),
          details = coalesce(details, '{}'::jsonb)
            || jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
      where run_id = v_run_id;
    end if;

    return public.platform_json_response(
      false,
      'UNEXPECTED_ERROR',
      'Unexpected error in platform_i04_run_extensible_maintenance_scheduler.',
      jsonb_build_object('run_id', v_run_id, 'sqlstate', sqlstate, 'sqlerrm', sqlerrm)
    );
end;
$function$;

create or replace view public.platform_rm_extensible_runtime_overview
with (security_invoker = true)
as
with entity_stats as (
  select
    count(*)::integer as entity_registry_count,
    count(*) filter (where entity_status = 'active')::integer as active_entity_count,
    count(*) filter (where join_profile_enabled)::integer as join_profile_enabled_entity_count,
    count(*) filter (where allow_tenant_override)::integer as tenant_override_entity_count
  from public.platform_extensible_entity_registry
), attribute_stats as (
  select
    count(*)::integer as attribute_schema_count,
    count(*) filter (where attribute_status = 'active')::integer as active_attribute_schema_count,
    count(*) filter (where tenant_id is null)::integer as shared_attribute_schema_count,
    count(*) filter (where tenant_id is not null)::integer as tenant_override_attribute_schema_count
  from public.platform_extensible_attribute_schema
), join_stats as (
  select
    count(*)::integer as join_profile_count,
    count(*) filter (where profile_status = 'active')::integer as active_join_profile_count,
    count(*) filter (where tenant_id is null)::integer as shared_join_profile_count,
    count(*) filter (where tenant_id is not null)::integer as tenant_override_join_profile_count
  from public.platform_extensible_join_profile
), cache_stats as (
  select
    count(*)::integer as cache_total_count,
    count(*) filter (where expires_at <= timezone('utc', now()))::integer as cache_expired_count,
    min(expires_at) filter (where expires_at <= timezone('utc', now())) as oldest_expired_cache_at,
    max(expires_at) as newest_cache_expiry_at
  from public.platform_extensible_schema_cache
), latest_maintenance as (
  select
    run_id,
    run_status,
    started_at,
    completed_at,
    cache_deleted_count,
    distinct_entity_count
  from public.platform_extensible_maintenance_run
  order by started_at desc
  limit 1
)
select
  timezone('utc', now()) as captured_at,
  es.entity_registry_count,
  es.active_entity_count,
  es.join_profile_enabled_entity_count,
  es.tenant_override_entity_count,
  ats.attribute_schema_count,
  ats.active_attribute_schema_count,
  ats.shared_attribute_schema_count,
  ats.tenant_override_attribute_schema_count,
  js.join_profile_count,
  js.active_join_profile_count,
  js.shared_join_profile_count,
  js.tenant_override_join_profile_count,
  cs.cache_total_count,
  cs.cache_expired_count,
  cs.oldest_expired_cache_at,
  cs.newest_cache_expiry_at,
  lm.run_id as latest_maintenance_run_id,
  lm.run_status as latest_maintenance_status,
  lm.started_at as latest_maintenance_started_at,
  lm.completed_at as latest_maintenance_completed_at,
  lm.cache_deleted_count as latest_cache_deleted_count,
  lm.distinct_entity_count as latest_distinct_entity_count
from entity_stats es
cross join attribute_stats ats
cross join join_stats js
cross join cache_stats cs
left join latest_maintenance lm on true;

create or replace view public.platform_rm_extensible_maintenance_status
with (security_invoker = true)
as
with latest_maintenance as (
  select
    run_id,
    maintenance_code,
    run_status,
    cache_grace_seconds,
    cache_deleted_count,
    distinct_entity_count,
    oldest_deleted_expires_at,
    newest_deleted_expires_at,
    started_at,
    completed_at,
    details
  from public.platform_extensible_maintenance_run
  order by started_at desc
  limit 1
), cache_backlog as (
  select
    count(*)::integer as expired_cache_count,
    min(expires_at) as oldest_expired_cache_at,
    max(expires_at) as newest_expired_cache_at
  from public.platform_extensible_schema_cache
  where expires_at <= timezone('utc', now())
)
select
  timezone('utc', now()) as captured_at,
  lm.run_id,
  lm.maintenance_code,
  lm.run_status,
  lm.cache_grace_seconds,
  lm.cache_deleted_count,
  lm.distinct_entity_count,
  lm.oldest_deleted_expires_at,
  lm.newest_deleted_expires_at,
  lm.started_at,
  lm.completed_at,
  lm.details,
  cb.expired_cache_count,
  cb.oldest_expired_cache_at,
  cb.newest_expired_cache_at
from (select 1 as marker) seed
left join latest_maintenance lm on true
left join cache_backlog cb on true;

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
  ('extensible_runtime_overview', 'I04', 'Extensible Runtime Overview', 'public', 'view', 'platform_shared', 'platform_rm_extensible_runtime_overview', 'none', 'none', 'I04', null, null, 'I04 runtime observability baseline.', jsonb_build_object('phase', 'I04_RUNTIME_HARDENING')),
  ('extensible_maintenance_status', 'I04', 'Extensible Maintenance Status', 'public', 'view', 'platform_shared', 'platform_rm_extensible_maintenance_status', 'none', 'none', 'I04', null, null, 'I04 maintenance observability baseline.', jsonb_build_object('phase', 'I04_RUNTIME_HARDENING'))
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

revoke all on public.platform_extensible_maintenance_run from public, anon, authenticated;
revoke all on public.platform_rm_extensible_runtime_overview from public, anon, authenticated;
revoke all on public.platform_rm_extensible_maintenance_status from public, anon, authenticated;

revoke all on function public.platform_cleanup_extensible_schema_cache(jsonb) from public, anon, authenticated;
revoke all on function public.platform_i04_run_extensible_maintenance_scheduler() from public, anon, authenticated;

grant all on public.platform_extensible_maintenance_run to service_role;
grant select on public.platform_rm_extensible_runtime_overview to service_role;
grant select on public.platform_rm_extensible_maintenance_status to service_role;

grant execute on function public.platform_cleanup_extensible_schema_cache(jsonb) to service_role;
grant execute on function public.platform_i04_run_extensible_maintenance_scheduler() to service_role;

do $do$
declare
  v_command text := 'select public.platform_i04_run_extensible_maintenance_scheduler();';
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'i04-extensible-cache-maintenance'
  ) then
    update cron.job
    set schedule = '*/15 * * * *',
        command = v_command,
        database = current_database(),
        username = current_user,
        active = true
    where jobname = 'i04-extensible-cache-maintenance';
  else
    perform cron.schedule('i04-extensible-cache-maintenance', '*/15 * * * *', v_command);
  end if;
end;
$do$;

do $do$
declare
  v_result jsonb;
begin
  v_result := public.platform_i04_run_extensible_maintenance_scheduler();

  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'I04 extensible maintenance bootstrap run failed: %', v_result::text;
  end if;
end;
$do$;
