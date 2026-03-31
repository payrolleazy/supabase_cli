create or replace function public.platform_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

create or replace function public.platform_json_response(
  p_success boolean,
  p_code text,
  p_message text,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'success', p_success,
    'code', p_code,
    'message', p_message,
    'details', coalesce(p_details, '{}'::jsonb)
  );
$$;

create or replace function public.platform_try_uuid(p_value text)
returns uuid
language plpgsql
immutable
as $$
declare
  v_uuid uuid;
begin
  if p_value is null or btrim(p_value) = '' then
    return null;
  end if;

  begin
    v_uuid := btrim(p_value)::uuid;
  exception
    when invalid_text_representation then
      return null;
  end;

  return v_uuid;
end;
$$;

create or replace function public.platform_normalize_tenant_code(p_input text)
returns text
language plpgsql
immutable
as $$
declare
  v_value text;
begin
  if p_input is null then
    return null;
  end if;

  v_value := lower(btrim(p_input));
  v_value := regexp_replace(v_value, '[^a-z0-9]+', '_', 'g');
  v_value := regexp_replace(v_value, '^_+|_+$', '', 'g');
  v_value := regexp_replace(v_value, '_{2,}', '_', 'g');

  if v_value = '' then
    return null;
  end if;

  return v_value;
end;
$$;

create or replace function public.platform_resolve_actor()
returns uuid
language sql
stable
as $$
  select auth.uid();
$$;

create or replace function public.platform_access_transition_allowed(
  p_from text,
  p_to text
)
returns boolean
language sql
immutable
as $$
  select case
    when p_from is null then p_to = 'active'
    when p_from = p_to then true
    when p_from = 'active' and p_to in ('dormant_access_blocked', 'disabled') then true
    when p_from = 'dormant_access_blocked' and p_to in ('dormant_background_blocked', 'active', 'disabled') then true
    when p_from = 'dormant_background_blocked' and p_to in ('active', 'disabled') then true
    when p_from = 'disabled' and p_to in ('active', 'terminated') then true
    else false
  end;
$$;

create or replace function public.platform_provisioning_transition_allowed(
  p_from text,
  p_to text
)
returns boolean
language sql
immutable
as $$
  select case
    when p_from is null then p_to = 'requested'
    when p_from = p_to then true
    when p_from = 'requested' and p_to in ('registry_created', 'failed', 'disabled') then true
    when p_from = 'registry_created' and p_to in ('schema_pending', 'failed', 'disabled') then true
    when p_from = 'schema_pending' and p_to in ('schema_ready', 'failed', 'disabled') then true
    when p_from = 'schema_ready' and p_to in ('foundation_ready', 'failed', 'disabled') then true
    when p_from = 'foundation_ready' and p_to in ('ready_for_routing', 'failed', 'disabled') then true
    when p_from = 'ready_for_routing' and p_to in ('failed', 'disabled') then true
    when p_from = 'failed' and p_to in ('registry_created', 'schema_pending', 'schema_ready', 'foundation_ready', 'ready_for_routing', 'disabled') then true
    when p_from = 'disabled' and p_to in ('registry_created', 'schema_pending', 'schema_ready', 'foundation_ready', 'ready_for_routing') then true
    else false
  end;
$$;

create table if not exists public.platform_tenant (
  tenant_id uuid primary key default gen_random_uuid(),
  tenant_code text not null unique,
  schema_name text unique,
  display_name text not null,
  legal_name text,
  default_currency_code text not null default 'INR',
  default_timezone text not null default 'Asia/Kolkata',
  tenant_kind text not null default 'client',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid,
  metadata jsonb not null default '{}'::jsonb,
  constraint platform_tenant_tenant_code_format_chk
    check (tenant_code ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'),
  constraint platform_tenant_schema_name_format_chk
    check (schema_name is null or schema_name ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_tenant_display_name_chk
    check (btrim(display_name) <> ''),
  constraint platform_tenant_default_currency_code_chk
    check (default_currency_code = upper(default_currency_code) and char_length(default_currency_code) between 3 and 8),
  constraint platform_tenant_default_timezone_chk
    check (btrim(default_timezone) <> ''),
  constraint platform_tenant_tenant_kind_chk
    check (btrim(tenant_kind) <> ''),
  constraint platform_tenant_metadata_object_chk
    check (jsonb_typeof(metadata) = 'object')
);

create table if not exists public.platform_tenant_provisioning (
  tenant_id uuid primary key references public.platform_tenant(tenant_id) on delete cascade,
  provisioning_status text not null,
  schema_provisioned boolean not null default false,
  foundation_version text,
  latest_completed_step text,
  last_error_code text,
  last_error_message text,
  last_error_at timestamptz,
  ready_for_routing boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  details jsonb not null default '{}'::jsonb,
  constraint platform_tenant_provisioning_status_chk
    check (provisioning_status in (
      'requested',
      'registry_created',
      'schema_pending',
      'schema_ready',
      'foundation_ready',
      'ready_for_routing',
      'failed',
      'disabled'
    )),
  constraint platform_tenant_provisioning_details_object_chk
    check (jsonb_typeof(details) = 'object')
);

create table if not exists public.platform_tenant_access_state (
  tenant_id uuid primary key references public.platform_tenant(tenant_id) on delete cascade,
  access_state text not null,
  reason_code text,
  reason_details jsonb not null default '{}'::jsonb,
  billing_state text not null,
  dormant_started_at timestamptz,
  background_stop_at timestamptz,
  restored_at timestamptz,
  disabled_at timestamptz,
  terminated_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  updated_by uuid,
  constraint platform_tenant_access_state_access_chk
    check (access_state in (
      'active',
      'dormant_access_blocked',
      'dormant_background_blocked',
      'disabled',
      'terminated'
    )),
  constraint platform_tenant_access_state_billing_chk
    check (billing_state in (
      'current',
      'overdue',
      'dormant',
      'suspended',
      'closed'
    )),
  constraint platform_tenant_access_state_reason_details_object_chk
    check (jsonb_typeof(reason_details) = 'object'),
  constraint platform_tenant_access_state_dormant_window_chk
    check (
      (access_state in ('dormant_access_blocked', 'dormant_background_blocked') and dormant_started_at is not null and background_stop_at is not null)
      or
      (access_state not in ('dormant_access_blocked', 'dormant_background_blocked'))
    )
);

create table if not exists public.platform_tenant_status_history (
  id bigint generated by default as identity primary key,
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  status_family text not null,
  from_status text,
  to_status text not null,
  transition_reason_code text,
  transition_details jsonb not null default '{}'::jsonb,
  changed_at timestamptz not null default timezone('utc', now()),
  changed_by uuid,
  source text not null,
  constraint platform_tenant_status_history_family_chk
    check (status_family in ('provisioning', 'access', 'billing')),
  constraint platform_tenant_status_history_source_chk
    check (btrim(source) <> ''),
  constraint platform_tenant_status_history_details_object_chk
    check (jsonb_typeof(transition_details) = 'object')
);

create index if not exists idx_platform_tenant_provisioning_status_ready
  on public.platform_tenant_provisioning (provisioning_status, ready_for_routing);

create index if not exists idx_platform_tenant_access_state_lookup
  on public.platform_tenant_access_state (access_state, billing_state);

create index if not exists idx_platform_tenant_access_state_cutoff
  on public.platform_tenant_access_state (background_stop_at)
  where access_state = 'dormant_access_blocked';

create index if not exists idx_platform_tenant_status_history_tenant_changed_at
  on public.platform_tenant_status_history (tenant_id, changed_at desc);

alter table public.platform_tenant enable row level security;
alter table public.platform_tenant_provisioning enable row level security;
alter table public.platform_tenant_access_state enable row level security;
alter table public.platform_tenant_status_history enable row level security;

drop trigger if exists trg_platform_tenant_set_updated_at on public.platform_tenant;
create trigger trg_platform_tenant_set_updated_at
before update on public.platform_tenant
for each row
execute function public.platform_set_updated_at();

drop trigger if exists trg_platform_tenant_provisioning_set_updated_at on public.platform_tenant_provisioning;
create trigger trg_platform_tenant_provisioning_set_updated_at
before update on public.platform_tenant_provisioning
for each row
execute function public.platform_set_updated_at();

drop trigger if exists trg_platform_tenant_access_state_set_updated_at on public.platform_tenant_access_state;
create trigger trg_platform_tenant_access_state_set_updated_at
before update on public.platform_tenant_access_state
for each row
execute function public.platform_set_updated_at();

create or replace function public.platform_append_status_history(
  p_tenant_id uuid,
  p_status_family text,
  p_from_status text,
  p_to_status text,
  p_transition_reason_code text default null,
  p_transition_details jsonb default '{}'::jsonb,
  p_changed_by uuid default null,
  p_source text default 'system'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.platform_tenant_status_history (
    tenant_id,
    status_family,
    from_status,
    to_status,
    transition_reason_code,
    transition_details,
    changed_by,
    source
  )
  values (
    p_tenant_id,
    p_status_family,
    p_from_status,
    p_to_status,
    p_transition_reason_code,
    coalesce(p_transition_details, '{}'::jsonb),
    p_changed_by,
    coalesce(nullif(btrim(p_source), ''), 'system')
  );
end;
$$;

create or replace function public.platform_resolve_tenant_id(p_params jsonb)
returns uuid
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid;
  v_tenant_code text;
begin
  if p_params ? 'tenant_id' then
    v_tenant_id := public.platform_try_uuid(p_params->>'tenant_id');
    if v_tenant_id is not null then
      return v_tenant_id;
    end if;
  end if;

  v_tenant_code := public.platform_normalize_tenant_code(p_params->>'tenant_code');
  if v_tenant_code is null then
    return null;
  end if;

  select pt.tenant_id
  into v_tenant_id
  from public.platform_tenant pt
  where pt.tenant_code = v_tenant_code;

  return v_tenant_id;
end;
$$;

create or replace view public.platform_tenant_registry_view as
with latest_status as (
  select distinct on (h.tenant_id)
    h.tenant_id,
    h.status_family,
    h.to_status,
    h.transition_reason_code,
    h.changed_at,
    h.source
  from public.platform_tenant_status_history h
  order by h.tenant_id, h.changed_at desc, h.id desc
)
select
  pt.tenant_id,
  pt.tenant_code,
  pt.schema_name,
  pt.display_name,
  pt.legal_name,
  pt.default_currency_code,
  pt.default_timezone,
  pt.tenant_kind,
  pt.created_at,
  pt.updated_at,
  pt.created_by,
  pt.metadata,
  ptp.provisioning_status,
  ptp.schema_provisioned,
  ptp.foundation_version,
  ptp.latest_completed_step,
  ptp.last_error_code,
  ptp.last_error_message,
  ptp.last_error_at,
  ptp.ready_for_routing,
  ptp.details as provisioning_details,
  pas.access_state,
  pas.reason_code,
  pas.reason_details,
  pas.billing_state,
  pas.dormant_started_at,
  pas.background_stop_at,
  pas.restored_at,
  pas.disabled_at,
  pas.terminated_at,
  case
    when ptp.ready_for_routing and pas.access_state = 'active' then true
    else false
  end as client_access_allowed,
  case
    when ptp.ready_for_routing and pas.access_state in ('active', 'dormant_access_blocked') then true
    else false
  end as background_processing_allowed,
  ls.status_family as latest_transition_family,
  ls.to_status as latest_transition_status,
  ls.transition_reason_code as latest_transition_reason_code,
  ls.changed_at as latest_transition_at,
  ls.source as latest_transition_source
from public.platform_tenant pt
join public.platform_tenant_provisioning ptp
  on ptp.tenant_id = pt.tenant_id
join public.platform_tenant_access_state pas
  on pas.tenant_id = pt.tenant_id
left join latest_status ls
  on ls.tenant_id = pt.tenant_id;;
