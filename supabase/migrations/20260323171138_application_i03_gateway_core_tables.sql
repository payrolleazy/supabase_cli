create table if not exists public.platform_gateway_operation (
  operation_code text primary key,
  operation_mode text not null,
  dispatch_kind text not null,
  operation_status text not null default 'draft',
  route_policy text not null default 'tenant_required',
  tenant_requirement text not null default 'required',
  idempotency_policy text not null default 'optional',
  rate_limit_policy text not null default 'default',
  max_limit_per_request integer,
  binding_ref text not null,
  dispatch_config jsonb not null default '{}'::jsonb,
  static_params jsonb not null default '{}'::jsonb,
  request_contract jsonb not null default '{}'::jsonb,
  response_contract jsonb not null default '{}'::jsonb,
  group_name text,
  synopsis text,
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid,
  updated_by uuid,
  constraint platform_gateway_operation_code_check check (btrim(operation_code) <> ''),
  constraint platform_gateway_operation_mode_check check (
    operation_mode = any (array['read', 'mutate', 'action'])
  ),
  constraint platform_gateway_operation_dispatch_kind_check check (
    dispatch_kind = any (array['read_surface', 'mutation_adapter', 'function_action'])
  ),
  constraint platform_gateway_operation_status_check check (
    operation_status = any (array['draft', 'active', 'disabled'])
  ),
  constraint platform_gateway_operation_route_policy_check check (
    route_policy = any (array['tenant_required'])
  ),
  constraint platform_gateway_operation_tenant_requirement_check check (
    tenant_requirement = any (array['required'])
  ),
  constraint platform_gateway_operation_idempotency_policy_check check (
    idempotency_policy = any (array['none', 'optional', 'required'])
  ),
  constraint platform_gateway_operation_binding_ref_check check (btrim(binding_ref) <> ''),
  constraint platform_gateway_operation_dispatch_config_check check (jsonb_typeof(dispatch_config) = 'object'),
  constraint platform_gateway_operation_static_params_check check (jsonb_typeof(static_params) = 'object'),
  constraint platform_gateway_operation_request_contract_check check (jsonb_typeof(request_contract) = 'object'),
  constraint platform_gateway_operation_response_contract_check check (jsonb_typeof(response_contract) = 'object'),
  constraint platform_gateway_operation_rate_limit_policy_check check (
    rate_limit_policy = any (array['default'])
  ),
  constraint platform_gateway_operation_metadata_check check (jsonb_typeof(metadata) = 'object'),
  constraint platform_gateway_operation_limit_check check (
    max_limit_per_request is null
    or (max_limit_per_request > 0 and max_limit_per_request <= 5000)
  ),
  constraint platform_gateway_operation_mode_dispatch_match check (
    (operation_mode = 'read' and dispatch_kind = 'read_surface')
    or (operation_mode = 'mutate' and dispatch_kind = 'mutation_adapter')
    or (operation_mode = 'action' and dispatch_kind = 'function_action')
  )
);

create index if not exists idx_platform_gateway_operation_status
on public.platform_gateway_operation (operation_status, operation_mode);

create index if not exists idx_platform_gateway_operation_group
on public.platform_gateway_operation (group_name, operation_status);

alter table public.platform_gateway_operation enable row level security;
drop policy if exists platform_gateway_operation_service_role_all on public.platform_gateway_operation;
create policy platform_gateway_operation_service_role_all
on public.platform_gateway_operation
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_gateway_operation_set_updated_at on public.platform_gateway_operation;
create trigger trg_platform_gateway_operation_set_updated_at
before update on public.platform_gateway_operation
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_gateway_operation_role (
  operation_code text not null references public.platform_gateway_operation(operation_code) on delete cascade,
  role_code text not null references public.platform_access_role(role_code),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  created_by uuid,
  constraint platform_gateway_operation_role_pkey primary key (operation_code, role_code),
  constraint platform_gateway_operation_role_metadata_check check (jsonb_typeof(metadata) = 'object')
);

create index if not exists idx_platform_gateway_operation_role_role_code
on public.platform_gateway_operation_role (role_code, operation_code);

alter table public.platform_gateway_operation_role enable row level security;
drop policy if exists platform_gateway_operation_role_service_role_all on public.platform_gateway_operation_role;
create policy platform_gateway_operation_role_service_role_all
on public.platform_gateway_operation_role
for all
to service_role
using (true)
with check (true);

create table if not exists public.platform_gateway_idempotency_claim (
  claim_id uuid primary key default gen_random_uuid(),
  operation_code text not null references public.platform_gateway_operation(operation_code) on delete cascade,
  tenant_id uuid not null references public.platform_tenant(tenant_id),
  actor_user_id uuid not null,
  idempotency_key text not null,
  claim_status text not null default 'claimed',
  request_hash text,
  request_payload jsonb not null default '{}'::jsonb,
  response_payload jsonb not null default '{}'::jsonb,
  error_payload jsonb not null default '{}'::jsonb,
  claimed_at timestamptz not null default timezone('utc', now()),
  completed_at timestamptz,
  expires_at timestamptz not null default (timezone('utc', now()) + interval '1 day'),
  metadata jsonb not null default '{}'::jsonb,
  constraint platform_gateway_idempotency_claim_status_check check (
    claim_status = any (array['claimed', 'succeeded', 'failed', 'expired'])
  ),
  constraint platform_gateway_idempotency_claim_key_check check (btrim(idempotency_key) <> ''),
  constraint platform_gateway_idempotency_claim_request_payload_check check (jsonb_typeof(request_payload) = 'object'),
  constraint platform_gateway_idempotency_claim_response_payload_check check (jsonb_typeof(response_payload) = 'object'),
  constraint platform_gateway_idempotency_claim_error_payload_check check (jsonb_typeof(error_payload) = 'object'),
  constraint platform_gateway_idempotency_claim_metadata_check check (jsonb_typeof(metadata) = 'object'),
  constraint platform_gateway_idempotency_claim_unique unique (operation_code, tenant_id, actor_user_id, idempotency_key)
);

create index if not exists idx_platform_gateway_idempotency_claim_lookup
on public.platform_gateway_idempotency_claim (operation_code, tenant_id, actor_user_id, idempotency_key);

create index if not exists idx_platform_gateway_idempotency_claim_status
on public.platform_gateway_idempotency_claim (claim_status, expires_at);

alter table public.platform_gateway_idempotency_claim enable row level security;
drop policy if exists platform_gateway_idempotency_claim_service_role_all on public.platform_gateway_idempotency_claim;
create policy platform_gateway_idempotency_claim_service_role_all
on public.platform_gateway_idempotency_claim
for all
to service_role
using (true)
with check (true);

create table if not exists public.platform_gateway_request_log (
  request_id uuid primary key default gen_random_uuid(),
  operation_code text,
  actor_user_id uuid,
  tenant_id uuid references public.platform_tenant(tenant_id),
  execution_mode text,
  operation_mode text,
  dispatch_kind text,
  request_status text not null,
  error_code text,
  duration_ms integer,
  idempotency_key text,
  request_payload jsonb not null default '{}'::jsonb,
  response_payload jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  constraint platform_gateway_request_log_status_check check (
    request_status = any (array['succeeded', 'failed', 'replayed', 'blocked'])
  ),
  constraint platform_gateway_request_log_request_payload_check check (jsonb_typeof(request_payload) = 'object'),
  constraint platform_gateway_request_log_response_payload_check check (jsonb_typeof(response_payload) = 'object'),
  constraint platform_gateway_request_log_metadata_check check (jsonb_typeof(metadata) = 'object'),
  constraint platform_gateway_request_log_duration_check check (duration_ms is null or duration_ms >= 0)
);

create index if not exists idx_platform_gateway_request_log_operation_created
on public.platform_gateway_request_log (operation_code, created_at desc);

create index if not exists idx_platform_gateway_request_log_actor_created
on public.platform_gateway_request_log (actor_user_id, created_at desc);

create index if not exists idx_platform_gateway_request_log_tenant_created
on public.platform_gateway_request_log (tenant_id, created_at desc);

alter table public.platform_gateway_request_log enable row level security;
drop policy if exists platform_gateway_request_log_service_role_all on public.platform_gateway_request_log;
create policy platform_gateway_request_log_service_role_all
on public.platform_gateway_request_log
for all
to service_role
using (true)
with check (true);

create or replace view public.platform_rm_gateway_operation_catalog as
select
  pgo.operation_code,
  pgo.operation_mode,
  pgo.dispatch_kind,
  pgo.operation_status,
  pgo.route_policy,
  pgo.tenant_requirement,
  pgo.idempotency_policy,
  pgo.rate_limit_policy,
  pgo.max_limit_per_request,
  pgo.binding_ref,
  pgo.group_name,
  pgo.synopsis,
  pgo.description,
  pgo.dispatch_config,
  pgo.static_params,
  pgo.request_contract,
  pgo.response_contract,
  pgo.metadata,
  pgo.created_at,
  pgo.updated_at,
  coalesce(
    array_agg(pgor.role_code order by pgor.role_code)
      filter (where pgor.role_code is not null),
    '{}'::text[]
  ) as allowed_role_codes
from public.platform_gateway_operation pgo
left join public.platform_gateway_operation_role pgor
  on pgor.operation_code = pgo.operation_code
group by
  pgo.operation_code,
  pgo.operation_mode,
  pgo.dispatch_kind,
  pgo.operation_status,
  pgo.route_policy,
  pgo.tenant_requirement,
  pgo.idempotency_policy,
  pgo.rate_limit_policy,
  pgo.max_limit_per_request,
  pgo.binding_ref,
  pgo.group_name,
  pgo.synopsis,
  pgo.description,
  pgo.dispatch_config,
  pgo.static_params,
  pgo.request_contract,
  pgo.response_contract,
  pgo.metadata,
  pgo.created_at,
  pgo.updated_at;;
