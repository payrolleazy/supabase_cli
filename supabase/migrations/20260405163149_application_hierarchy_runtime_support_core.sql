create table if not exists public.platform_hierarchy_metadata (
  tenant_id uuid primary key references public.platform_tenant(tenant_id) on delete cascade,
  last_cache_refresh_at timestamptz null,
  last_health_check_at timestamptz null,
  last_self_test_at timestamptz null,
  last_maintenance_at timestamptz null,
  last_backup_at timestamptz null,
  last_health_status text null check (last_health_status in ('healthy', 'warning', 'critical')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.platform_hierarchy_health_status (
  tenant_id uuid primary key references public.platform_tenant(tenant_id) on delete cascade,
  health_status text not null default 'healthy' check (health_status in ('healthy', 'warning', 'critical')),
  issue_count integer not null default 0 check (issue_count >= 0),
  checked_at timestamptz not null default timezone('utc', now()),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.platform_hierarchy_error_log (
  error_log_id bigserial primary key,
  tenant_id uuid null references public.platform_tenant(tenant_id) on delete set null,
  operation_code text not null,
  error_code text not null,
  error_message text not null,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  occurred_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.platform_hierarchy_performance_log (
  performance_log_id bigserial primary key,
  tenant_id uuid null references public.platform_tenant(tenant_id) on delete set null,
  operation_code text not null,
  status text not null check (status in ('succeeded', 'warning', 'failed')),
  duration_ms integer null check (duration_ms is null or duration_ms >= 0),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.platform_hierarchy_backup_log (
  backup_log_id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  backup_kind text not null default 'org_chart_snapshot' check (backup_kind in ('org_chart_snapshot')),
  position_count integer not null default 0 check (position_count >= 0),
  occupancy_count integer not null default 0 check (occupancy_count >= 0),
  snapshot_payload jsonb not null default '[]'::jsonb check (jsonb_typeof(snapshot_payload) = 'array'),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  requested_by text null,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.platform_hierarchy_maintenance_lock (
  lock_key text primary key,
  tenant_id uuid null references public.platform_tenant(tenant_id) on delete cascade,
  locked_at timestamptz not null default timezone('utc', now()),
  lock_expires_at timestamptz not null,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object')
);

create table if not exists public.platform_hierarchy_maintenance_run (
  run_id uuid primary key default gen_random_uuid(),
  maintenance_code text not null check (maintenance_code in ('hierarchy_maintenance')),
  trigger_source text not null default 'manual',
  run_status text not null default 'running' check (run_status in ('running', 'succeeded', 'failed')),
  refresh_run_id uuid null references public.platform_read_model_refresh_run(id) on delete set null,
  tenant_checked_count integer not null default 0 check (tenant_checked_count >= 0),
  healthy_tenant_count integer not null default 0 check (healthy_tenant_count >= 0),
  warning_tenant_count integer not null default 0 check (warning_tenant_count >= 0),
  critical_tenant_count integer not null default 0 check (critical_tenant_count >= 0),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  completed_at timestamptz null
);

create index if not exists idx_platform_hierarchy_error_log_tenant_occurred on public.platform_hierarchy_error_log (tenant_id, occurred_at desc);
create index if not exists idx_platform_hierarchy_performance_log_tenant_created on public.platform_hierarchy_performance_log (tenant_id, created_at desc);
create index if not exists idx_platform_hierarchy_backup_log_tenant_created on public.platform_hierarchy_backup_log (tenant_id, created_at desc);
create index if not exists idx_platform_hierarchy_maintenance_lock_expires on public.platform_hierarchy_maintenance_lock (lock_expires_at);
create index if not exists idx_platform_hierarchy_maintenance_run_status_created on public.platform_hierarchy_maintenance_run (run_status, created_at desc);

alter table public.platform_hierarchy_metadata enable row level security;
alter table public.platform_hierarchy_health_status enable row level security;
alter table public.platform_hierarchy_error_log enable row level security;
alter table public.platform_hierarchy_performance_log enable row level security;
alter table public.platform_hierarchy_backup_log enable row level security;
alter table public.platform_hierarchy_maintenance_lock enable row level security;
alter table public.platform_hierarchy_maintenance_run enable row level security;

drop policy if exists platform_hierarchy_metadata_service_role_all on public.platform_hierarchy_metadata;
create policy platform_hierarchy_metadata_service_role_all on public.platform_hierarchy_metadata for all to service_role using (true) with check (true);
drop policy if exists platform_hierarchy_health_status_service_role_all on public.platform_hierarchy_health_status;
create policy platform_hierarchy_health_status_service_role_all on public.platform_hierarchy_health_status for all to service_role using (true) with check (true);
drop policy if exists platform_hierarchy_error_log_service_role_all on public.platform_hierarchy_error_log;
create policy platform_hierarchy_error_log_service_role_all on public.platform_hierarchy_error_log for all to service_role using (true) with check (true);
drop policy if exists platform_hierarchy_performance_log_service_role_all on public.platform_hierarchy_performance_log;
create policy platform_hierarchy_performance_log_service_role_all on public.platform_hierarchy_performance_log for all to service_role using (true) with check (true);
drop policy if exists platform_hierarchy_backup_log_service_role_all on public.platform_hierarchy_backup_log;
create policy platform_hierarchy_backup_log_service_role_all on public.platform_hierarchy_backup_log for all to service_role using (true) with check (true);
drop policy if exists platform_hierarchy_maintenance_lock_service_role_all on public.platform_hierarchy_maintenance_lock;
create policy platform_hierarchy_maintenance_lock_service_role_all on public.platform_hierarchy_maintenance_lock for all to service_role using (true) with check (true);
drop policy if exists platform_hierarchy_maintenance_run_service_role_all on public.platform_hierarchy_maintenance_run;
create policy platform_hierarchy_maintenance_run_service_role_all on public.platform_hierarchy_maintenance_run for all to service_role using (true) with check (true);

drop trigger if exists trg_platform_hierarchy_metadata_set_updated_at on public.platform_hierarchy_metadata;
create trigger trg_platform_hierarchy_metadata_set_updated_at before update on public.platform_hierarchy_metadata for each row execute function public.platform_set_updated_at();
drop trigger if exists trg_platform_hierarchy_health_status_set_updated_at on public.platform_hierarchy_health_status;
create trigger trg_platform_hierarchy_health_status_set_updated_at before update on public.platform_hierarchy_health_status for each row execute function public.platform_set_updated_at();
drop trigger if exists trg_platform_hierarchy_maintenance_run_set_updated_at on public.platform_hierarchy_maintenance_run;
create trigger trg_platform_hierarchy_maintenance_run_set_updated_at before update on public.platform_hierarchy_maintenance_run for each row execute function public.platform_set_updated_at();

create or replace function public.platform_hierarchy_org_chart_rows_for_schema(p_tenant_id uuid, p_schema_name text)
returns table(
  tenant_id uuid,
  position_id bigint,
  position_code text,
  position_name text,
  position_group_id bigint,
  position_group_code text,
  position_group_name text,
  reporting_position_id bigint,
  hierarchy_path text,
  hierarchy_level integer,
  position_status text,
  active_occupancy_count integer,
  direct_report_count integer,
  operational_employee_id uuid,
  operational_employee_code text,
  operational_actor_user_id uuid,
  operational_employee_name text,
  operational_occupancy_role text,
  overlap_count integer
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if p_tenant_id is null or p_schema_name is null then
    return;
  end if;

  if not public.platform_table_exists(p_schema_name, 'hierarchy_position')
    or not public.platform_table_exists(p_schema_name, 'hierarchy_position_group')
    or not public.platform_table_exists(p_schema_name, 'hierarchy_position_occupancy')
    or not public.platform_table_exists(p_schema_name, 'wcm_employee')
    or not public.platform_table_exists(p_schema_name, 'wcm_employee_service_state')
  then
    return;
  end if;

  return query execute format(
    $sql$
      with active_occupancy as (
        select o.position_id, count(*)::integer as active_occupancy_count
        from %1$I.hierarchy_position_occupancy o
        where o.occupancy_status = 'active'
          and o.effective_start_date <= current_date
          and coalesce(o.effective_end_date, date '9999-12-31') >= current_date
        group by o.position_id
      ), direct_reports as (
        select p.reporting_position_id, count(*)::integer as direct_report_count
        from %1$I.hierarchy_position p
        where p.reporting_position_id is not null
        group by p.reporting_position_id
      ), ranked_occupancy as (
        select
          o.position_id,
          e.employee_id,
          e.employee_code,
          e.actor_user_id,
          concat_ws(' ', e.first_name, nullif(e.middle_name, ''), e.last_name) as employee_name,
          o.occupancy_role,
          greatest(count(*) over (partition by o.position_id)::integer - 1, 0) as overlap_count,
          row_number() over (
            partition by o.position_id
            order by
              public.platform_hierarchy_occupancy_role_priority(o.occupancy_role),
              public.platform_hierarchy_service_state_priority(s.service_state),
              o.effective_start_date desc,
              o.occupancy_id desc
          ) as operational_rank
        from %1$I.hierarchy_position_occupancy o
        join %1$I.wcm_employee e on e.employee_id = o.employee_id
        join %1$I.wcm_employee_service_state s on s.employee_id = o.employee_id
        where o.occupancy_status = 'active'
          and o.effective_start_date <= current_date
          and coalesce(o.effective_end_date, date '9999-12-31') >= current_date
      )
      select
        $1::uuid as tenant_id,
        p.position_id,
        p.position_code,
        p.position_name,
        p.position_group_id,
        g.position_group_code,
        g.position_group_name,
        p.reporting_position_id,
        ltree2text(p.hierarchy_path) as hierarchy_path,
        nlevel(p.hierarchy_path)::integer as hierarchy_level,
        p.position_status,
        coalesce(ao.active_occupancy_count, 0)::integer as active_occupancy_count,
        coalesce(dr.direct_report_count, 0)::integer as direct_report_count,
        ro.employee_id as operational_employee_id,
        ro.employee_code as operational_employee_code,
        ro.actor_user_id as operational_actor_user_id,
        ro.employee_name as operational_employee_name,
        ro.occupancy_role as operational_occupancy_role,
        coalesce(ro.overlap_count, 0)::integer as overlap_count
      from %1$I.hierarchy_position p
      left join %1$I.hierarchy_position_group g on g.position_group_id = p.position_group_id
      left join active_occupancy ao on ao.position_id = p.position_id
      left join direct_reports dr on dr.reporting_position_id = p.position_id
      left join ranked_occupancy ro on ro.position_id = p.position_id and ro.operational_rank = 1
      order by p.hierarchy_path nulls last, p.position_code
    $sql$,
    p_schema_name
  ) using p_tenant_id;
end;
$function$;

create or replace function public.platform_hierarchy_org_chart_cache_seed_rows()
returns table(
  tenant_id uuid,
  position_id bigint,
  position_code text,
  position_name text,
  position_group_id bigint,
  position_group_code text,
  position_group_name text,
  reporting_position_id bigint,
  hierarchy_path text,
  hierarchy_level integer,
  position_status text,
  active_occupancy_count integer,
  direct_report_count integer,
  operational_employee_id uuid,
  operational_employee_code text,
  operational_actor_user_id uuid,
  operational_employee_name text,
  operational_occupancy_role text,
  overlap_count integer
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant record;
begin
  for v_tenant in
    select tenant_id, schema_name
    from public.platform_tenant_registry_view
    where schema_provisioned is true
      and schema_name like 'tenant_%'
    order by schema_name
  loop
    return query
    select *
    from public.platform_hierarchy_org_chart_rows_for_schema(v_tenant.tenant_id, v_tenant.schema_name);
  end loop;
end;
$function$;

create materialized view if not exists public.platform_rm_hierarchy_org_chart_cached_store
as
select *
from public.platform_hierarchy_org_chart_cache_seed_rows()
with no data;

create unique index if not exists idx_platform_rm_hierarchy_org_chart_cached_store_tenant_position on public.platform_rm_hierarchy_org_chart_cached_store (tenant_id, position_id);
create index if not exists idx_platform_rm_hierarchy_org_chart_cached_store_tenant_status on public.platform_rm_hierarchy_org_chart_cached_store (tenant_id, position_status, position_code);

create or replace view public.platform_rm_hierarchy_org_chart_cached
with (security_invoker = true)
as
select *
from public.platform_rm_hierarchy_org_chart_cached_store
where tenant_id = public.platform_current_tenant_id();

create or replace function public.platform_hierarchy_position_history_rows()
returns table(
  tenant_id uuid,
  occupancy_history_id bigint,
  occupancy_id bigint,
  position_id bigint,
  position_code text,
  position_name text,
  employee_id uuid,
  employee_code text,
  employee_name text,
  actor_user_id uuid,
  occupancy_role text,
  event_type text,
  effective_start_date date,
  effective_end_date date,
  event_reason text,
  event_details jsonb,
  created_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_current_tenant_id();
  v_schema_name text := public.platform_current_tenant_schema();
begin
  if v_tenant_id is null or v_schema_name is null then
    return;
  end if;

  if not public.platform_table_exists(v_schema_name, 'hierarchy_position_occupancy_history')
    or not public.platform_table_exists(v_schema_name, 'hierarchy_position')
    or not public.platform_table_exists(v_schema_name, 'wcm_employee')
  then
    return;
  end if;

  return query execute format(
    $sql$
      select
        $1::uuid as tenant_id,
        h.occupancy_history_id,
        h.occupancy_id,
        h.position_id,
        p.position_code,
        p.position_name,
        h.employee_id,
        e.employee_code,
        concat_ws(' ', e.first_name, nullif(e.middle_name, ''), e.last_name) as employee_name,
        h.actor_user_id,
        h.occupancy_role,
        h.event_type,
        h.effective_start_date,
        h.effective_end_date,
        h.event_reason,
        h.event_details,
        h.created_at
      from %1$I.hierarchy_position_occupancy_history h
      left join %1$I.hierarchy_position p on p.position_id = h.position_id
      left join %1$I.wcm_employee e on e.employee_id = h.employee_id
      order by h.created_at desc, h.occupancy_history_id desc
    $sql$,
    v_schema_name
  ) using v_tenant_id;
end;
$function$;

create or replace function public.platform_hierarchy_metrics_summary_rows()
returns table(
  tenant_id uuid,
  total_position_count integer,
  active_position_count integer,
  occupied_position_count integer,
  vacant_position_count integer,
  overlap_position_count integer,
  root_position_count integer,
  max_hierarchy_level integer,
  last_cache_refresh_at timestamptz,
  last_health_status text,
  last_health_check_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_current_tenant_id();
  v_schema_name text := public.platform_current_tenant_schema();
begin
  if v_tenant_id is null then
    return;
  end if;

  if exists (
    select 1 from public.platform_rm_hierarchy_org_chart_cached_store c where c.tenant_id = v_tenant_id limit 1
  ) then
    return query
    select
      v_tenant_id as tenant_id,
      count(*)::integer as total_position_count,
      count(*) filter (where c.position_status = 'active')::integer as active_position_count,
      count(*) filter (where c.operational_employee_id is not null)::integer as occupied_position_count,
      count(*) filter (where c.operational_employee_id is null)::integer as vacant_position_count,
      count(*) filter (where c.overlap_count > 0)::integer as overlap_position_count,
      count(*) filter (where c.reporting_position_id is null)::integer as root_position_count,
      coalesce(max(c.hierarchy_level), 0)::integer as max_hierarchy_level,
      max(m.last_cache_refresh_at) as last_cache_refresh_at,
      max(m.last_health_status) as last_health_status,
      max(m.last_health_check_at) as last_health_check_at
    from public.platform_rm_hierarchy_org_chart_cached_store c
    left join public.platform_hierarchy_metadata m on m.tenant_id = v_tenant_id
    where c.tenant_id = v_tenant_id;
  else
    if v_schema_name is null then
      return;
    end if;

    return query
    select
      v_tenant_id as tenant_id,
      count(*)::integer as total_position_count,
      count(*) filter (where c.position_status = 'active')::integer as active_position_count,
      count(*) filter (where c.operational_employee_id is not null)::integer as occupied_position_count,
      count(*) filter (where c.operational_employee_id is null)::integer as vacant_position_count,
      count(*) filter (where c.overlap_count > 0)::integer as overlap_position_count,
      count(*) filter (where c.reporting_position_id is null)::integer as root_position_count,
      coalesce(max(c.hierarchy_level), 0)::integer as max_hierarchy_level,
      max(m.last_cache_refresh_at) as last_cache_refresh_at,
      max(m.last_health_status) as last_health_status,
      max(m.last_health_check_at) as last_health_check_at
    from public.platform_hierarchy_org_chart_rows_for_schema(v_tenant_id, v_schema_name) c
    left join public.platform_hierarchy_metadata m on m.tenant_id = v_tenant_id;
  end if;
end;
$function$;

create or replace function public.platform_hierarchy_health_status_rows()
returns table(
  tenant_id uuid,
  health_status text,
  issue_count integer,
  checked_at timestamptz,
  last_cache_refresh_at timestamptz,
  last_maintenance_at timestamptz,
  last_self_test_at timestamptz,
  details jsonb
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_current_tenant_id();
begin
  if v_tenant_id is null then
    return;
  end if;

  return query
  select
    v_tenant_id as tenant_id,
    coalesce(h.health_status, 'never_checked') as health_status,
    coalesce(h.issue_count, 0)::integer as issue_count,
    h.checked_at,
    m.last_cache_refresh_at,
    m.last_maintenance_at,
    m.last_self_test_at,
    coalesce(h.details, '{}'::jsonb) as details
  from (select 1) seed
  left join public.platform_hierarchy_health_status h on h.tenant_id = v_tenant_id
  left join public.platform_hierarchy_metadata m on m.tenant_id = v_tenant_id;
end;
$function$;

create or replace view public.platform_rm_hierarchy_position_history with (security_invoker = true) as select * from public.platform_hierarchy_position_history_rows();
create or replace view public.platform_rm_hierarchy_metrics_summary with (security_invoker = true) as select * from public.platform_hierarchy_metrics_summary_rows();
create or replace view public.platform_rm_hierarchy_health_status with (security_invoker = true) as select * from public.platform_hierarchy_health_status_rows();

create or replace function public.platform_hierarchy_run_diagnostics_internal(p_tenant_id uuid, p_schema_name text, p_trigger text default 'health_check')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_started_at timestamptz := timezone('utc', now());
  v_missing_tables text[] := '{}'::text[];
  v_position_count integer := 0;
  v_active_position_count integer := 0;
  v_active_occupancy_count integer := 0;
  v_overlap_position_count integer := 0;
  v_orphan_reporting_count integer := 0;
  v_missing_path_count integer := 0;
  v_inactive_position_with_active_occupancy_count integer := 0;
  v_issue_count integer := 0;
  v_health_status text := 'healthy';
  v_details jsonb := '{}'::jsonb;
  v_duration_ms integer;
begin
  if p_tenant_id is null or p_schema_name is null then
    return public.platform_json_response(false, 'TENANT_CONTEXT_REQUIRED', 'tenant_id and tenant_schema are required.', '{}'::jsonb);
  end if;

  if not public.platform_table_exists(p_schema_name, 'hierarchy_position') then
    v_missing_tables := array_append(v_missing_tables, 'hierarchy_position');
  end if;
  if not public.platform_table_exists(p_schema_name, 'hierarchy_position_occupancy') then
    v_missing_tables := array_append(v_missing_tables, 'hierarchy_position_occupancy');
  end if;
  if not public.platform_table_exists(p_schema_name, 'wcm_employee') then
    v_missing_tables := array_append(v_missing_tables, 'wcm_employee');
  end if;

  if coalesce(array_length(v_missing_tables, 1), 0) > 0 then
    v_issue_count := array_length(v_missing_tables, 1);
    v_health_status := 'critical';
    v_details := jsonb_build_object('tenant_id', p_tenant_id, 'tenant_schema', p_schema_name, 'health_status', v_health_status, 'issue_count', v_issue_count, 'missing_tables', to_jsonb(v_missing_tables), 'trigger', p_trigger);
  else
    execute format(
      $sql$
        with position_metrics as (
          select
            count(*)::integer as position_count,
            count(*) filter (where p.position_status = 'active')::integer as active_position_count,
            count(*) filter (
              where p.reporting_position_id is not null
                and not exists (
                  select 1 from %1$I.hierarchy_position parent where parent.position_id = p.reporting_position_id
                )
            )::integer as orphan_reporting_count,
            count(*) filter (
              where p.position_status = 'active' and p.hierarchy_path is null
            )::integer as missing_path_count
          from %1$I.hierarchy_position p
        ), occupancy_metrics as (
          select
            count(*) filter (
              where o.occupancy_status = 'active'
                and o.effective_start_date <= current_date
                and coalesce(o.effective_end_date, date '9999-12-31') >= current_date
            )::integer as active_occupancy_count,
            count(*) filter (
              where o.occupancy_status = 'active'
                and o.effective_start_date <= current_date
                and coalesce(o.effective_end_date, date '9999-12-31') >= current_date
                and coalesce(p.position_status, '') <> 'active'
            )::integer as inactive_position_with_active_occupancy_count
          from %1$I.hierarchy_position_occupancy o
          left join %1$I.hierarchy_position p on p.position_id = o.position_id
        ), overlap_metrics as (
          select count(*)::integer as overlap_position_count
          from (
            select o.position_id
            from %1$I.hierarchy_position_occupancy o
            where o.occupancy_status = 'active'
              and o.effective_start_date <= current_date
              and coalesce(o.effective_end_date, date '9999-12-31') >= current_date
            group by o.position_id
            having count(*) > 1
          ) overlap_rows
        )
        select pm.position_count, pm.active_position_count, om.active_occupancy_count, xm.overlap_position_count, pm.orphan_reporting_count, pm.missing_path_count, om.inactive_position_with_active_occupancy_count
        from position_metrics pm
        cross join occupancy_metrics om
        cross join overlap_metrics xm
      $sql$,
      p_schema_name
    ) into v_position_count, v_active_position_count, v_active_occupancy_count, v_overlap_position_count, v_orphan_reporting_count, v_missing_path_count, v_inactive_position_with_active_occupancy_count;

    v_issue_count := coalesce(v_orphan_reporting_count, 0) + coalesce(v_missing_path_count, 0) + coalesce(v_inactive_position_with_active_occupancy_count, 0) + coalesce(v_overlap_position_count, 0);
    v_health_status := case
      when coalesce(v_orphan_reporting_count, 0) > 0 or coalesce(v_missing_path_count, 0) > 0 then 'critical'
      when coalesce(v_inactive_position_with_active_occupancy_count, 0) > 0 or coalesce(v_overlap_position_count, 0) > 0 then 'warning'
      else 'healthy'
    end;

    v_details := jsonb_build_object(
      'tenant_id', p_tenant_id,
      'tenant_schema', p_schema_name,
      'health_status', v_health_status,
      'issue_count', v_issue_count,
      'position_count', v_position_count,
      'active_position_count', v_active_position_count,
      'active_occupancy_count', v_active_occupancy_count,
      'overlap_position_count', v_overlap_position_count,
      'orphan_reporting_count', v_orphan_reporting_count,
      'missing_path_count', v_missing_path_count,
      'inactive_position_with_active_occupancy_count', v_inactive_position_with_active_occupancy_count,
      'trigger', p_trigger
    );
  end if;

  insert into public.platform_hierarchy_health_status (tenant_id, health_status, issue_count, checked_at, details)
  values (p_tenant_id, v_health_status, v_issue_count, timezone('utc', now()), v_details)
  on conflict (tenant_id)
  do update set health_status = excluded.health_status, issue_count = excluded.issue_count, checked_at = excluded.checked_at, details = excluded.details, updated_at = timezone('utc', now());

  insert into public.platform_hierarchy_metadata (tenant_id, last_health_check_at, last_self_test_at, last_health_status, metadata)
  values (p_tenant_id, timezone('utc', now()), case when p_trigger = 'self_test' then timezone('utc', now()) else null end, v_health_status, jsonb_build_object('last_trigger', p_trigger))
  on conflict (tenant_id)
  do update set
    last_health_check_at = timezone('utc', now()),
    last_self_test_at = case when p_trigger = 'self_test' then timezone('utc', now()) else public.platform_hierarchy_metadata.last_self_test_at end,
    last_health_status = excluded.last_health_status,
    metadata = coalesce(public.platform_hierarchy_metadata.metadata, '{}'::jsonb) || excluded.metadata,
    updated_at = timezone('utc', now());

  v_duration_ms := greatest(floor(extract(epoch from (timezone('utc', now()) - v_started_at)) * 1000)::integer, 0);

  insert into public.platform_hierarchy_performance_log (tenant_id, operation_code, status, duration_ms, details)
  values (
    p_tenant_id,
    'hierarchy_diagnostics',
    case when v_health_status = 'healthy' then 'succeeded' when v_health_status = 'warning' then 'warning' else 'failed' end,
    v_duration_ms,
    v_details
  );

  return public.platform_json_response(true, 'OK', 'Hierarchy diagnostics completed.', v_details);
exception
  when others then
    insert into public.platform_hierarchy_error_log (tenant_id, operation_code, error_code, error_message, details)
    values (p_tenant_id, 'hierarchy_diagnostics', 'UNEXPECTED_ERROR', sqlerrm, jsonb_build_object('tenant_schema', p_schema_name, 'trigger', p_trigger, 'sqlstate', sqlstate, 'sqlerrm', sqlerrm));

    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_hierarchy_run_diagnostics_internal.', jsonb_build_object('tenant_id', p_tenant_id, 'tenant_schema', p_schema_name, 'sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_hierarchy_health_check(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_schema_name text;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Hierarchy health check is restricted to internal callers.', '{}'::jsonb);
  end if;

  if v_tenant_id is null then
    v_tenant_id := public.platform_current_tenant_id();
  end if;
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select schema_name into v_schema_name from public.platform_tenant_registry_view where tenant_id = v_tenant_id and schema_provisioned is true;
  if v_schema_name is null then
    return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_FOUND', 'Tenant schema is not available.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  return public.platform_hierarchy_run_diagnostics_internal(v_tenant_id, v_schema_name, 'health_check');
end;
$function$;

create or replace function public.platform_hierarchy_self_test(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_schema_name text;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Hierarchy self-test is restricted to internal callers.', '{}'::jsonb);
  end if;

  if v_tenant_id is null then
    v_tenant_id := public.platform_current_tenant_id();
  end if;
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select schema_name into v_schema_name from public.platform_tenant_registry_view where tenant_id = v_tenant_id and schema_provisioned is true;
  if v_schema_name is null then
    return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_FOUND', 'Tenant schema is not available.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  return public.platform_hierarchy_run_diagnostics_internal(v_tenant_id, v_schema_name, 'self_test');
end;
$function$;

create or replace function public.platform_search_hierarchy_positions(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_schema_name text;
  v_search_text text := nullif(btrim(p_params->>'search_text'), '');
  v_position_status text := nullif(lower(btrim(p_params->>'position_status')), '');
  v_limit integer := 50;
  v_rows jsonb := '[]'::jsonb;
  v_row_count integer := 0;
  v_cache_available boolean := false;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Hierarchy search is restricted to internal callers.', '{}'::jsonb);
  end if;

  if nullif(p_params->>'limit', '') is not null then
    begin
      v_limit := (p_params->>'limit')::integer;
    exception when others then
      return public.platform_json_response(false, 'INVALID_LIMIT', 'limit must be an integer.', '{}'::jsonb);
    end;
  end if;

  if v_tenant_id is null then
    v_tenant_id := public.platform_current_tenant_id();
  end if;
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select schema_name into v_schema_name from public.platform_tenant_registry_view where tenant_id = v_tenant_id and schema_provisioned is true;
  if v_schema_name is null then
    return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_FOUND', 'Tenant schema is not available.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_limit < 1 then
    v_limit := 1;
  elsif v_limit > 200 then
    v_limit := 200;
  end if;

  select exists (select 1 from public.platform_rm_hierarchy_org_chart_cached_store c where c.tenant_id = v_tenant_id limit 1) into v_cache_available;

  if v_cache_available then
    select count(*)::integer, coalesce(jsonb_agg(to_jsonb(s) order by s.hierarchy_path, s.position_code), '[]'::jsonb)
    into v_row_count, v_rows
    from (
      select *
      from public.platform_rm_hierarchy_org_chart_cached_store c
      where c.tenant_id = v_tenant_id
        and (v_position_status is null or c.position_status = v_position_status)
        and (
          v_search_text is null
          or c.position_code ilike ('%' || v_search_text || '%')
          or c.position_name ilike ('%' || v_search_text || '%')
          or coalesce(c.position_group_code, '') ilike ('%' || v_search_text || '%')
          or coalesce(c.position_group_name, '') ilike ('%' || v_search_text || '%')
          or coalesce(c.operational_employee_code, '') ilike ('%' || v_search_text || '%')
          or coalesce(c.operational_employee_name, '') ilike ('%' || v_search_text || '%')
        )
      order by c.hierarchy_path nulls last, c.position_code
      limit v_limit
    ) s;
  else
    select count(*)::integer, coalesce(jsonb_agg(to_jsonb(s) order by s.hierarchy_path, s.position_code), '[]'::jsonb)
    into v_row_count, v_rows
    from (
      select *
      from public.platform_hierarchy_org_chart_rows_for_schema(v_tenant_id, v_schema_name) c
      where (v_position_status is null or c.position_status = v_position_status)
        and (
          v_search_text is null
          or c.position_code ilike ('%' || v_search_text || '%')
          or c.position_name ilike ('%' || v_search_text || '%')
          or coalesce(c.position_group_code, '') ilike ('%' || v_search_text || '%')
          or coalesce(c.position_group_name, '') ilike ('%' || v_search_text || '%')
          or coalesce(c.operational_employee_code, '') ilike ('%' || v_search_text || '%')
          or coalesce(c.operational_employee_name, '') ilike ('%' || v_search_text || '%')
        )
      order by c.hierarchy_path nulls last, c.position_code
      limit v_limit
    ) s;
  end if;

  return public.platform_json_response(true, 'OK', 'Hierarchy search completed.', jsonb_build_object('tenant_id', v_tenant_id, 'row_count', v_row_count, 'cache_available', v_cache_available, 'rows', v_rows));
end;
$function$;

create or replace function public.platform_hierarchy_capture_backup(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_schema_name text;
  v_backup_id uuid;
  v_snapshot jsonb := '[]'::jsonb;
  v_position_count integer := 0;
  v_occupancy_count integer := 0;
  v_requested_by text := coalesce(nullif(btrim(p_params->>'requested_by'), ''), auth.uid()::text, 'system');
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Hierarchy backup is restricted to internal callers.', '{}'::jsonb);
  end if;

  if v_tenant_id is null then
    v_tenant_id := public.platform_current_tenant_id();
  end if;
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select schema_name into v_schema_name from public.platform_tenant_registry_view where tenant_id = v_tenant_id and schema_provisioned is true;
  if v_schema_name is null then
    return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_FOUND', 'Tenant schema is not available.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  select coalesce(jsonb_agg(to_jsonb(r) order by r.hierarchy_path, r.position_code), '[]'::jsonb), count(*)::integer, count(*) filter (where r.operational_employee_id is not null)::integer
  into v_snapshot, v_position_count, v_occupancy_count
  from public.platform_hierarchy_org_chart_rows_for_schema(v_tenant_id, v_schema_name) r;

  insert into public.platform_hierarchy_backup_log (tenant_id, backup_kind, position_count, occupancy_count, snapshot_payload, details, requested_by)
  values (v_tenant_id, 'org_chart_snapshot', v_position_count, v_occupancy_count, v_snapshot, jsonb_build_object('tenant_schema', v_schema_name), v_requested_by)
  returning backup_log_id into v_backup_id;

  insert into public.platform_hierarchy_metadata (tenant_id, last_backup_at, metadata)
  values (v_tenant_id, timezone('utc', now()), jsonb_build_object('last_backup_id', v_backup_id))
  on conflict (tenant_id)
  do update set
    last_backup_at = excluded.last_backup_at,
    metadata = coalesce(public.platform_hierarchy_metadata.metadata, '{}'::jsonb) || excluded.metadata,
    updated_at = timezone('utc', now());

  return public.platform_json_response(true, 'OK', 'Hierarchy backup captured.', jsonb_build_object('backup_log_id', v_backup_id, 'tenant_id', v_tenant_id, 'position_count', v_position_count, 'occupancy_count', v_occupancy_count));
exception
  when others then
    insert into public.platform_hierarchy_error_log (tenant_id, operation_code, error_code, error_message, details)
    values (v_tenant_id, 'hierarchy_backup', 'UNEXPECTED_ERROR', sqlerrm, jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));

    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_hierarchy_capture_backup.', jsonb_build_object('tenant_id', v_tenant_id, 'sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_hierarchy_run_maintenance(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_trigger_source text := coalesce(nullif(btrim(p_params->>'source'), ''), 'manual');
  v_lock_key text := 'hierarchy_runtime_maintenance';
  v_run_id uuid;
  v_refresh_request jsonb;
  v_refresh_execute jsonb := '{}'::jsonb;
  v_refresh_run_id uuid;
  v_refresh_status text := '';
  v_refresh_row_count integer := 0;
  v_cache_refreshed boolean := false;
  v_tenant record;
  v_diag_result jsonb;
  v_diag_status text := '';
  v_tenant_checked_count integer := 0;
  v_healthy_tenant_count integer := 0;
  v_warning_tenant_count integer := 0;
  v_critical_tenant_count integer := 0;
  v_failed_tenant_ids jsonb := '[]'::jsonb;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Hierarchy maintenance is restricted to internal callers.', '{}'::jsonb);
  end if;

  delete from public.platform_hierarchy_maintenance_lock where lock_key = v_lock_key and lock_expires_at < timezone('utc', now());

  insert into public.platform_hierarchy_maintenance_lock (lock_key, tenant_id, lock_expires_at, details)
  values (v_lock_key, null, timezone('utc', now()) + interval '20 minutes', jsonb_build_object('trigger_source', v_trigger_source))
  on conflict do nothing;

  if not found then
    return public.platform_json_response(false, 'MAINTENANCE_ALREADY_RUNNING', 'Hierarchy maintenance is already running.', jsonb_build_object('lock_key', v_lock_key));
  end if;

  insert into public.platform_hierarchy_maintenance_run (maintenance_code, trigger_source, run_status, details)
  values ('hierarchy_maintenance', v_trigger_source, 'running', jsonb_build_object('trigger_source', v_trigger_source))
  returning run_id into v_run_id;

  v_refresh_request := public.platform_request_read_model_refresh(jsonb_build_object('read_model_code', 'hierarchy_org_chart_cached_store', 'refresh_trigger', 'schedule', 'requested_by', 'hierarchy_maintenance'));
  if coalesce((v_refresh_request->>'success')::boolean, false) is not true then
    raise exception 'platform_request_read_model_refresh failed: %', v_refresh_request::text;
  end if;

  v_refresh_run_id := nullif(v_refresh_request->'details'->>'run_id', '')::uuid;
  v_refresh_status := coalesce(v_refresh_request->'details'->>'status', '');

  if v_refresh_status = 'queued' then
    v_refresh_execute := public.platform_execute_read_model_refresh(jsonb_build_object('run_id', v_refresh_run_id, 'capture_row_count', true));
    if coalesce((v_refresh_execute->>'success')::boolean, false) is not true then
      raise exception 'platform_execute_read_model_refresh failed: %', v_refresh_execute::text;
    end if;
    v_refresh_row_count := coalesce(nullif(v_refresh_execute->'details'->>'row_count', '')::integer, 0);
    v_cache_refreshed := true;
  end if;

  for v_tenant in
    select tenant_id, schema_name
    from public.platform_tenant_registry_view
    where schema_provisioned is true
      and schema_name like 'tenant_%'
      and coalesce(background_processing_allowed, true) is true
    order by schema_name
  loop
    v_diag_result := public.platform_hierarchy_run_diagnostics_internal(v_tenant.tenant_id, v_tenant.schema_name, 'maintenance');
    v_tenant_checked_count := v_tenant_checked_count + 1;

    if coalesce((v_diag_result->>'success')::boolean, false) is true then
      v_diag_status := coalesce(v_diag_result->'details'->>'health_status', 'critical');
    else
      v_diag_status := 'critical';
      v_failed_tenant_ids := v_failed_tenant_ids || jsonb_build_array(v_tenant.tenant_id);
    end if;

    if v_diag_status = 'healthy' then
      v_healthy_tenant_count := v_healthy_tenant_count + 1;
    elsif v_diag_status = 'warning' then
      v_warning_tenant_count := v_warning_tenant_count + 1;
    else
      v_critical_tenant_count := v_critical_tenant_count + 1;
    end if;

    insert into public.platform_hierarchy_metadata (tenant_id, last_cache_refresh_at, last_maintenance_at, metadata)
    values (
      v_tenant.tenant_id,
      case when v_cache_refreshed then timezone('utc', now()) else null end,
      timezone('utc', now()),
      jsonb_build_object('last_maintenance_trigger', v_trigger_source)
    )
    on conflict (tenant_id)
    do update set
      last_cache_refresh_at = case when v_cache_refreshed then timezone('utc', now()) else public.platform_hierarchy_metadata.last_cache_refresh_at end,
      last_maintenance_at = timezone('utc', now()),
      metadata = coalesce(public.platform_hierarchy_metadata.metadata, '{}'::jsonb) || excluded.metadata,
      updated_at = timezone('utc', now());
  end loop;

  update public.platform_hierarchy_maintenance_run
  set run_status = 'succeeded',
      refresh_run_id = v_refresh_run_id,
      tenant_checked_count = v_tenant_checked_count,
      healthy_tenant_count = v_healthy_tenant_count,
      warning_tenant_count = v_warning_tenant_count,
      critical_tenant_count = v_critical_tenant_count,
      details = jsonb_build_object('trigger_source', v_trigger_source, 'cache_refreshed', v_cache_refreshed, 'refresh_row_count', v_refresh_row_count, 'refresh_request', v_refresh_request, 'refresh_execute', v_refresh_execute, 'failed_tenant_ids', v_failed_tenant_ids),
      completed_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where run_id = v_run_id;

  delete from public.platform_hierarchy_maintenance_lock where lock_key = v_lock_key;

  return public.platform_json_response(true, 'OK', 'Hierarchy maintenance completed.', jsonb_build_object('run_id', v_run_id, 'refresh_run_id', v_refresh_run_id, 'cache_refreshed', v_cache_refreshed, 'refresh_row_count', v_refresh_row_count, 'tenant_checked_count', v_tenant_checked_count, 'healthy_tenant_count', v_healthy_tenant_count, 'warning_tenant_count', v_warning_tenant_count, 'critical_tenant_count', v_critical_tenant_count, 'failed_tenant_ids', v_failed_tenant_ids));
exception
  when others then
    if v_run_id is not null then
      update public.platform_hierarchy_maintenance_run
      set run_status = 'failed',
          refresh_run_id = v_refresh_run_id,
          details = jsonb_build_object('trigger_source', v_trigger_source, 'refresh_request', v_refresh_request, 'refresh_execute', v_refresh_execute, 'sqlstate', sqlstate, 'sqlerrm', sqlerrm),
          completed_at = timezone('utc', now()),
          updated_at = timezone('utc', now())
      where run_id = v_run_id;
    end if;

    insert into public.platform_hierarchy_error_log (tenant_id, operation_code, error_code, error_message, details)
    values (null, 'hierarchy_maintenance', 'UNEXPECTED_ERROR', sqlerrm, jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm, 'trigger_source', v_trigger_source));

    delete from public.platform_hierarchy_maintenance_lock where lock_key = v_lock_key;

    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_hierarchy_run_maintenance.', jsonb_build_object('run_id', v_run_id, 'sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_hierarchy_run_maintenance_scheduler()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  return public.platform_hierarchy_run_maintenance(jsonb_build_object('source', 'pg_cron'));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_hierarchy_run_maintenance_scheduler.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

revoke all on public.platform_hierarchy_metadata from public, anon, authenticated;
revoke all on public.platform_hierarchy_health_status from public, anon, authenticated;
revoke all on public.platform_hierarchy_error_log from public, anon, authenticated;
revoke all on public.platform_hierarchy_performance_log from public, anon, authenticated;
revoke all on public.platform_hierarchy_backup_log from public, anon, authenticated;
revoke all on public.platform_hierarchy_maintenance_lock from public, anon, authenticated;
revoke all on public.platform_hierarchy_maintenance_run from public, anon, authenticated;
revoke all on public.platform_rm_hierarchy_org_chart_cached_store from public, anon, authenticated;
revoke all on public.platform_rm_hierarchy_org_chart_cached from public, anon, authenticated;
revoke all on public.platform_rm_hierarchy_position_history from public, anon, authenticated;
revoke all on public.platform_rm_hierarchy_metrics_summary from public, anon, authenticated;
revoke all on public.platform_rm_hierarchy_health_status from public, anon, authenticated;

revoke all on function public.platform_hierarchy_org_chart_rows_for_schema(uuid, text) from public, anon, authenticated;
revoke all on function public.platform_hierarchy_org_chart_cache_seed_rows() from public, anon, authenticated;
revoke all on function public.platform_hierarchy_position_history_rows() from public, anon, authenticated;
revoke all on function public.platform_hierarchy_metrics_summary_rows() from public, anon, authenticated;
revoke all on function public.platform_hierarchy_health_status_rows() from public, anon, authenticated;
revoke all on function public.platform_hierarchy_run_diagnostics_internal(uuid, text, text) from public, anon, authenticated;
revoke all on function public.platform_hierarchy_health_check(jsonb) from public, anon, authenticated;
revoke all on function public.platform_hierarchy_self_test(jsonb) from public, anon, authenticated;
revoke all on function public.platform_search_hierarchy_positions(jsonb) from public, anon, authenticated;
revoke all on function public.platform_hierarchy_capture_backup(jsonb) from public, anon, authenticated;
revoke all on function public.platform_hierarchy_run_maintenance(jsonb) from public, anon, authenticated;
revoke all on function public.platform_hierarchy_run_maintenance_scheduler() from public, anon, authenticated;

grant all on public.platform_hierarchy_metadata to service_role;
grant all on public.platform_hierarchy_health_status to service_role;
grant all on public.platform_hierarchy_error_log to service_role;
grant all on public.platform_hierarchy_performance_log to service_role;
grant all on public.platform_hierarchy_backup_log to service_role;
grant all on public.platform_hierarchy_maintenance_lock to service_role;
grant all on public.platform_hierarchy_maintenance_run to service_role;
grant select on public.platform_rm_hierarchy_org_chart_cached_store to service_role;
grant select on public.platform_rm_hierarchy_org_chart_cached to service_role;
grant select on public.platform_rm_hierarchy_position_history to service_role;
grant select on public.platform_rm_hierarchy_metrics_summary to service_role;
grant select on public.platform_rm_hierarchy_health_status to service_role;
grant usage, select on sequence public.platform_hierarchy_error_log_error_log_id_seq to service_role;
grant usage, select on sequence public.platform_hierarchy_performance_log_performance_log_id_seq to service_role;
grant execute on function public.platform_hierarchy_position_history_rows() to service_role;
grant execute on function public.platform_hierarchy_metrics_summary_rows() to service_role;
grant execute on function public.platform_hierarchy_health_status_rows() to service_role;
grant execute on function public.platform_hierarchy_health_check(jsonb) to service_role;
grant execute on function public.platform_hierarchy_self_test(jsonb) to service_role;
grant execute on function public.platform_search_hierarchy_positions(jsonb) to service_role;
grant execute on function public.platform_hierarchy_capture_backup(jsonb) to service_role;
grant execute on function public.platform_hierarchy_run_maintenance(jsonb) to service_role;
grant execute on function public.platform_hierarchy_run_maintenance_scheduler() to service_role;

insert into public.platform_read_model_catalog (
  read_model_code, module_code, read_model_name, schema_placement, storage_kind, ownership_scope, object_name,
  refresh_strategy, refresh_mode, refresh_owner_code, refresh_function_name, freshness_sla_seconds, notes, metadata
) values
('hierarchy_org_chart_cached_store', 'HIERARCHY', 'Hierarchy Org Chart Cached Store', 'public', 'materialized_view', 'platform_shared', 'platform_rm_hierarchy_org_chart_cached_store', 'scheduled', 'full', 'hierarchy_operator', null, 1800, 'Cached hierarchy org-chart store refreshed by HIERARCHY maintenance every 30 minutes.', jsonb_build_object('scope', 'hierarchy_runtime_support')),
('hierarchy_org_chart_cached', 'HIERARCHY', 'Hierarchy Org Chart Cached', 'public', 'view', 'platform_shared', 'platform_rm_hierarchy_org_chart_cached', 'none', 'none', 'hierarchy_operator', null, null, 'Current-tenant security-invoker alias over the cached hierarchy org-chart store.', jsonb_build_object('scope', 'hierarchy_runtime_support')),
('hierarchy_position_history', 'HIERARCHY', 'Hierarchy Position History', 'public', 'view', 'platform_shared', 'platform_rm_hierarchy_position_history', 'none', 'none', 'hierarchy_operator', null, null, 'Current-tenant hierarchy occupancy history read surface.', jsonb_build_object('scope', 'hierarchy_runtime_support')),
('hierarchy_metrics_summary', 'HIERARCHY', 'Hierarchy Metrics Summary', 'public', 'view', 'platform_shared', 'platform_rm_hierarchy_metrics_summary', 'none', 'none', 'hierarchy_operator', null, null, 'Current-tenant hierarchy operational metrics summary.', jsonb_build_object('scope', 'hierarchy_runtime_support')),
('hierarchy_health_status', 'HIERARCHY', 'Hierarchy Health Status', 'public', 'view', 'platform_shared', 'platform_rm_hierarchy_health_status', 'none', 'none', 'hierarchy_operator', null, null, 'Current-tenant hierarchy health and maintenance status surface.', jsonb_build_object('scope', 'hierarchy_runtime_support'))
on conflict (read_model_code)
do update set
  module_code = excluded.module_code,
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
