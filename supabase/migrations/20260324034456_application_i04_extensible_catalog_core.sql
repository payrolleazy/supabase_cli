create table if not exists public.platform_extensible_entity_registry (
  entity_id uuid primary key default gen_random_uuid(),
  entity_code text not null,
  entity_label text not null,
  owner_module_code text not null,
  target_relation_schema text not null default 'public',
  target_relation_name text not null,
  primary_key_column text not null default 'id',
  tenant_scope text not null default 'tenant',
  allow_tenant_override boolean not null default true,
  join_profile_enabled boolean not null default false,
  entity_status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_extensible_entity_registry_entity_code_key unique (entity_code),
  constraint platform_extensible_entity_registry_entity_code_check check (entity_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_extensible_entity_registry_owner_module_code_check check (owner_module_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_extensible_entity_registry_target_relation_schema_check check (target_relation_schema ~ '^[a-z_][a-z0-9_]*$'),
  constraint platform_extensible_entity_registry_target_relation_name_check check (target_relation_name ~ '^[a-z_][a-z0-9_]*$'),
  constraint platform_extensible_entity_registry_primary_key_column_check check (primary_key_column ~ '^[a-z_][a-z0-9_]*$'),
  constraint platform_extensible_entity_registry_tenant_scope_check check (tenant_scope in ('shared', 'tenant')),
  constraint platform_extensible_entity_registry_entity_status_check check (entity_status in ('active', 'inactive')),
  constraint platform_extensible_entity_registry_metadata_check check (jsonb_typeof(metadata) = 'object')
);

create index if not exists idx_platform_extensible_entity_registry_owner_module
on public.platform_extensible_entity_registry (owner_module_code, entity_status);

create index if not exists idx_platform_extensible_entity_registry_target_relation
on public.platform_extensible_entity_registry (target_relation_schema, target_relation_name);

alter table public.platform_extensible_entity_registry enable row level security;

drop policy if exists platform_extensible_entity_registry_service_role_all on public.platform_extensible_entity_registry;
create policy platform_extensible_entity_registry_service_role_all
on public.platform_extensible_entity_registry
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_extensible_entity_registry_set_updated_at on public.platform_extensible_entity_registry;
create trigger trg_platform_extensible_entity_registry_set_updated_at
before update on public.platform_extensible_entity_registry
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_extensible_attribute_schema (
  attribute_schema_id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references public.platform_extensible_entity_registry(entity_id) on delete cascade,
  tenant_id uuid null references public.platform_tenant(tenant_id) on delete cascade,
  scope_tenant_key uuid generated always as (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)) stored,
  attribute_code text not null,
  ui_label text not null,
  data_type text not null,
  is_required boolean not null default false,
  default_value jsonb null,
  validation_rules jsonb not null default '{}'::jsonb,
  sort_order integer not null default 100,
  attribute_status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_extensible_attribute_schema_entity_scope_attribute_key unique (entity_id, scope_tenant_key, attribute_code),
  constraint platform_extensible_attribute_schema_attribute_code_check check (attribute_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_extensible_attribute_schema_data_type_check check (data_type in ('text', 'integer', 'numeric', 'boolean', 'uuid', 'date', 'timestamp', 'object', 'array', 'jsonb')),
  constraint platform_extensible_attribute_schema_sort_order_check check (sort_order >= 0),
  constraint platform_extensible_attribute_schema_attribute_status_check check (attribute_status in ('active', 'inactive')),
  constraint platform_extensible_attribute_schema_validation_rules_check check (jsonb_typeof(validation_rules) = 'object'),
  constraint platform_extensible_attribute_schema_metadata_check check (jsonb_typeof(metadata) = 'object')
);

create index if not exists idx_platform_extensible_attribute_schema_entity_status
on public.platform_extensible_attribute_schema (entity_id, attribute_status, sort_order, attribute_code);

create index if not exists idx_platform_extensible_attribute_schema_tenant_entity
on public.platform_extensible_attribute_schema (scope_tenant_key, entity_id, attribute_status);

alter table public.platform_extensible_attribute_schema enable row level security;

drop policy if exists platform_extensible_attribute_schema_service_role_all on public.platform_extensible_attribute_schema;
create policy platform_extensible_attribute_schema_service_role_all
on public.platform_extensible_attribute_schema
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_extensible_attribute_schema_set_updated_at on public.platform_extensible_attribute_schema;
create trigger trg_platform_extensible_attribute_schema_set_updated_at
before update on public.platform_extensible_attribute_schema
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_extensible_join_profile (
  join_profile_id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references public.platform_extensible_entity_registry(entity_id) on delete cascade,
  tenant_id uuid null references public.platform_tenant(tenant_id) on delete cascade,
  scope_tenant_key uuid generated always as (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)) stored,
  join_profile_code text not null,
  profile_status text not null default 'active',
  join_contract jsonb not null default '{}'::jsonb,
  projection_contract jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_extensible_join_profile_entity_scope_profile_key unique (entity_id, scope_tenant_key, join_profile_code),
  constraint platform_extensible_join_profile_join_profile_code_check check (join_profile_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_extensible_join_profile_profile_status_check check (profile_status in ('active', 'inactive')),
  constraint platform_extensible_join_profile_join_contract_check check (jsonb_typeof(join_contract) = 'object'),
  constraint platform_extensible_join_profile_projection_contract_check check (jsonb_typeof(projection_contract) = 'object'),
  constraint platform_extensible_join_profile_metadata_check check (jsonb_typeof(metadata) = 'object')
);

create index if not exists idx_platform_extensible_join_profile_entity_status
on public.platform_extensible_join_profile (entity_id, profile_status, join_profile_code);

create index if not exists idx_platform_extensible_join_profile_tenant_entity
on public.platform_extensible_join_profile (scope_tenant_key, entity_id, profile_status);

alter table public.platform_extensible_join_profile enable row level security;

drop policy if exists platform_extensible_join_profile_service_role_all on public.platform_extensible_join_profile;
create policy platform_extensible_join_profile_service_role_all
on public.platform_extensible_join_profile
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_extensible_join_profile_set_updated_at on public.platform_extensible_join_profile;
create trigger trg_platform_extensible_join_profile_set_updated_at
before update on public.platform_extensible_join_profile
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_extensible_schema_cache (
  cache_id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references public.platform_extensible_entity_registry(entity_id) on delete cascade,
  tenant_id uuid null references public.platform_tenant(tenant_id) on delete cascade,
  scope_tenant_key uuid generated always as (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)) stored,
  schema_digest text not null,
  schema_descriptor jsonb not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_extensible_schema_cache_entity_scope_key unique (entity_id, scope_tenant_key),
  constraint platform_extensible_schema_cache_schema_digest_check check (length(btrim(schema_digest)) > 0),
  constraint platform_extensible_schema_cache_descriptor_check check (jsonb_typeof(schema_descriptor) = 'object')
);

create index if not exists idx_platform_extensible_schema_cache_expiry
on public.platform_extensible_schema_cache (expires_at);

alter table public.platform_extensible_schema_cache enable row level security;

drop policy if exists platform_extensible_schema_cache_service_role_all on public.platform_extensible_schema_cache;
create policy platform_extensible_schema_cache_service_role_all
on public.platform_extensible_schema_cache
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_extensible_schema_cache_set_updated_at on public.platform_extensible_schema_cache;
create trigger trg_platform_extensible_schema_cache_set_updated_at
before update on public.platform_extensible_schema_cache
for each row execute function public.platform_set_updated_at();

create or replace view public.platform_rm_extensible_entity_catalog
with (security_invoker = true)
as
select
  peer.entity_id,
  peer.entity_code,
  peer.entity_label,
  peer.owner_module_code,
  peer.target_relation_schema,
  peer.target_relation_name,
  peer.primary_key_column,
  peer.tenant_scope,
  peer.allow_tenant_override,
  peer.join_profile_enabled,
  peer.entity_status,
  count(pas.attribute_schema_id) filter (where pas.attribute_status = 'active' and pas.tenant_id is null) as global_attribute_count,
  count(pas.attribute_schema_id) filter (where pas.attribute_status = 'active' and pas.tenant_id is not null) as tenant_override_attribute_count,
  count(distinct pejp.join_profile_id) filter (where pejp.profile_status = 'active') as active_join_profile_count,
  peer.created_at,
  peer.updated_at
from public.platform_extensible_entity_registry peer
left join public.platform_extensible_attribute_schema pas
  on pas.entity_id = peer.entity_id
left join public.platform_extensible_join_profile pejp
  on pejp.entity_id = peer.entity_id
group by
  peer.entity_id,
  peer.entity_code,
  peer.entity_label,
  peer.owner_module_code,
  peer.target_relation_schema,
  peer.target_relation_name,
  peer.primary_key_column,
  peer.tenant_scope,
  peer.allow_tenant_override,
  peer.join_profile_enabled,
  peer.entity_status,
  peer.created_at,
  peer.updated_at;

create or replace view public.platform_rm_extensible_attribute_catalog
with (security_invoker = true)
as
select
  pas.attribute_schema_id,
  peer.entity_code,
  peer.owner_module_code,
  pas.tenant_id,
  pas.attribute_code,
  pas.ui_label,
  pas.data_type,
  pas.is_required,
  pas.default_value,
  pas.validation_rules,
  pas.sort_order,
  pas.attribute_status,
  pas.metadata,
  pas.created_at,
  pas.updated_at
from public.platform_extensible_attribute_schema pas
join public.platform_extensible_entity_registry peer
  on peer.entity_id = pas.entity_id;;
