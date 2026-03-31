create table if not exists public.platform_read_model_catalog (
  read_model_code text primary key,
  module_code text not null,
  read_model_name text not null,
  schema_placement text not null check (schema_placement in ('public', 'tenant_schema')),
  storage_kind text not null check (storage_kind in ('view', 'materialized_view', 'summary_table')),
  ownership_scope text not null check (ownership_scope in ('platform_shared', 'tenant_owned')),
  object_name text not null,
  refresh_strategy text not null default 'none' check (refresh_strategy in ('none', 'manual', 'event_driven', 'scheduled', 'hybrid')),
  refresh_mode text not null default 'none' check (refresh_mode in ('none', 'full', 'incremental')),
  refresh_owner_code text not null,
  refresh_function_name text null,
  freshness_sla_seconds integer null check (freshness_sla_seconds is null or freshness_sla_seconds >= 0),
  notes text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_read_model_catalog_object_name_chk check (
    (schema_placement = 'public' and ownership_scope = 'platform_shared' and object_name like 'platform_rm_%')
    or
    (schema_placement = 'tenant_schema' and ownership_scope = 'tenant_owned' and object_name like 'rm_%')
  ),
  constraint platform_read_model_catalog_storage_refresh_chk check (
    (storage_kind = 'view' and refresh_strategy = 'none' and refresh_mode = 'none')
    or
    (storage_kind = 'materialized_view' and refresh_strategy <> 'none' and refresh_mode = 'full')
    or
    (storage_kind = 'summary_table' and refresh_strategy <> 'none' and refresh_mode in ('full', 'incremental'))
  ),
  constraint platform_read_model_catalog_refresh_function_name_chk check (
    refresh_function_name is null
    or refresh_function_name ~ '^[A-Za-z_][A-Za-z0-9_]*\\.[A-Za-z_][A-Za-z0-9_]*$'
  )
);

create unique index if not exists idx_platform_read_model_catalog_object
on public.platform_read_model_catalog (schema_placement, object_name);

alter table public.platform_read_model_catalog enable row level security;

drop policy if exists platform_read_model_catalog_service_role_all on public.platform_read_model_catalog;
create policy platform_read_model_catalog_service_role_all
on public.platform_read_model_catalog
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_read_model_catalog_set_updated_at on public.platform_read_model_catalog;
create trigger trg_platform_read_model_catalog_set_updated_at
before update on public.platform_read_model_catalog
for each row
execute function public.platform_set_updated_at();

create table if not exists public.platform_read_model_refresh_state (
  id uuid primary key default gen_random_uuid(),
  read_model_code text not null references public.platform_read_model_catalog(read_model_code) on delete cascade,
  tenant_id uuid null references public.platform_tenant(tenant_id) on delete cascade,
  scope_key text generated always as (coalesce(tenant_id::text, 'platform_shared')) stored,
  refresh_status text not null default 'never_run' check (refresh_status in ('never_run', 'queued', 'running', 'succeeded', 'failed')),
  active_run_id uuid null,
  last_requested_at timestamptz null,
  last_started_at timestamptz null,
  last_completed_at timestamptz null,
  last_succeeded_at timestamptz null,
  last_failed_at timestamptz null,
  last_duration_ms integer null check (last_duration_ms is null or last_duration_ms >= 0),
  last_row_count bigint null check (last_row_count is null or last_row_count >= 0),
  last_error_code text null,
  last_error_message text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_read_model_refresh_state_unique unique (read_model_code, scope_key)
);

create index if not exists idx_platform_read_model_refresh_state_tenant
on public.platform_read_model_refresh_state (tenant_id, read_model_code);

create index if not exists idx_platform_read_model_refresh_state_status
on public.platform_read_model_refresh_state (refresh_status, last_requested_at desc);

alter table public.platform_read_model_refresh_state enable row level security;

drop policy if exists platform_read_model_refresh_state_service_role_all on public.platform_read_model_refresh_state;
create policy platform_read_model_refresh_state_service_role_all
on public.platform_read_model_refresh_state
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_read_model_refresh_state_set_updated_at on public.platform_read_model_refresh_state;
create trigger trg_platform_read_model_refresh_state_set_updated_at
before update on public.platform_read_model_refresh_state
for each row
execute function public.platform_set_updated_at();

create table if not exists public.platform_read_model_refresh_run (
  id uuid primary key default gen_random_uuid(),
  read_model_code text not null references public.platform_read_model_catalog(read_model_code) on delete cascade,
  tenant_id uuid null references public.platform_tenant(tenant_id) on delete cascade,
  refresh_trigger text not null default 'manual' check (refresh_trigger in ('manual', 'event', 'schedule', 'repair', 'validation')),
  refresh_mode text not null check (refresh_mode in ('full', 'incremental')),
  requested_by text not null default 'system',
  request_idempotency_key text null,
  status text not null default 'queued' check (status in ('queued', 'running', 'succeeded', 'failed', 'cancelled')),
  async_job_id uuid null references public.platform_async_job(job_id) on delete set null,
  requested_at timestamptz not null default timezone('utc', now()),
  started_at timestamptz null,
  completed_at timestamptz null,
  duration_ms integer null check (duration_ms is null or duration_ms >= 0),
  row_count bigint null check (row_count is null or row_count >= 0),
  error_code text null,
  error_message text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_platform_read_model_refresh_run_lookup
on public.platform_read_model_refresh_run (read_model_code, tenant_id, requested_at desc);

create index if not exists idx_platform_read_model_refresh_run_status
on public.platform_read_model_refresh_run (status, requested_at desc);

create index if not exists idx_platform_read_model_refresh_run_async_job
on public.platform_read_model_refresh_run (async_job_id);

create unique index if not exists idx_platform_read_model_refresh_run_idempotency
on public.platform_read_model_refresh_run (request_idempotency_key)
where request_idempotency_key is not null;

alter table public.platform_read_model_refresh_run enable row level security;

drop policy if exists platform_read_model_refresh_run_service_role_all on public.platform_read_model_refresh_run;
create policy platform_read_model_refresh_run_service_role_all
on public.platform_read_model_refresh_run
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_read_model_refresh_run_set_updated_at on public.platform_read_model_refresh_run;
create trigger trg_platform_read_model_refresh_run_set_updated_at
before update on public.platform_read_model_refresh_run
for each row
execute function public.platform_set_updated_at();

create or replace function public.platform_register_read_model(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_read_model_code text := nullif(trim(coalesce(p_params->>'read_model_code', '')), '');
  v_module_code text := nullif(trim(coalesce(p_params->>'module_code', '')), '');
  v_read_model_name text := nullif(trim(coalesce(p_params->>'read_model_name', '')), '');
  v_schema_placement text := coalesce(nullif(trim(coalesce(p_params->>'schema_placement', '')), ''), 'public');
  v_storage_kind text := coalesce(nullif(trim(coalesce(p_params->>'storage_kind', '')), ''), 'view');
  v_ownership_scope text := coalesce(nullif(trim(coalesce(p_params->>'ownership_scope', '')), ''), 'platform_shared');
  v_object_name text := nullif(trim(coalesce(p_params->>'object_name', '')), '');
  v_refresh_strategy text := coalesce(nullif(trim(coalesce(p_params->>'refresh_strategy', '')), ''), 'none');
  v_refresh_mode text := coalesce(nullif(trim(coalesce(p_params->>'refresh_mode', '')), ''), 'none');
  v_refresh_owner_code text := nullif(trim(coalesce(p_params->>'refresh_owner_code', '')), '');
  v_refresh_function_name text := nullif(trim(coalesce(p_params->>'refresh_function_name', '')), '');
  v_freshness_sla_seconds integer := nullif(p_params->>'freshness_sla_seconds', '')::integer;
  v_notes text := nullif(p_params->>'notes', '');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_exists boolean := false;
begin
  if v_read_model_code is null then
    return public.platform_json_response(false, 'READ_MODEL_CODE_REQUIRED', 'read_model_code is required.', '{}'::jsonb);
  end if;

  if v_module_code is null then
    return public.platform_json_response(false, 'MODULE_CODE_REQUIRED', 'module_code is required.', jsonb_build_object('read_model_code', v_read_model_code));
  end if;

  if v_read_model_name is null then
    return public.platform_json_response(false, 'READ_MODEL_NAME_REQUIRED', 'read_model_name is required.', jsonb_build_object('read_model_code', v_read_model_code));
  end if;

  if v_object_name is null then
    return public.platform_json_response(false, 'OBJECT_NAME_REQUIRED', 'object_name is required.', jsonb_build_object('read_model_code', v_read_model_code));
  end if;

  if v_refresh_owner_code is null then
    return public.platform_json_response(false, 'REFRESH_OWNER_REQUIRED', 'refresh_owner_code is required.', jsonb_build_object('read_model_code', v_read_model_code));
  end if;

  if v_schema_placement = 'public' then
    if v_storage_kind = 'view' then
      select exists (
        select 1
        from information_schema.views
        where table_schema = 'public'
          and table_name = v_object_name
      )
      into v_exists;
    elsif v_storage_kind = 'materialized_view' then
      select exists (
        select 1
        from pg_matviews
        where schemaname = 'public'
          and matviewname = v_object_name
      )
      into v_exists;
    else
      select exists (
        select 1
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname = v_object_name
          and c.relkind = 'r'
      )
      into v_exists;
    end if;

    if v_exists is not true then
      return public.platform_json_response(
        false,
        'READ_MODEL_OBJECT_NOT_FOUND',
        'The public read-model object does not exist.',
        jsonb_build_object(
          'read_model_code', v_read_model_code,
          'schema_placement', v_schema_placement,
          'storage_kind', v_storage_kind,
          'object_name', v_object_name
        )
      );
    end if;
  end if;

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
  values (
    v_read_model_code,
    v_module_code,
    v_read_model_name,
    v_schema_placement,
    v_storage_kind,
    v_ownership_scope,
    v_object_name,
    v_refresh_strategy,
    v_refresh_mode,
    v_refresh_owner_code,
    v_refresh_function_name,
    v_freshness_sla_seconds,
    v_notes,
    v_metadata
  )
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

  return public.platform_json_response(
    true,
    'OK',
    'Read model registered successfully.',
    jsonb_build_object(
      'read_model_code', v_read_model_code,
      'module_code', v_module_code,
      'storage_kind', v_storage_kind,
      'schema_placement', v_schema_placement,
      'object_name', v_object_name
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_read_model.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace view public.platform_rm_tenant_registry
as
select *
from public.platform_tenant_registry_view;

alter view public.platform_rm_tenant_registry set (security_invoker = true);

create or replace view public.platform_rm_actor_tenant_membership
as
select *
from public.platform_actor_tenant_membership_view;

alter view public.platform_rm_actor_tenant_membership set (security_invoker = true);

create or replace view public.platform_rm_schema_provisioning
as
select *
from public.platform_schema_provisioning_view;

alter view public.platform_rm_schema_provisioning set (security_invoker = true);

create or replace view public.platform_rm_async_dispatch_readiness
as
select *
from public.platform_async_dispatch_readiness_view;

alter view public.platform_rm_async_dispatch_readiness set (security_invoker = true);

create or replace view public.platform_rm_async_stale_lease
as
select *
from public.platform_async_stale_lease_view;

alter view public.platform_rm_async_stale_lease set (security_invoker = true);

create or replace view public.platform_rm_async_dead_letter
as
select *
from public.platform_async_dead_letter_view;

alter view public.platform_rm_async_dead_letter set (security_invoker = true);

create or replace view public.platform_rm_async_queue_health
as
select *
from public.platform_async_queue_health_view;

alter view public.platform_rm_async_queue_health set (security_invoker = true);

create or replace view public.platform_rm_tenant_commercial_state
as
select *
from public.platform_tenant_commercial_state_view;

alter view public.platform_rm_tenant_commercial_state set (security_invoker = true);

create or replace view public.platform_rm_refresh_status
as
select
  c.read_model_code,
  c.module_code,
  c.read_model_name,
  c.schema_placement,
  c.storage_kind,
  c.ownership_scope,
  c.object_name,
  c.refresh_strategy,
  c.refresh_mode,
  c.refresh_owner_code,
  c.refresh_function_name,
  c.freshness_sla_seconds,
  coalesce(s.scope_key, case when c.ownership_scope = 'platform_shared' then 'platform_shared' else 'tenant_uninitialized' end) as scope_key,
  s.tenant_id,
  coalesce(s.refresh_status, 'never_run') as refresh_status,
  s.active_run_id,
  s.last_requested_at,
  s.last_started_at,
  s.last_completed_at,
  s.last_succeeded_at,
  s.last_failed_at,
  s.last_duration_ms,
  s.last_row_count,
  s.last_error_code,
  s.last_error_message,
  case
    when c.storage_kind = 'view' then false
    when c.freshness_sla_seconds is null then false
    when s.last_succeeded_at is null then true
    when timezone('utc', now()) > s.last_succeeded_at + make_interval(secs => c.freshness_sla_seconds) then true
    else false
  end as is_stale
from public.platform_read_model_catalog c
left join public.platform_read_model_refresh_state s
  on s.read_model_code = c.read_model_code;

alter view public.platform_rm_refresh_status set (security_invoker = true);

drop materialized view if exists public.platform_rm_refresh_overview;
create materialized view public.platform_rm_refresh_overview
as
select
  module_code,
  count(distinct read_model_code) as registered_model_count,
  count(*) filter (where storage_kind = 'view') as direct_view_state_rows,
  count(*) filter (where storage_kind <> 'view') as refreshable_state_rows,
  count(*) filter (where refresh_status = 'queued') as queued_state_rows,
  count(*) filter (where refresh_status = 'running') as running_state_rows,
  count(*) filter (where refresh_status = 'failed') as failed_state_rows,
  count(*) filter (where is_stale) as stale_state_rows,
  max(last_completed_at) as last_completed_at
from public.platform_rm_refresh_status
where read_model_code <> 'platform_refresh_overview'
group by module_code;

create unique index if not exists idx_platform_rm_refresh_overview_module_code
on public.platform_rm_refresh_overview (module_code);

do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_read_model(jsonb_build_object(
    'read_model_code', 'platform_tenant_registry',
    'module_code', 'platform_f01',
    'read_model_name', 'Platform Tenant Registry',
    'schema_placement', 'public',
    'storage_kind', 'view',
    'ownership_scope', 'platform_shared',
    'object_name', 'platform_rm_tenant_registry',
    'refresh_strategy', 'none',
    'refresh_mode', 'none',
    'refresh_owner_code', 'direct_view',
    'notes', 'Standardized wrapper over platform_tenant_registry_view.'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'platform_tenant_registry registration failed: %', v_result;
  end if;

  v_result := public.platform_register_read_model(jsonb_build_object(
    'read_model_code', 'platform_actor_tenant_membership',
    'module_code', 'platform_f01',
    'read_model_name', 'Platform Actor Tenant Membership',
    'schema_placement', 'public',
    'storage_kind', 'view',
    'ownership_scope', 'platform_shared',
    'object_name', 'platform_rm_actor_tenant_membership',
    'refresh_strategy', 'none',
    'refresh_mode', 'none',
    'refresh_owner_code', 'direct_view',
    'notes', 'Standardized wrapper over platform_actor_tenant_membership_view.'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'platform_actor_tenant_membership registration failed: %', v_result;
  end if;

  v_result := public.platform_register_read_model(jsonb_build_object(
    'read_model_code', 'platform_schema_provisioning',
    'module_code', 'platform_f02',
    'read_model_name', 'Platform Schema Provisioning',
    'schema_placement', 'public',
    'storage_kind', 'view',
    'ownership_scope', 'platform_shared',
    'object_name', 'platform_rm_schema_provisioning',
    'refresh_strategy', 'none',
    'refresh_mode', 'none',
    'refresh_owner_code', 'direct_view',
    'notes', 'Standardized wrapper over platform_schema_provisioning_view.'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'platform_schema_provisioning registration failed: %', v_result;
  end if;

  v_result := public.platform_register_read_model(jsonb_build_object(
    'read_model_code', 'platform_async_dispatch_readiness',
    'module_code', 'platform_f04',
    'read_model_name', 'Platform Async Dispatch Readiness',
    'schema_placement', 'public',
    'storage_kind', 'view',
    'ownership_scope', 'platform_shared',
    'object_name', 'platform_rm_async_dispatch_readiness',
    'refresh_strategy', 'none',
    'refresh_mode', 'none',
    'refresh_owner_code', 'direct_view',
    'notes', 'Standardized wrapper over platform_async_dispatch_readiness_view.'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'platform_async_dispatch_readiness registration failed: %', v_result;
  end if;

  v_result := public.platform_register_read_model(jsonb_build_object(
    'read_model_code', 'platform_async_stale_lease',
    'module_code', 'platform_f04',
    'read_model_name', 'Platform Async Stale Lease',
    'schema_placement', 'public',
    'storage_kind', 'view',
    'ownership_scope', 'platform_shared',
    'object_name', 'platform_rm_async_stale_lease',
    'refresh_strategy', 'none',
    'refresh_mode', 'none',
    'refresh_owner_code', 'direct_view',
    'notes', 'Standardized wrapper over platform_async_stale_lease_view.'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'platform_async_stale_lease registration failed: %', v_result;
  end if;

  v_result := public.platform_register_read_model(jsonb_build_object(
    'read_model_code', 'platform_async_dead_letter',
    'module_code', 'platform_f04',
    'read_model_name', 'Platform Async Dead Letter',
    'schema_placement', 'public',
    'storage_kind', 'view',
    'ownership_scope', 'platform_shared',
    'object_name', 'platform_rm_async_dead_letter',
    'refresh_strategy', 'none',
    'refresh_mode', 'none',
    'refresh_owner_code', 'direct_view',
    'notes', 'Standardized wrapper over platform_async_dead_letter_view.'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'platform_async_dead_letter registration failed: %', v_result;
  end if;

  v_result := public.platform_register_read_model(jsonb_build_object(
    'read_model_code', 'platform_async_queue_health',
    'module_code', 'platform_f04',
    'read_model_name', 'Platform Async Queue Health',
    'schema_placement', 'public',
    'storage_kind', 'view',
    'ownership_scope', 'platform_shared',
    'object_name', 'platform_rm_async_queue_health',
    'refresh_strategy', 'none',
    'refresh_mode', 'none',
    'refresh_owner_code', 'direct_view',
    'notes', 'Standardized wrapper over platform_async_queue_health_view.'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'platform_async_queue_health registration failed: %', v_result;
  end if;

  v_result := public.platform_register_read_model(jsonb_build_object(
    'read_model_code', 'platform_tenant_commercial_state',
    'module_code', 'platform_f05',
    'read_model_name', 'Platform Tenant Commercial State',
    'schema_placement', 'public',
    'storage_kind', 'view',
    'ownership_scope', 'platform_shared',
    'object_name', 'platform_rm_tenant_commercial_state',
    'refresh_strategy', 'none',
    'refresh_mode', 'none',
    'refresh_owner_code', 'direct_view',
    'notes', 'Standardized wrapper over platform_tenant_commercial_state_view.'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'platform_tenant_commercial_state registration failed: %', v_result;
  end if;

  v_result := public.platform_register_read_model(jsonb_build_object(
    'read_model_code', 'platform_refresh_status',
    'module_code', 'platform_f06',
    'read_model_name', 'Platform Refresh Status',
    'schema_placement', 'public',
    'storage_kind', 'view',
    'ownership_scope', 'platform_shared',
    'object_name', 'platform_rm_refresh_status',
    'refresh_strategy', 'none',
    'refresh_mode', 'none',
    'refresh_owner_code', 'direct_view',
    'notes', 'Governed refresh-status view for registered read models.'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'platform_refresh_status registration failed: %', v_result;
  end if;

  v_result := public.platform_register_read_model(jsonb_build_object(
    'read_model_code', 'platform_refresh_overview',
    'module_code', 'platform_f06',
    'read_model_name', 'Platform Refresh Overview',
    'schema_placement', 'public',
    'storage_kind', 'materialized_view',
    'ownership_scope', 'platform_shared',
    'object_name', 'platform_rm_refresh_overview',
    'refresh_strategy', 'manual',
    'refresh_mode', 'full',
    'refresh_owner_code', 'platform_f06_operator',
    'freshness_sla_seconds', 3600,
    'notes', 'Materialized operational overview for refresh-state observability.'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'platform_refresh_overview registration failed: %', v_result;
  end if;

  refresh materialized view public.platform_rm_refresh_overview;
end
$$;

create or replace function public.platform_get_read_model_refresh_status(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_read_model_code text := nullif(trim(coalesce(p_params->>'read_model_code', '')), '');
  v_module_code text := nullif(trim(coalesce(p_params->>'module_code', '')), '');
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_shared_only boolean := coalesce((p_params->>'shared_only')::boolean, false);
  v_items jsonb;
begin
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'read_model_code', read_model_code,
        'module_code', module_code,
        'read_model_name', read_model_name,
        'schema_placement', schema_placement,
        'storage_kind', storage_kind,
        'ownership_scope', ownership_scope,
        'object_name', object_name,
        'refresh_strategy', refresh_strategy,
        'refresh_mode', refresh_mode,
        'refresh_owner_code', refresh_owner_code,
        'refresh_function_name', refresh_function_name,
        'freshness_sla_seconds', freshness_sla_seconds,
        'tenant_id', tenant_id,
        'scope_key', scope_key,
        'refresh_status', refresh_status,
        'last_requested_at', last_requested_at,
        'last_started_at', last_started_at,
        'last_completed_at', last_completed_at,
        'last_succeeded_at', last_succeeded_at,
        'last_failed_at', last_failed_at,
        'last_duration_ms', last_duration_ms,
        'last_row_count', last_row_count,
        'last_error_code', last_error_code,
        'last_error_message', last_error_message,
        'is_stale', is_stale
      )
      order by module_code, read_model_code, tenant_id nulls first
    ),
    '[]'::jsonb
  )
  into v_items
  from public.platform_rm_refresh_status
  where (v_read_model_code is null or read_model_code = v_read_model_code)
    and (v_module_code is null or module_code = v_module_code)
    and (
      (v_tenant_id is not null and tenant_id = v_tenant_id)
      or (v_tenant_id is null and v_shared_only is true and tenant_id is null)
      or (v_tenant_id is null and v_shared_only is false)
    );

  return public.platform_json_response(true, 'OK', 'Read-model refresh status fetched successfully.', jsonb_build_object('items', v_items));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_get_read_model_refresh_status.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_execute_read_model_refresh(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_run_id uuid := nullif(p_params->>'run_id', '')::uuid;
  v_capture_row_count boolean := coalesce((p_params->>'capture_row_count')::boolean, false);
  v_begin_result jsonb;
  v_complete_result jsonb;
  v_fail_result jsonb;
  v_run public.platform_read_model_refresh_run%rowtype;
  v_catalog public.platform_read_model_catalog%rowtype;
  v_tenant_schema text;
  v_function_schema text;
  v_function_name text;
  v_function_result jsonb;
  v_row_count bigint := null;
  v_payload jsonb;
begin
  if v_run_id is null then
    return public.platform_json_response(false, 'RUN_ID_REQUIRED', 'run_id is required.', '{}'::jsonb);
  end if;

  select *
  into v_run
  from public.platform_read_model_refresh_run
  where id = v_run_id
  for update;

  if not found then
    return public.platform_json_response(false, 'RUN_NOT_FOUND', 'Refresh run not found.', jsonb_build_object('run_id', v_run_id));
  end if;

  if v_run.status = 'succeeded' then
    return public.platform_json_response(true, 'OK', 'Refresh run already completed.', jsonb_build_object('run_id', v_run_id, 'status', v_run.status));
  end if;

  if v_run.status <> 'queued' then
    return public.platform_json_response(false, 'RUN_NOT_EXECUTABLE', 'Only queued refresh runs can be executed.', jsonb_build_object('run_id', v_run_id, 'status', v_run.status));
  end if;

  select *
  into v_catalog
  from public.platform_read_model_catalog
  where read_model_code = v_run.read_model_code;

  if not found then
    return public.platform_json_response(false, 'READ_MODEL_NOT_FOUND', 'Read model is not registered.', jsonb_build_object('read_model_code', v_run.read_model_code));
  end if;

  v_begin_result := public.platform_begin_read_model_refresh(jsonb_build_object('run_id', v_run_id));
  if coalesce((v_begin_result->>'success')::boolean, false) is not true then
    return v_begin_result;
  end if;

  if v_catalog.storage_kind = 'materialized_view' then
    if v_catalog.schema_placement = 'public' then
      v_tenant_schema := 'public';
    else
      if v_run.tenant_id is null then
        v_fail_result := public.platform_fail_read_model_refresh(jsonb_build_object('run_id', v_run_id, 'error_code', 'TENANT_ID_REQUIRED', 'error_message', 'tenant_id is required for tenant-owned materialized-view refresh.'));
        return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id is required for tenant-owned materialized-view refresh.', jsonb_build_object('run_id', v_run_id, 'fail_result', v_fail_result));
      end if;

      select schema_name
      into v_tenant_schema
      from public.platform_tenant
      where tenant_id = v_run.tenant_id;

      if v_tenant_schema is null then
        v_fail_result := public.platform_fail_read_model_refresh(jsonb_build_object('run_id', v_run_id, 'error_code', 'TENANT_SCHEMA_NOT_FOUND', 'error_message', 'Tenant schema was not found for the refresh request.'));
        return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_FOUND', 'Tenant schema was not found for the refresh request.', jsonb_build_object('run_id', v_run_id, 'tenant_id', v_run.tenant_id, 'fail_result', v_fail_result));
      end if;
    end if;

    execute format('refresh materialized view %I.%I', v_tenant_schema, v_catalog.object_name);

    if v_capture_row_count then
      execute format('select count(*) from %I.%I', v_tenant_schema, v_catalog.object_name)
      into v_row_count;
    end if;
  elsif v_catalog.refresh_function_name is not null then
    v_function_schema := split_part(v_catalog.refresh_function_name, '.', 1);
    v_function_name := split_part(v_catalog.refresh_function_name, '.', 2);
    v_payload := jsonb_build_object(
      'run_id', v_run_id,
      'read_model_code', v_run.read_model_code,
      'tenant_id', v_run.tenant_id,
      'refresh_mode', v_run.refresh_mode,
      'refresh_trigger', v_run.refresh_trigger,
      'requested_by', v_run.requested_by
    ) || coalesce(v_run.metadata, '{}'::jsonb);

    execute format('select %I.%I($1)', v_function_schema, v_function_name)
    into v_function_result
    using v_payload;

    if jsonb_typeof(v_function_result) = 'object'
       and v_function_result ? 'success'
       and coalesce((v_function_result->>'success')::boolean, false) is not true then
      v_fail_result := public.platform_fail_read_model_refresh(jsonb_build_object(
        'run_id', v_run_id,
        'error_code', coalesce(v_function_result->>'code', 'REFRESH_FUNCTION_FAILED'),
        'error_message', coalesce(v_function_result->>'message', 'Refresh function returned failure.')
      ));
      return public.platform_json_response(false, 'REFRESH_FUNCTION_FAILED', 'Refresh function returned failure.', jsonb_build_object('run_id', v_run_id, 'result', v_function_result, 'fail_result', v_fail_result));
    end if;

    if jsonb_typeof(v_function_result) = 'object' and v_function_result ? 'details' then
      v_row_count := nullif(v_function_result->'details'->>'row_count', '')::bigint;
    end if;
  else
    v_fail_result := public.platform_fail_read_model_refresh(jsonb_build_object('run_id', v_run_id, 'error_code', 'NO_REFRESH_EXECUTOR', 'error_message', 'No refresh execution path is configured for this read model.'));
    return public.platform_json_response(false, 'NO_REFRESH_EXECUTOR', 'No refresh execution path is configured for this read model.', jsonb_build_object('run_id', v_run_id, 'read_model_code', v_run.read_model_code, 'fail_result', v_fail_result));
  end if;

  v_complete_result := public.platform_complete_read_model_refresh(jsonb_build_object(
    'run_id', v_run_id,
    'row_count', v_row_count,
    'metadata', case when v_function_result is null then '{}'::jsonb else jsonb_build_object('refresh_result', v_function_result) end
  ));

  if coalesce((v_complete_result->>'success')::boolean, false) is not true then
    return v_complete_result;
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'Read-model refresh executed successfully.',
    jsonb_build_object(
      'run_id', v_run_id,
      'read_model_code', v_run.read_model_code,
      'tenant_id', v_run.tenant_id,
      'row_count', v_row_count
    )
  );
exception
  when others then
    perform public.platform_fail_read_model_refresh(jsonb_build_object(
      'run_id', v_run_id,
      'error_code', 'REFRESH_EXECUTION_FAILED',
      'error_message', sqlerrm
    ));
    return public.platform_json_response(false, 'REFRESH_EXECUTION_FAILED', 'Unexpected error in platform_execute_read_model_refresh.', jsonb_build_object('run_id', v_run_id, 'sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_request_read_model_refresh(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_read_model_code text := nullif(trim(coalesce(p_params->>'read_model_code', '')), '');
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_refresh_trigger text := coalesce(nullif(trim(coalesce(p_params->>'refresh_trigger', '')), ''), 'manual');
  v_requested_by text := coalesce(nullif(trim(coalesce(p_params->>'requested_by', '')), ''), auth.uid()::text, 'system');
  v_request_idempotency_key text := nullif(trim(coalesce(p_params->>'request_idempotency_key', '')), '');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_catalog public.platform_read_model_catalog%rowtype;
  v_existing_run public.platform_read_model_refresh_run%rowtype;
  v_run_id uuid;
  v_refresh_mode text;
  v_now timestamptz := timezone('utc', now());
begin
  if v_read_model_code is null then
    return public.platform_json_response(false, 'READ_MODEL_CODE_REQUIRED', 'read_model_code is required.', '{}'::jsonb);
  end if;

  select *
  into v_catalog
  from public.platform_read_model_catalog
  where read_model_code = v_read_model_code;

  if not found then
    return public.platform_json_response(false, 'READ_MODEL_NOT_FOUND', 'Read model is not registered.', jsonb_build_object('read_model_code', v_read_model_code));
  end if;

  if v_catalog.storage_kind = 'view' or v_catalog.refresh_strategy = 'none' then
    return public.platform_json_response(false, 'READ_MODEL_NOT_REFRESHABLE', 'This read model does not require refresh.', jsonb_build_object('read_model_code', v_read_model_code));
  end if;

  if v_catalog.ownership_scope = 'platform_shared' and v_tenant_id is not null then
    return public.platform_json_response(false, 'TENANT_NOT_ALLOWED', 'Shared read models must not be requested with tenant scope.', jsonb_build_object('read_model_code', v_read_model_code, 'tenant_id', v_tenant_id));
  end if;

  if v_catalog.ownership_scope = 'tenant_owned' and v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required for tenant-owned read models.', jsonb_build_object('read_model_code', v_read_model_code));
  end if;

  if v_request_idempotency_key is not null then
    select *
    into v_existing_run
    from public.platform_read_model_refresh_run
    where request_idempotency_key = v_request_idempotency_key
    order by requested_at desc
    limit 1;

    if found then
      return public.platform_json_response(
        true,
        'OK',
        'Existing refresh request reused by idempotency key.',
        jsonb_build_object(
          'run_id', v_existing_run.id,
          'read_model_code', v_existing_run.read_model_code,
          'tenant_id', v_existing_run.tenant_id,
          'status', v_existing_run.status,
          'reused', true
        )
      );
    end if;
  end if;

  select *
  into v_existing_run
  from public.platform_read_model_refresh_run
  where read_model_code = v_read_model_code
    and tenant_id is not distinct from v_tenant_id
    and status in ('queued', 'running')
  order by requested_at desc
  limit 1;

  if found then
    return public.platform_json_response(
      true,
      'OK',
      'Existing in-flight refresh request reused.',
      jsonb_build_object(
        'run_id', v_existing_run.id,
        'read_model_code', v_existing_run.read_model_code,
        'tenant_id', v_existing_run.tenant_id,
        'status', v_existing_run.status,
        'reused', true
      )
    );
  end if;

  v_refresh_mode := coalesce(nullif(trim(coalesce(p_params->>'refresh_mode', '')), ''), v_catalog.refresh_mode);

  insert into public.platform_read_model_refresh_run (
    read_model_code,
    tenant_id,
    refresh_trigger,
    refresh_mode,
    requested_by,
    request_idempotency_key,
    status,
    async_job_id,
    requested_at,
    metadata
  )
  values (
    v_read_model_code,
    v_tenant_id,
    v_refresh_trigger,
    v_refresh_mode,
    v_requested_by,
    v_request_idempotency_key,
    'queued',
    nullif(p_params->>'async_job_id', '')::uuid,
    v_now,
    v_metadata
  )
  returning id
  into v_run_id;

  insert into public.platform_read_model_refresh_state (
    read_model_code,
    tenant_id,
    refresh_status,
    active_run_id,
    last_requested_at,
    metadata
  )
  values (
    v_read_model_code,
    v_tenant_id,
    'queued',
    null,
    v_now,
    v_metadata
  )
  on conflict (read_model_code, scope_key)
  do update set
    tenant_id = excluded.tenant_id,
    refresh_status = 'queued',
    active_run_id = null,
    last_requested_at = excluded.last_requested_at,
    metadata = public.platform_read_model_refresh_state.metadata || excluded.metadata,
    updated_at = timezone('utc', now());

  return public.platform_json_response(
    true,
    'OK',
    'Read-model refresh requested successfully.',
    jsonb_build_object(
      'run_id', v_run_id,
      'read_model_code', v_read_model_code,
      'tenant_id', v_tenant_id,
      'status', 'queued'
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_request_read_model_refresh.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_begin_read_model_refresh(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_run_id uuid := nullif(p_params->>'run_id', '')::uuid;
  v_run public.platform_read_model_refresh_run%rowtype;
  v_now timestamptz := timezone('utc', now());
begin
  if v_run_id is null then
    return public.platform_json_response(false, 'RUN_ID_REQUIRED', 'run_id is required.', '{}'::jsonb);
  end if;

  select *
  into v_run
  from public.platform_read_model_refresh_run
  where id = v_run_id
  for update;

  if not found then
    return public.platform_json_response(false, 'RUN_NOT_FOUND', 'Refresh run not found.', jsonb_build_object('run_id', v_run_id));
  end if;

  if v_run.status = 'succeeded' then
    return public.platform_json_response(true, 'OK', 'Refresh run already completed.', jsonb_build_object('run_id', v_run_id, 'status', v_run.status));
  end if;

  if v_run.status = 'running' then
    return public.platform_json_response(false, 'RUN_ALREADY_RUNNING', 'Refresh run is already running.', jsonb_build_object('run_id', v_run_id));
  end if;

  if v_run.status <> 'queued' then
    return public.platform_json_response(false, 'RUN_NOT_STARTABLE', 'Only queued refresh runs can be started.', jsonb_build_object('run_id', v_run_id, 'status', v_run.status));
  end if;

  update public.platform_read_model_refresh_run
  set
    status = 'running',
    started_at = v_now,
    completed_at = null,
    duration_ms = null,
    error_code = null,
    error_message = null
  where id = v_run_id;

  insert into public.platform_read_model_refresh_state (
    read_model_code,
    tenant_id,
    refresh_status,
    active_run_id,
    last_requested_at,
    last_started_at,
    metadata
  )
  values (
    v_run.read_model_code,
    v_run.tenant_id,
    'running',
    v_run_id,
    v_run.requested_at,
    v_now,
    v_run.metadata
  )
  on conflict (read_model_code, scope_key)
  do update set
    tenant_id = excluded.tenant_id,
    refresh_status = 'running',
    active_run_id = v_run_id,
    last_requested_at = excluded.last_requested_at,
    last_started_at = excluded.last_started_at,
    metadata = public.platform_read_model_refresh_state.metadata || excluded.metadata,
    updated_at = timezone('utc', now());

  return public.platform_json_response(true, 'OK', 'Refresh run started.', jsonb_build_object('run_id', v_run_id, 'status', 'running'));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_begin_read_model_refresh.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_complete_read_model_refresh(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_run_id uuid := nullif(p_params->>'run_id', '')::uuid;
  v_row_count bigint := nullif(p_params->>'row_count', '')::bigint;
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_run public.platform_read_model_refresh_run%rowtype;
  v_now timestamptz := timezone('utc', now());
  v_duration_ms integer;
begin
  if v_run_id is null then
    return public.platform_json_response(false, 'RUN_ID_REQUIRED', 'run_id is required.', '{}'::jsonb);
  end if;

  select *
  into v_run
  from public.platform_read_model_refresh_run
  where id = v_run_id
  for update;

  if not found then
    return public.platform_json_response(false, 'RUN_NOT_FOUND', 'Refresh run not found.', jsonb_build_object('run_id', v_run_id));
  end if;

  if v_run.status = 'succeeded' then
    return public.platform_json_response(true, 'OK', 'Refresh run already marked as succeeded.', jsonb_build_object('run_id', v_run_id, 'status', v_run.status));
  end if;

  if v_run.status <> 'running' then
    return public.platform_json_response(false, 'RUN_NOT_RUNNING', 'Only running refresh runs can be completed.', jsonb_build_object('run_id', v_run_id, 'status', v_run.status));
  end if;

  v_duration_ms := greatest(0, floor(extract(epoch from (v_now - coalesce(v_run.started_at, v_run.requested_at))) * 1000)::integer);

  update public.platform_read_model_refresh_run
  set
    status = 'succeeded',
    completed_at = v_now,
    duration_ms = v_duration_ms,
    row_count = coalesce(v_row_count, row_count),
    error_code = null,
    error_message = null,
    metadata = public.platform_read_model_refresh_run.metadata || v_metadata
  where id = v_run_id;

  update public.platform_read_model_refresh_state
  set
    refresh_status = 'succeeded',
    active_run_id = null,
    last_completed_at = v_now,
    last_succeeded_at = v_now,
    last_duration_ms = v_duration_ms,
    last_row_count = coalesce(v_row_count, last_row_count),
    last_error_code = null,
    last_error_message = null,
    metadata = public.platform_read_model_refresh_state.metadata || v_metadata,
    updated_at = timezone('utc', now())
  where read_model_code = v_run.read_model_code
    and scope_key = coalesce(v_run.tenant_id::text, 'platform_shared');

  return public.platform_json_response(true, 'OK', 'Refresh run completed successfully.', jsonb_build_object('run_id', v_run_id, 'status', 'succeeded', 'row_count', v_row_count));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_complete_read_model_refresh.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_fail_read_model_refresh(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_run_id uuid := nullif(p_params->>'run_id', '')::uuid;
  v_error_code text := coalesce(nullif(trim(coalesce(p_params->>'error_code', '')), ''), 'REFRESH_FAILED');
  v_error_message text := coalesce(nullif(p_params->>'error_message', ''), 'Read-model refresh failed.');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_run public.platform_read_model_refresh_run%rowtype;
  v_now timestamptz := timezone('utc', now());
  v_duration_ms integer;
begin
  if v_run_id is null then
    return public.platform_json_response(false, 'RUN_ID_REQUIRED', 'run_id is required.', '{}'::jsonb);
  end if;

  select *
  into v_run
  from public.platform_read_model_refresh_run
  where id = v_run_id
  for update;

  if not found then
    return public.platform_json_response(false, 'RUN_NOT_FOUND', 'Refresh run not found.', jsonb_build_object('run_id', v_run_id));
  end if;

  v_duration_ms := greatest(0, floor(extract(epoch from (v_now - coalesce(v_run.started_at, v_run.requested_at))) * 1000)::integer);

  update public.platform_read_model_refresh_run
  set
    status = 'failed',
    completed_at = v_now,
    duration_ms = v_duration_ms,
    error_code = v_error_code,
    error_message = v_error_message,
    metadata = public.platform_read_model_refresh_run.metadata || v_metadata
  where id = v_run_id;

  insert into public.platform_read_model_refresh_state (
    read_model_code,
    tenant_id,
    refresh_status,
    active_run_id,
    last_requested_at,
    last_started_at,
    last_completed_at,
    last_failed_at,
    last_duration_ms,
    last_error_code,
    last_error_message,
    metadata
  )
  values (
    v_run.read_model_code,
    v_run.tenant_id,
    'failed',
    null,
    v_run.requested_at,
    v_run.started_at,
    v_now,
    v_now,
    v_duration_ms,
    v_error_code,
    v_error_message,
    v_metadata
  )
  on conflict (read_model_code, scope_key)
  do update set
    tenant_id = excluded.tenant_id,
    refresh_status = 'failed',
    active_run_id = null,
    last_requested_at = excluded.last_requested_at,
    last_started_at = excluded.last_started_at,
    last_completed_at = excluded.last_completed_at,
    last_failed_at = excluded.last_failed_at,
    last_duration_ms = excluded.last_duration_ms,
    last_error_code = excluded.last_error_code,
    last_error_message = excluded.last_error_message,
    metadata = public.platform_read_model_refresh_state.metadata || excluded.metadata,
    updated_at = timezone('utc', now());

  return public.platform_json_response(true, 'OK', 'Refresh run marked as failed.', jsonb_build_object('run_id', v_run_id, 'status', 'failed', 'error_code', v_error_code));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_fail_read_model_refresh.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
