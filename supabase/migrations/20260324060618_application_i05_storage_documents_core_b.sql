create table if not exists public.platform_document_record (
  document_id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  document_class_id uuid not null references public.platform_document_class(document_class_id) on delete restrict,
  bucket_code text not null references public.platform_storage_bucket_catalog(bucket_code) on delete restrict,
  upload_intent_id uuid null unique references public.platform_document_upload_intent(upload_intent_id) on delete set null,
  owner_actor_user_id uuid null,
  uploaded_by_actor_user_id uuid null,
  storage_object_name text not null,
  original_file_name text not null,
  content_type text not null,
  file_size_bytes bigint null,
  checksum_sha256 text null,
  protection_mode text not null,
  access_mode text not null,
  allowed_role_codes text[] not null default '{}'::text[],
  document_status text not null default 'active',
  version_no integer not null default 1,
  superseded_by_document_id uuid null references public.platform_document_record(document_id) on delete set null,
  expires_on date null,
  storage_metadata jsonb not null default '{}'::jsonb,
  document_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_document_record_file_size_check check (file_size_bytes is null or file_size_bytes > 0),
  constraint platform_document_record_checksum_check check (checksum_sha256 is null or checksum_sha256 ~ '^[A-Fa-f0-9]{64}$'),
  constraint platform_document_record_protection_mode_check check (protection_mode in ('signed_url', 'edge_stream', 'encrypted_edge_stream')),
  constraint platform_document_record_access_mode_check check (access_mode in ('owner_only', 'owner_and_admin', 'role_bound', 'tenant_membership', 'service_only')),
  constraint platform_document_record_document_status_check check (document_status in ('active', 'superseded', 'deleted')),
  constraint platform_document_record_version_no_check check (version_no > 0),
  constraint platform_document_record_storage_metadata_check check (jsonb_typeof(storage_metadata) = 'object'),
  constraint platform_document_record_document_metadata_check check (jsonb_typeof(document_metadata) = 'object'),
  constraint platform_document_record_bucket_object_key unique (bucket_code, storage_object_name)
);

create index if not exists idx_platform_document_record_tenant_status_class
on public.platform_document_record (tenant_id, document_status, document_class_id);

create index if not exists idx_platform_document_record_document_class_id
on public.platform_document_record (document_class_id);

create index if not exists idx_platform_document_record_owner_actor
on public.platform_document_record (owner_actor_user_id, document_status);

alter table public.platform_document_record enable row level security;

drop policy if exists platform_document_record_service_role_all on public.platform_document_record;
create policy platform_document_record_service_role_all
on public.platform_document_record
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_document_record_set_updated_at on public.platform_document_record;
create trigger trg_platform_document_record_set_updated_at
before update on public.platform_document_record
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_document_binding (
  binding_id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.platform_document_record(document_id) on delete cascade,
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  binding_status text not null default 'active',
  target_entity_code text not null,
  target_key text not null,
  relation_purpose text not null default 'attachment',
  bound_by_actor_user_id uuid null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_document_binding_binding_status_check check (binding_status in ('active', 'inactive')),
  constraint platform_document_binding_target_entity_code_check check (target_entity_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_document_binding_metadata_check check (jsonb_typeof(metadata) = 'object'),
  constraint platform_document_binding_document_target_key unique (document_id, target_entity_code, target_key, relation_purpose)
);

create index if not exists idx_platform_document_binding_tenant_target
on public.platform_document_binding (tenant_id, target_entity_code, target_key, binding_status);

create index if not exists idx_platform_document_binding_document_id
on public.platform_document_binding (document_id, binding_status);

alter table public.platform_document_binding enable row level security;

drop policy if exists platform_document_binding_service_role_all on public.platform_document_binding;
create policy platform_document_binding_service_role_all
on public.platform_document_binding
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_document_binding_set_updated_at on public.platform_document_binding;
create trigger trg_platform_document_binding_set_updated_at
before update on public.platform_document_binding
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_document_event_log (
  event_id bigint generated by default as identity primary key,
  event_type text not null,
  severity text not null default 'info',
  tenant_id uuid null references public.platform_tenant(tenant_id) on delete set null,
  document_id uuid null references public.platform_document_record(document_id) on delete set null,
  upload_intent_id uuid null references public.platform_document_upload_intent(upload_intent_id) on delete set null,
  actor_user_id uuid null,
  message text not null,
  details jsonb not null default '{}'::jsonb,
  event_timestamp timestamptz not null default timezone('utc', now()),
  constraint platform_document_event_log_severity_check check (severity in ('info', 'warning', 'error')),
  constraint platform_document_event_log_details_check check (jsonb_typeof(details) = 'object')
);

create index if not exists idx_platform_document_event_log_tenant_time
on public.platform_document_event_log (tenant_id, event_timestamp desc);

create index if not exists idx_platform_document_event_log_document_time
on public.platform_document_event_log (document_id, event_timestamp desc);

create index if not exists idx_platform_document_event_log_upload_intent_time
on public.platform_document_event_log (upload_intent_id, event_timestamp desc);

alter table public.platform_document_event_log enable row level security;

drop policy if exists platform_document_event_log_service_role_all on public.platform_document_event_log;
create policy platform_document_event_log_service_role_all
on public.platform_document_event_log
for all
to service_role
using (true)
with check (true);

create or replace view public.platform_rm_storage_bucket_catalog
with (security_invoker = true)
as
select
  psbc.bucket_code,
  psbc.bucket_name,
  psbc.bucket_purpose,
  psbc.bucket_visibility,
  psbc.protection_mode,
  psbc.file_size_limit_bytes,
  psbc.allowed_mime_types,
  psbc.retention_days,
  psbc.bucket_status,
  psbc.metadata,
  psbc.created_at,
  psbc.updated_at,
  (sb.id is not null) as storage_bucket_present,
  sb.public as storage_public_flag,
  sb.file_size_limit as storage_file_size_limit,
  sb.allowed_mime_types as storage_allowed_mime_types
from public.platform_storage_bucket_catalog psbc
left join storage.buckets sb
  on sb.id = psbc.bucket_name;

create or replace view public.platform_rm_document_catalog
with (security_invoker = true)
as
select
  pdr.document_id,
  pdr.tenant_id,
  pdc.document_class_code,
  pdc.class_label,
  pdc.owner_module_code,
  pdr.bucket_code,
  psbc.bucket_name,
  pdr.upload_intent_id,
  pdr.owner_actor_user_id,
  pdr.uploaded_by_actor_user_id,
  pdr.storage_object_name,
  pdr.original_file_name,
  pdr.content_type,
  pdr.file_size_bytes,
  pdr.checksum_sha256,
  pdr.protection_mode,
  pdr.access_mode,
  pdr.allowed_role_codes,
  pdr.document_status,
  pdr.version_no,
  pdr.expires_on,
  pdr.storage_metadata,
  pdr.document_metadata,
  pdr.created_at,
  pdr.updated_at
from public.platform_document_record pdr
join public.platform_document_class pdc
  on pdc.document_class_id = pdr.document_class_id
join public.platform_storage_bucket_catalog psbc
  on psbc.bucket_code = pdr.bucket_code;

create or replace view public.platform_rm_document_binding_catalog
with (security_invoker = true)
as
select
  pdb.binding_id,
  pdb.tenant_id,
  pdb.document_id,
  pdc.document_class_code,
  pdb.target_entity_code,
  pdb.target_key,
  pdb.relation_purpose,
  pdb.binding_status,
  pdb.bound_by_actor_user_id,
  pdb.metadata,
  pdb.created_at,
  pdb.updated_at
from public.platform_document_binding pdb
join public.platform_document_record pdr
  on pdr.document_id = pdb.document_id
join public.platform_document_class pdc
  on pdc.document_class_id = pdr.document_class_id;;
