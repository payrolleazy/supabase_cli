create table if not exists public.platform_actor_tenant_membership (
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  actor_user_id uuid not null,
  membership_status text not null default 'active',
  is_default_tenant boolean not null default false,
  routing_status text not null default 'enabled',
  linked_at timestamptz not null default now(),
  linked_by uuid,
  disabled_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_actor_tenant_membership_pkey primary key (tenant_id, actor_user_id),
  constraint platform_actor_tenant_membership_status_check check (membership_status in ('active', 'invited', 'disabled', 'revoked')),
  constraint platform_actor_tenant_membership_routing_status_check check (routing_status in ('enabled', 'blocked')),
  constraint platform_actor_tenant_membership_default_guard check (is_default_tenant = false or (membership_status = 'active' and routing_status = 'enabled'))
);

create index if not exists idx_platform_actor_tenant_membership_actor_status
  on public.platform_actor_tenant_membership (actor_user_id, membership_status, routing_status);

create unique index if not exists uq_platform_actor_default_active_membership
  on public.platform_actor_tenant_membership (actor_user_id)
  where is_default_tenant = true and membership_status = 'active' and routing_status = 'enabled';

drop trigger if exists trg_platform_actor_tenant_membership_set_updated_at on public.platform_actor_tenant_membership;
create trigger trg_platform_actor_tenant_membership_set_updated_at
before update on public.platform_actor_tenant_membership
for each row
execute function public.platform_set_updated_at();

alter table public.platform_actor_tenant_membership enable row level security;

create or replace view public.platform_actor_tenant_membership_view as
select
  patm.tenant_id,
  pt.tenant_code,
  pt.schema_name,
  patm.actor_user_id,
  patm.membership_status,
  patm.routing_status,
  patm.is_default_tenant,
  ptrv.ready_for_routing,
  ptrv.access_state,
  ptrv.client_access_allowed,
  ptrv.background_processing_allowed,
  ptrv.background_stop_at
from public.platform_actor_tenant_membership patm
join public.platform_tenant pt on pt.tenant_id = patm.tenant_id
left join public.platform_tenant_registry_view ptrv on ptrv.tenant_id = patm.tenant_id;

create or replace function public.platform_is_internal_caller()
returns boolean
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
begin
  return auth.role() = 'service_role' or session_user = 'postgres';
end;
$function$;

create or replace function public.platform_current_tenant_id()
returns uuid
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select public.platform_try_uuid(nullif(current_setting('platform.tenant_id', true), ''));
$function$;

create or replace function public.platform_current_tenant_schema()
returns text
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select nullif(current_setting('platform.tenant_schema', true), '');
$function$;

create or replace function public.platform_current_actor_user_id()
returns uuid
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select public.platform_try_uuid(nullif(current_setting('platform.actor_user_id', true), ''));
$function$;

create or replace function public.platform_current_execution_mode()
returns text
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select nullif(current_setting('platform.execution_mode', true), '');
$function$;

create or replace function public.platform_current_access_state()
returns text
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select nullif(current_setting('platform.access_state', true), '');
$function$;

create or replace function public.platform_get_current_execution_context()
returns jsonb
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select public.platform_json_response(true, 'OK', 'Current execution context resolved.', jsonb_build_object(
    'execution_mode', nullif(current_setting('platform.execution_mode', true), ''),
    'actor_user_id', public.platform_try_uuid(nullif(current_setting('platform.actor_user_id', true), '')),
    'tenant_id', public.platform_try_uuid(nullif(current_setting('platform.tenant_id', true), '')),
    'tenant_code', nullif(current_setting('platform.tenant_code', true), ''),
    'tenant_schema', nullif(current_setting('platform.tenant_schema', true), ''),
    'access_state', nullif(current_setting('platform.access_state', true), ''),
    'client_access_allowed', coalesce(nullif(current_setting('platform.client_access_allowed', true), '')::boolean, false),
    'background_processing_allowed', coalesce(nullif(current_setting('platform.background_processing_allowed', true), '')::boolean, false),
    'context_source', nullif(current_setting('platform.context_source', true), '')
  ));
$function$;;
