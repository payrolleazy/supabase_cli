create or replace function public.platform_jsonb_text_array(p_value jsonb)
returns text[]
language sql
immutable
as $function$
  select
    case
      when p_value is null or p_value = 'null'::jsonb then '{}'::text[]
      when jsonb_typeof(p_value) <> 'array' then null::text[]
      else coalesce((
        select array_agg(btrim(v)) filter (where nullif(btrim(v), '') is not null)
        from jsonb_array_elements_text(p_value) as t(v)
      ), '{}'::text[])
    end;
$function$;

create or replace function public.platform_sanitize_storage_filename(p_file_name text)
returns text
language sql
immutable
as $function$
  select
    case
      when coalesce(nullif(btrim(p_file_name), ''), '') = '' then 'file.bin'
      else regexp_replace(
        regexp_replace(lower(btrim(p_file_name)), '[^a-z0-9._-]+', '_', 'g'),
        '_{2,}',
        '_',
        'g'
      )
    end;
$function$;

create or replace function public.platform_build_document_storage_object_name(
  p_tenant_id uuid,
  p_document_class_code text,
  p_owner_actor_user_id uuid,
  p_upload_intent_id uuid,
  p_original_file_name text
)
returns text
language sql
stable
as $function$
  select
    p_tenant_id::text || '/' ||
    lower(btrim(p_document_class_code)) || '/' ||
    coalesce(p_owner_actor_user_id::text, 'unowned') || '/' ||
    p_upload_intent_id::text || '/' ||
    public.platform_sanitize_storage_filename(p_original_file_name);
$function$;

create table if not exists public.platform_storage_bucket_catalog (
  bucket_code text primary key,
  bucket_name text not null unique,
  bucket_purpose text not null default 'document',
  bucket_visibility text not null default 'private',
  protection_mode text not null default 'signed_url',
  file_size_limit_bytes bigint null,
  allowed_mime_types text[] not null default '{}'::text[],
  retention_days integer null,
  bucket_status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_storage_bucket_catalog_bucket_code_check check (bucket_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_storage_bucket_catalog_bucket_name_check check (bucket_name ~ '^[a-z0-9][a-z0-9._-]*$'),
  constraint platform_storage_bucket_catalog_bucket_purpose_check check (bucket_purpose in ('document', 'template', 'temporary', 'artifact')),
  constraint platform_storage_bucket_catalog_bucket_visibility_check check (bucket_visibility in ('private', 'public')),
  constraint platform_storage_bucket_catalog_protection_mode_check check (protection_mode in ('signed_url', 'edge_stream', 'encrypted_edge_stream')),
  constraint platform_storage_bucket_catalog_file_size_limit_check check (file_size_limit_bytes is null or file_size_limit_bytes > 0),
  constraint platform_storage_bucket_catalog_retention_days_check check (retention_days is null or retention_days > 0),
  constraint platform_storage_bucket_catalog_bucket_status_check check (bucket_status in ('active', 'inactive')),
  constraint platform_storage_bucket_catalog_metadata_check check (jsonb_typeof(metadata) = 'object')
);

create index if not exists idx_platform_storage_bucket_catalog_purpose_status
on public.platform_storage_bucket_catalog (bucket_purpose, bucket_status);

alter table public.platform_storage_bucket_catalog enable row level security;

drop policy if exists platform_storage_bucket_catalog_service_role_all on public.platform_storage_bucket_catalog;
create policy platform_storage_bucket_catalog_service_role_all
on public.platform_storage_bucket_catalog
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_storage_bucket_catalog_set_updated_at on public.platform_storage_bucket_catalog;
create trigger trg_platform_storage_bucket_catalog_set_updated_at
before update on public.platform_storage_bucket_catalog
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_document_class (
  document_class_id uuid primary key default gen_random_uuid(),
  document_class_code text not null unique,
  class_label text not null,
  owner_module_code text not null,
  default_bucket_code text not null references public.platform_storage_bucket_catalog(bucket_code) on delete restrict,
  sensitivity_level text not null default 'normal',
  default_access_mode text not null default 'owner_only',
  default_allowed_role_codes text[] not null default '{}'::text[],
  default_protection_mode text not null default 'signed_url',
  max_file_size_bytes bigint null,
  allowed_mime_types text[] not null default '{}'::text[],
  allow_multiple_bindings boolean not null default true,
  application_encryption_required boolean not null default false,
  class_status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_document_class_code_check check (document_class_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_document_class_owner_module_code_check check (owner_module_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_document_class_sensitivity_level_check check (sensitivity_level in ('normal', 'sensitive', 'restricted')),
  constraint platform_document_class_default_access_mode_check check (default_access_mode in ('owner_only', 'owner_and_admin', 'role_bound', 'tenant_membership', 'service_only')),
  constraint platform_document_class_default_protection_mode_check check (default_protection_mode in ('signed_url', 'edge_stream', 'encrypted_edge_stream')),
  constraint platform_document_class_max_file_size_check check (max_file_size_bytes is null or max_file_size_bytes > 0),
  constraint platform_document_class_class_status_check check (class_status in ('active', 'inactive')),
  constraint platform_document_class_metadata_check check (jsonb_typeof(metadata) = 'object')
);

create index if not exists idx_platform_document_class_bucket_code
on public.platform_document_class (default_bucket_code);

create index if not exists idx_platform_document_class_module_status
on public.platform_document_class (owner_module_code, class_status);

alter table public.platform_document_class enable row level security;

drop policy if exists platform_document_class_service_role_all on public.platform_document_class;
create policy platform_document_class_service_role_all
on public.platform_document_class
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_document_class_set_updated_at on public.platform_document_class;
create trigger trg_platform_document_class_set_updated_at
before update on public.platform_document_class
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_document_upload_intent (
  upload_intent_id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  document_class_id uuid not null references public.platform_document_class(document_class_id) on delete restrict,
  bucket_code text not null references public.platform_storage_bucket_catalog(bucket_code) on delete restrict,
  requested_by_actor_user_id uuid null,
  owner_actor_user_id uuid null,
  binding_target_entity_code text null,
  binding_target_key text null,
  binding_relation_purpose text null,
  original_file_name text not null,
  sanitized_file_name text not null,
  content_type text not null,
  expected_size_bytes bigint null,
  storage_object_name text not null,
  upload_status text not null default 'pending',
  protection_mode text not null,
  access_mode text not null,
  allowed_role_codes text[] not null default '{}'::text[],
  intent_expires_at timestamptz not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_document_upload_intent_binding_target_check check (
    (binding_target_entity_code is null and binding_target_key is null)
    or (binding_target_entity_code is not null and binding_target_key is not null)
  ),
  constraint platform_document_upload_intent_entity_code_check check (binding_target_entity_code is null or binding_target_entity_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_document_upload_intent_expected_size_check check (expected_size_bytes is null or expected_size_bytes > 0),
  constraint platform_document_upload_intent_upload_status_check check (upload_status in ('pending', 'completed', 'expired', 'cancelled')),
  constraint platform_document_upload_intent_protection_mode_check check (protection_mode in ('signed_url', 'edge_stream', 'encrypted_edge_stream')),
  constraint platform_document_upload_intent_access_mode_check check (access_mode in ('owner_only', 'owner_and_admin', 'role_bound', 'tenant_membership', 'service_only')),
  constraint platform_document_upload_intent_storage_object_name_check check (length(btrim(storage_object_name)) > 0),
  constraint platform_document_upload_intent_metadata_check check (jsonb_typeof(metadata) = 'object'),
  constraint platform_document_upload_intent_bucket_object_key unique (bucket_code, storage_object_name)
);

create index if not exists idx_platform_document_upload_intent_tenant_status_expiry
on public.platform_document_upload_intent (tenant_id, upload_status, intent_expires_at);

create index if not exists idx_platform_document_upload_intent_document_class_id
on public.platform_document_upload_intent (document_class_id);

alter table public.platform_document_upload_intent enable row level security;

drop policy if exists platform_document_upload_intent_service_role_all on public.platform_document_upload_intent;
create policy platform_document_upload_intent_service_role_all
on public.platform_document_upload_intent
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_document_upload_intent_set_updated_at on public.platform_document_upload_intent;
create trigger trg_platform_document_upload_intent_set_updated_at
before update on public.platform_document_upload_intent
for each row execute function public.platform_set_updated_at();;
