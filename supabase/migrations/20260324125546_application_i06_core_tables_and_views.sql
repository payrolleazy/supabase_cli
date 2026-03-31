create table if not exists public.platform_exchange_contract (
  contract_id uuid primary key default gen_random_uuid(),
  contract_code text not null unique,
  direction text not null,
  contract_label text not null,
  owner_module_code text not null,
  entity_id uuid not null references public.platform_extensible_entity_registry(entity_id) on delete restrict,
  worker_code text not null references public.platform_async_worker_registry(worker_code) on delete restrict,
  source_operation_code text null,
  target_operation_code text null,
  join_profile_code text null,
  template_mode text not null default 'i04_descriptor',
  accepted_file_formats text[] not null default '{}'::text[],
  allowed_role_codes text[] not null default '{}'::text[],
  upload_document_class_code text null references public.platform_document_class(document_class_code) on delete restrict,
  artifact_document_class_code text null references public.platform_document_class(document_class_code) on delete restrict,
  artifact_bucket_code text null references public.platform_storage_bucket_catalog(bucket_code) on delete restrict,
  validation_profile jsonb not null default '{}'::jsonb,
  delivery_profile jsonb not null default '{}'::jsonb,
  contract_status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_exchange_contract_code_check check (contract_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_exchange_contract_direction_check check (direction in ('import', 'export')),
  constraint platform_exchange_contract_owner_module_code_check check (owner_module_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_exchange_contract_source_operation_code_check check (source_operation_code is null or source_operation_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_exchange_contract_target_operation_code_check check (target_operation_code is null or target_operation_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_exchange_contract_join_profile_code_check check (join_profile_code is null or join_profile_code ~ '^[a-z][a-z0-9_]*$'),
  constraint platform_exchange_contract_template_mode_check check (template_mode in ('i04_descriptor', 'custom_columns')),
  constraint platform_exchange_contract_status_check check (contract_status in ('active', 'inactive')),
  constraint platform_exchange_contract_validation_profile_check check (jsonb_typeof(validation_profile) = 'object'),
  constraint platform_exchange_contract_delivery_profile_check check (jsonb_typeof(delivery_profile) = 'object'),
  constraint platform_exchange_contract_metadata_check check (jsonb_typeof(metadata) = 'object')
);

create index if not exists idx_platform_exchange_contract_owner_status
on public.platform_exchange_contract (owner_module_code, contract_status, direction);

create index if not exists idx_platform_exchange_contract_entity_status
on public.platform_exchange_contract (entity_id, contract_status);

create index if not exists idx_platform_exchange_contract_worker_code
on public.platform_exchange_contract (worker_code);

create index if not exists idx_platform_exchange_contract_upload_document_class_code
on public.platform_exchange_contract (upload_document_class_code)
where upload_document_class_code is not null;

create index if not exists idx_platform_exchange_contract_artifact_document_class_code
on public.platform_exchange_contract (artifact_document_class_code)
where artifact_document_class_code is not null;

create index if not exists idx_platform_exchange_contract_artifact_bucket_code
on public.platform_exchange_contract (artifact_bucket_code)
where artifact_bucket_code is not null;

alter table public.platform_exchange_contract enable row level security;

drop policy if exists platform_exchange_contract_service_role_all on public.platform_exchange_contract;
create policy platform_exchange_contract_service_role_all
on public.platform_exchange_contract
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_exchange_contract_set_updated_at on public.platform_exchange_contract;
create trigger trg_platform_exchange_contract_set_updated_at
before update on public.platform_exchange_contract
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_import_session (
  import_session_id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.platform_exchange_contract(contract_id) on delete restrict,
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  requested_by_actor_user_id uuid not null,
  upload_intent_id uuid null unique references public.platform_document_upload_intent(upload_intent_id) on delete set null,
  source_document_id uuid null unique references public.platform_document_record(document_id) on delete set null,
  idempotency_key text null,
  source_file_name text not null,
  content_type text not null,
  expected_size_bytes bigint null,
  session_status text not null default 'pending_upload',
  preview_summary jsonb not null default '{}'::jsonb,
  validation_summary jsonb not null default '{}'::jsonb,
  staging_row_count integer not null default 0,
  ready_row_count integer not null default 0,
  invalid_row_count integer not null default 0,
  duplicate_row_count integer not null default 0,
  commit_requested_at timestamptz null,
  committed_at timestamptz null,
  expires_at timestamptz not null default (timezone('utc', now()) + interval '1 day'),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_import_session_idempotency_key_check check (idempotency_key is null or length(btrim(idempotency_key)) > 0),
  constraint platform_import_session_expected_size_check check (expected_size_bytes is null or expected_size_bytes > 0),
  constraint platform_import_session_status_check check (session_status in ('pending_upload', 'uploaded', 'preview_ready', 'ready_to_commit', 'committing', 'committed', 'failed', 'cancelled', 'expired')),
  constraint platform_import_session_preview_summary_check check (jsonb_typeof(preview_summary) = 'object'),
  constraint platform_import_session_validation_summary_check check (jsonb_typeof(validation_summary) = 'object'),
  constraint platform_import_session_metadata_check check (jsonb_typeof(metadata) = 'object'),
  constraint platform_import_session_staging_row_count_check check (staging_row_count >= 0),
  constraint platform_import_session_ready_row_count_check check (ready_row_count >= 0),
  constraint platform_import_session_invalid_row_count_check check (invalid_row_count >= 0),
  constraint platform_import_session_duplicate_row_count_check check (duplicate_row_count >= 0)
);

create unique index if not exists ux_platform_import_session_idempotency
on public.platform_import_session (tenant_id, contract_id, requested_by_actor_user_id, idempotency_key)
where idempotency_key is not null;

create index if not exists idx_platform_import_session_tenant_status
on public.platform_import_session (tenant_id, session_status, created_at desc);

create index if not exists idx_platform_import_session_contract_id
on public.platform_import_session (contract_id, created_at desc);

create index if not exists idx_platform_import_session_requested_by_actor
on public.platform_import_session (requested_by_actor_user_id, created_at desc);

create index if not exists idx_platform_import_session_tenant_id
on public.platform_import_session (tenant_id);

alter table public.platform_import_session enable row level security;

drop policy if exists platform_import_session_service_role_all on public.platform_import_session;
create policy platform_import_session_service_role_all
on public.platform_import_session
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_import_session_set_updated_at on public.platform_import_session;
create trigger trg_platform_import_session_set_updated_at
before update on public.platform_import_session
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_import_staging_row (
  staging_row_id bigint generated by default as identity primary key,
  import_session_id uuid not null references public.platform_import_session(import_session_id) on delete cascade,
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  source_row_number integer not null,
  raw_row jsonb not null,
  canonical_row jsonb not null default '{}'::jsonb,
  validation_status text not null default 'pending',
  validation_messages jsonb not null default '[]'::jsonb,
  duplicate_key text null,
  commit_result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_import_staging_row_source_row_number_check check (source_row_number > 0),
  constraint platform_import_staging_row_validation_status_check check (validation_status in ('pending', 'ready', 'invalid', 'duplicate', 'committed', 'failed')),
  constraint platform_import_staging_row_raw_row_check check (jsonb_typeof(raw_row) = 'object'),
  constraint platform_import_staging_row_canonical_row_check check (jsonb_typeof(canonical_row) = 'object'),
  constraint platform_import_staging_row_validation_messages_check check (jsonb_typeof(validation_messages) = 'array'),
  constraint platform_import_staging_row_commit_result_check check (jsonb_typeof(commit_result) = 'object'),
  constraint platform_import_staging_row_session_row_key unique (import_session_id, source_row_number)
);

create index if not exists idx_platform_import_staging_row_session_status
on public.platform_import_staging_row (import_session_id, validation_status, source_row_number);

create index if not exists idx_platform_import_staging_row_tenant_status
on public.platform_import_staging_row (tenant_id, validation_status, created_at desc);

create index if not exists idx_platform_import_staging_row_tenant_id
on public.platform_import_staging_row (tenant_id);

alter table public.platform_import_staging_row enable row level security;

drop policy if exists platform_import_staging_row_service_role_all on public.platform_import_staging_row;
create policy platform_import_staging_row_service_role_all
on public.platform_import_staging_row
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_import_staging_row_set_updated_at on public.platform_import_staging_row;
create trigger trg_platform_import_staging_row_set_updated_at
before update on public.platform_import_staging_row
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_import_run (
  import_run_id uuid primary key default gen_random_uuid(),
  import_session_id uuid not null references public.platform_import_session(import_session_id) on delete cascade,
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  contract_id uuid not null references public.platform_exchange_contract(contract_id) on delete restrict,
  run_no integer not null default 1,
  requested_by_actor_user_id uuid not null,
  job_id uuid null unique references public.platform_async_job(job_id) on delete set null,
  run_status text not null default 'queued',
  result_summary jsonb not null default '{}'::jsonb,
  diagnostics jsonb not null default '{}'::jsonb,
  requested_at timestamptz not null default timezone('utc', now()),
  started_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_import_run_run_no_check check (run_no > 0),
  constraint platform_import_run_status_check check (run_status in ('queued', 'running', 'completed', 'failed', 'cancelled')),
  constraint platform_import_run_result_summary_check check (jsonb_typeof(result_summary) = 'object'),
  constraint platform_import_run_diagnostics_check check (jsonb_typeof(diagnostics) = 'object'),
  constraint platform_import_run_session_run_key unique (import_session_id, run_no)
);

create index if not exists idx_platform_import_run_tenant_status
on public.platform_import_run (tenant_id, run_status, requested_at desc);

create index if not exists idx_platform_import_run_contract_status
on public.platform_import_run (contract_id, run_status, requested_at desc);

create index if not exists idx_platform_import_run_tenant_id
on public.platform_import_run (tenant_id);

alter table public.platform_import_run enable row level security;

drop policy if exists platform_import_run_service_role_all on public.platform_import_run;
create policy platform_import_run_service_role_all
on public.platform_import_run
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_import_run_set_updated_at on public.platform_import_run;
create trigger trg_platform_import_run_set_updated_at
before update on public.platform_import_run
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_import_validation_summary (
  validation_summary_id uuid primary key default gen_random_uuid(),
  import_session_id uuid not null unique references public.platform_import_session(import_session_id) on delete cascade,
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  total_rows integer not null default 0,
  ready_rows integer not null default 0,
  invalid_rows integer not null default 0,
  duplicate_rows integer not null default 0,
  committed_rows integer not null default 0,
  failed_rows integer not null default 0,
  summary_payload jsonb not null default '{}'::jsonb,
  generated_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_import_validation_summary_total_rows_check check (total_rows >= 0),
  constraint platform_import_validation_summary_ready_rows_check check (ready_rows >= 0),
  constraint platform_import_validation_summary_invalid_rows_check check (invalid_rows >= 0),
  constraint platform_import_validation_summary_duplicate_rows_check check (duplicate_rows >= 0),
  constraint platform_import_validation_summary_committed_rows_check check (committed_rows >= 0),
  constraint platform_import_validation_summary_failed_rows_check check (failed_rows >= 0),
  constraint platform_import_validation_summary_payload_check check (jsonb_typeof(summary_payload) = 'object')
);

create index if not exists idx_platform_import_validation_summary_tenant_id
on public.platform_import_validation_summary (tenant_id);

alter table public.platform_import_validation_summary enable row level security;

drop policy if exists platform_import_validation_summary_service_role_all on public.platform_import_validation_summary;
create policy platform_import_validation_summary_service_role_all
on public.platform_import_validation_summary
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_import_validation_summary_set_updated_at on public.platform_import_validation_summary;
create trigger trg_platform_import_validation_summary_set_updated_at
before update on public.platform_import_validation_summary
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_export_policy (
  export_policy_id uuid primary key default gen_random_uuid(),
  contract_id uuid not null unique references public.platform_exchange_contract(contract_id) on delete cascade,
  default_retention_days integer not null default 7,
  max_jobs_per_tenant_per_day integer null,
  max_active_jobs_per_tenant integer null,
  cleanup_enabled boolean not null default true,
  policy_status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_export_policy_default_retention_days_check check (default_retention_days > 0),
  constraint platform_export_policy_max_jobs_per_tenant_per_day_check check (max_jobs_per_tenant_per_day is null or max_jobs_per_tenant_per_day > 0),
  constraint platform_export_policy_max_active_jobs_per_tenant_check check (max_active_jobs_per_tenant is null or max_active_jobs_per_tenant > 0),
  constraint platform_export_policy_status_check check (policy_status in ('active', 'inactive')),
  constraint platform_export_policy_metadata_check check (jsonb_typeof(metadata) = 'object')
);

create index if not exists idx_platform_export_policy_status
on public.platform_export_policy (policy_status);

alter table public.platform_export_policy enable row level security;

drop policy if exists platform_export_policy_service_role_all on public.platform_export_policy;
create policy platform_export_policy_service_role_all
on public.platform_export_policy
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_export_policy_set_updated_at on public.platform_export_policy;
create trigger trg_platform_export_policy_set_updated_at
before update on public.platform_export_policy
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_export_job (
  export_job_id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  contract_id uuid not null references public.platform_exchange_contract(contract_id) on delete restrict,
  requested_by_actor_user_id uuid not null,
  job_id uuid null unique references public.platform_async_job(job_id) on delete set null,
  artifact_document_id uuid null unique references public.platform_document_record(document_id) on delete set null,
  idempotency_key text null,
  deduplication_key text null,
  request_payload jsonb not null default '{}'::jsonb,
  job_status text not null default 'queued',
  progress_percent integer not null default 0,
  result_summary jsonb not null default '{}'::jsonb,
  error_details jsonb not null default '{}'::jsonb,
  queued_at timestamptz not null default timezone('utc', now()),
  started_at timestamptz null,
  completed_at timestamptz null,
  expires_at timestamptz null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_export_job_idempotency_key_check check (idempotency_key is null or length(btrim(idempotency_key)) > 0),
  constraint platform_export_job_deduplication_key_check check (deduplication_key is null or length(btrim(deduplication_key)) > 0),
  constraint platform_export_job_request_payload_check check (jsonb_typeof(request_payload) = 'object'),
  constraint platform_export_job_status_check check (job_status in ('queued', 'running', 'completed', 'failed', 'expired', 'cancelled')),
  constraint platform_export_job_progress_percent_check check (progress_percent between 0 and 100),
  constraint platform_export_job_result_summary_check check (jsonb_typeof(result_summary) = 'object'),
  constraint platform_export_job_error_details_check check (jsonb_typeof(error_details) = 'object')
);

create unique index if not exists ux_platform_export_job_idempotency
on public.platform_export_job (tenant_id, contract_id, idempotency_key)
where idempotency_key is not null;

create index if not exists idx_platform_export_job_tenant_status
on public.platform_export_job (tenant_id, job_status, queued_at desc);

create index if not exists idx_platform_export_job_contract_status
on public.platform_export_job (contract_id, job_status, queued_at desc);

create index if not exists idx_platform_export_job_requested_by_actor
on public.platform_export_job (requested_by_actor_user_id, queued_at desc);

create index if not exists idx_platform_export_job_tenant_id
on public.platform_export_job (tenant_id);

alter table public.platform_export_job enable row level security;

drop policy if exists platform_export_job_service_role_all on public.platform_export_job;
create policy platform_export_job_service_role_all
on public.platform_export_job
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_export_job_set_updated_at on public.platform_export_job;
create trigger trg_platform_export_job_set_updated_at
before update on public.platform_export_job
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_export_artifact (
  export_artifact_id uuid primary key default gen_random_uuid(),
  export_job_id uuid not null unique references public.platform_export_job(export_job_id) on delete cascade,
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  contract_id uuid not null references public.platform_exchange_contract(contract_id) on delete restrict,
  document_id uuid null unique references public.platform_document_record(document_id) on delete set null,
  bucket_code text not null references public.platform_storage_bucket_catalog(bucket_code) on delete restrict,
  storage_object_name text not null,
  file_name text not null,
  content_type text not null,
  file_size_bytes bigint null,
  checksum_sha256 text null,
  retention_expires_at timestamptz null,
  artifact_status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_export_artifact_storage_object_name_check check (length(btrim(storage_object_name)) > 0),
  constraint platform_export_artifact_file_size_check check (file_size_bytes is null or file_size_bytes > 0),
  constraint platform_export_artifact_checksum_check check (checksum_sha256 is null or checksum_sha256 ~ '^[A-Fa-f0-9]{64}$'),
  constraint platform_export_artifact_status_check check (artifact_status in ('active', 'expired', 'deleted')),
  constraint platform_export_artifact_metadata_check check (jsonb_typeof(metadata) = 'object'),
  constraint platform_export_artifact_bucket_object_key unique (bucket_code, storage_object_name)
);

create index if not exists idx_platform_export_artifact_tenant_status
on public.platform_export_artifact (tenant_id, artifact_status, created_at desc);

create index if not exists idx_platform_export_artifact_contract_id
on public.platform_export_artifact (contract_id, created_at desc);

create index if not exists idx_platform_export_artifact_tenant_id
on public.platform_export_artifact (tenant_id);

alter table public.platform_export_artifact enable row level security;

drop policy if exists platform_export_artifact_service_role_all on public.platform_export_artifact;
create policy platform_export_artifact_service_role_all
on public.platform_export_artifact
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_export_artifact_set_updated_at on public.platform_export_artifact;
create trigger trg_platform_export_artifact_set_updated_at
before update on public.platform_export_artifact
for each row execute function public.platform_set_updated_at();

create table if not exists public.platform_export_event_log (
  event_id bigint generated by default as identity primary key,
  export_job_id uuid null references public.platform_export_job(export_job_id) on delete set null,
  contract_id uuid null references public.platform_exchange_contract(contract_id) on delete set null,
  tenant_id uuid null references public.platform_tenant(tenant_id) on delete set null,
  actor_user_id uuid null,
  event_type text not null,
  severity text not null default 'info',
  message text not null,
  details jsonb not null default '{}'::jsonb,
  event_timestamp timestamptz not null default timezone('utc', now()),
  constraint platform_export_event_log_severity_check check (severity in ('info', 'warning', 'error')),
  constraint platform_export_event_log_details_check check (jsonb_typeof(details) = 'object')
);

create index if not exists idx_platform_export_event_log_tenant_time
on public.platform_export_event_log (tenant_id, event_timestamp desc);

create index if not exists idx_platform_export_event_log_job_time
on public.platform_export_event_log (export_job_id, event_timestamp desc);

create index if not exists idx_platform_export_event_log_contract_time
on public.platform_export_event_log (contract_id, event_timestamp desc);

alter table public.platform_export_event_log enable row level security;

drop policy if exists platform_export_event_log_service_role_all on public.platform_export_event_log;
create policy platform_export_event_log_service_role_all
on public.platform_export_event_log
for all
to service_role
using (true)
with check (true);

create or replace view public.platform_rm_exchange_contract_catalog
with (security_invoker = true)
as
select
  pec.contract_id,
  pec.contract_code,
  pec.direction,
  pec.contract_label,
  pec.owner_module_code,
  peer.entity_code,
  peer.entity_label,
  peer.target_relation_schema,
  peer.target_relation_name,
  pec.worker_code,
  pec.source_operation_code,
  pec.target_operation_code,
  pec.join_profile_code,
  pec.template_mode,
  pec.accepted_file_formats,
  pec.allowed_role_codes,
  pec.upload_document_class_code,
  pec.artifact_document_class_code,
  pec.artifact_bucket_code,
  pec.contract_status,
  pec.validation_profile,
  pec.delivery_profile,
  pec.metadata,
  pec.created_at,
  pec.updated_at
from public.platform_exchange_contract pec
join public.platform_extensible_entity_registry peer
  on peer.entity_id = pec.entity_id;

create or replace view public.platform_rm_import_session_overview
with (security_invoker = true)
as
select
  pis.import_session_id,
  pis.tenant_id,
  pec.contract_code,
  peer.entity_code,
  pis.requested_by_actor_user_id,
  pis.upload_intent_id,
  pis.source_document_id,
  pis.idempotency_key,
  pis.source_file_name,
  pis.content_type,
  pis.expected_size_bytes,
  pis.session_status,
  pis.staging_row_count,
  pis.ready_row_count,
  pis.invalid_row_count,
  pis.duplicate_row_count,
  pis.commit_requested_at,
  pis.committed_at,
  pivs.total_rows,
  pivs.committed_rows,
  pivs.failed_rows,
  pis.preview_summary,
  pis.validation_summary,
  pis.expires_at,
  pis.created_at,
  pis.updated_at
from public.platform_import_session pis
join public.platform_exchange_contract pec
  on pec.contract_id = pis.contract_id
join public.platform_extensible_entity_registry peer
  on peer.entity_id = pec.entity_id
left join public.platform_import_validation_summary pivs
  on pivs.import_session_id = pis.import_session_id;

create or replace view public.platform_rm_import_validation_summary
with (security_invoker = true)
as
select
  pivs.validation_summary_id,
  pivs.import_session_id,
  pivs.tenant_id,
  pec.contract_code,
  peer.entity_code,
  pivs.total_rows,
  pivs.ready_rows,
  pivs.invalid_rows,
  pivs.duplicate_rows,
  pivs.committed_rows,
  pivs.failed_rows,
  pivs.summary_payload,
  pivs.generated_at,
  pivs.updated_at
from public.platform_import_validation_summary pivs
join public.platform_import_session pis
  on pis.import_session_id = pivs.import_session_id
join public.platform_exchange_contract pec
  on pec.contract_id = pis.contract_id
join public.platform_extensible_entity_registry peer
  on peer.entity_id = pec.entity_id;

create or replace view public.platform_rm_export_job_overview
with (security_invoker = true)
as
select
  pej.export_job_id,
  pej.tenant_id,
  pec.contract_code,
  peer.entity_code,
  pej.requested_by_actor_user_id,
  pej.job_id,
  pej.idempotency_key,
  pej.deduplication_key,
  pej.artifact_document_id,
  pea.export_artifact_id,
  pea.bucket_code,
  pea.storage_object_name,
  pea.file_name,
  pea.content_type,
  pea.file_size_bytes,
  pea.retention_expires_at,
  pea.artifact_status,
  pej.job_status,
  pej.progress_percent,
  pej.result_summary,
  pej.error_details,
  pej.queued_at,
  pej.started_at,
  pej.completed_at,
  pej.expires_at,
  pej.created_at,
  pej.updated_at
from public.platform_export_job pej
join public.platform_exchange_contract pec
  on pec.contract_id = pej.contract_id
join public.platform_extensible_entity_registry peer
  on peer.entity_id = pec.entity_id
left join public.platform_export_artifact pea
  on pea.export_job_id = pej.export_job_id;

create or replace view public.platform_rm_export_queue_health
with (security_invoker = true)
as
select
  pec.contract_code,
  pej.job_status,
  count(*) as job_count,
  min(pej.queued_at) as oldest_queued_at,
  max(pej.updated_at) as newest_update_at
from public.platform_export_job pej
join public.platform_exchange_contract pec
  on pec.contract_id = pej.contract_id
group by pec.contract_code, pej.job_status;;
