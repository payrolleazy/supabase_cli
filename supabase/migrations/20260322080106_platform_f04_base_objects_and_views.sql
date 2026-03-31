create table if not exists public.platform_async_worker_registry (
  worker_code text primary key,
  module_code text not null,
  dispatch_mode text not null,
  handler_contract text not null,
  is_active boolean not null default true,
  max_batch_size integer not null default 50,
  default_lease_seconds integer not null default 120,
  heartbeat_grace_seconds integer not null default 180,
  retry_backoff_policy jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  created_by uuid,
  constraint platform_async_worker_registry_worker_code_check
    check (btrim(worker_code) <> ''),
  constraint platform_async_worker_registry_module_code_check
    check (btrim(module_code) <> ''),
  constraint platform_async_worker_registry_dispatch_mode_check
    check (dispatch_mode in ('edge_worker', 'db_inline_handler')),
  constraint platform_async_worker_registry_handler_contract_check
    check (btrim(handler_contract) <> ''),
  constraint platform_async_worker_registry_max_batch_size_check
    check (max_batch_size > 0 and max_batch_size <= 500),
  constraint platform_async_worker_registry_default_lease_seconds_check
    check (default_lease_seconds > 0),
  constraint platform_async_worker_registry_heartbeat_grace_seconds_check
    check (heartbeat_grace_seconds >= default_lease_seconds),
  constraint platform_async_worker_registry_retry_backoff_policy_check
    check (jsonb_typeof(retry_backoff_policy) = 'object'),
  constraint platform_async_worker_registry_metadata_check
    check (jsonb_typeof(metadata) = 'object')
);

drop trigger if exists trg_platform_async_worker_registry_set_updated_at on public.platform_async_worker_registry;
create trigger trg_platform_async_worker_registry_set_updated_at
before update on public.platform_async_worker_registry
for each row
execute function public.platform_set_updated_at();

alter table public.platform_async_worker_registry enable row level security;

create table if not exists public.platform_async_job (
  job_id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  tenant_schema text not null,
  module_code text not null,
  worker_code text not null references public.platform_async_worker_registry(worker_code),
  job_type text not null,
  job_state text not null,
  dispatch_mode text not null,
  priority integer not null default 100,
  payload jsonb not null default '{}'::jsonb,
  idempotency_key text,
  deduplication_key text,
  available_at timestamptz not null default timezone('utc', now()),
  claimed_at timestamptz,
  lease_expires_at timestamptz,
  heartbeat_at timestamptz,
  claimed_by_worker text,
  attempt_count integer not null default 0,
  max_attempts integer not null default 10,
  next_retry_at timestamptz,
  last_error_code text,
  last_error_message text,
  last_error_details jsonb,
  result_summary jsonb not null default '{}'::jsonb,
  origin_source text not null,
  created_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  completed_at timestamptz,
  dead_lettered_at timestamptz,
  cancelled_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  constraint platform_async_job_tenant_schema_check
    check (btrim(tenant_schema) <> ''),
  constraint platform_async_job_module_code_check
    check (btrim(module_code) <> ''),
  constraint platform_async_job_job_type_check
    check (btrim(job_type) <> ''),
  constraint platform_async_job_job_state_check
    check (job_state in ('queued', 'claimed', 'running', 'retry_wait', 'completed', 'failed_terminal', 'dead_lettered', 'cancelled')),
  constraint platform_async_job_dispatch_mode_check
    check (dispatch_mode in ('edge_worker', 'db_inline_handler')),
  constraint platform_async_job_payload_check
    check (jsonb_typeof(payload) = 'object'),
  constraint platform_async_job_attempt_count_check
    check (attempt_count >= 0),
  constraint platform_async_job_max_attempts_check
    check (max_attempts > 0),
  constraint platform_async_job_last_error_details_check
    check (last_error_details is null or jsonb_typeof(last_error_details) = 'object'),
  constraint platform_async_job_result_summary_check
    check (jsonb_typeof(result_summary) = 'object'),
  constraint platform_async_job_origin_source_check
    check (btrim(origin_source) <> ''),
  constraint platform_async_job_metadata_check
    check (jsonb_typeof(metadata) = 'object')
);

create index if not exists idx_platform_async_job_due
  on public.platform_async_job (job_state, worker_code, priority, available_at, next_retry_at, created_at)
  where job_state in ('queued', 'retry_wait');

create index if not exists idx_platform_async_job_tenant_module_state
  on public.platform_async_job (tenant_id, module_code, job_state, created_at);

create index if not exists idx_platform_async_job_worker_state
  on public.platform_async_job (worker_code, job_state, created_at);

create unique index if not exists uq_platform_async_job_idempotency
  on public.platform_async_job (tenant_id, worker_code, idempotency_key)
  where idempotency_key is not null;

create unique index if not exists uq_platform_async_job_active_dedup
  on public.platform_async_job (tenant_id, worker_code, deduplication_key)
  where deduplication_key is not null
    and job_state in ('queued', 'claimed', 'running', 'retry_wait');

drop trigger if exists trg_platform_async_job_set_updated_at on public.platform_async_job;
create trigger trg_platform_async_job_set_updated_at
before update on public.platform_async_job
for each row
execute function public.platform_set_updated_at();

alter table public.platform_async_job enable row level security;

create table if not exists public.platform_async_job_attempt (
  attempt_id bigint generated by default as identity primary key,
  job_id uuid not null references public.platform_async_job(job_id) on delete cascade,
  attempt_number integer not null,
  worker_code text,
  started_at timestamptz not null,
  completed_at timestamptz,
  attempt_state text not null,
  error_code text,
  error_message text,
  error_details jsonb,
  result_summary jsonb,
  duration_ms integer,
  created_at timestamptz not null default timezone('utc', now()),
  constraint platform_async_job_attempt_attempt_number_check
    check (attempt_number > 0),
  constraint platform_async_job_attempt_attempt_state_check
    check (attempt_state in ('started', 'succeeded', 'failed_retryable', 'failed_terminal', 'cancelled')),
  constraint platform_async_job_attempt_error_details_check
    check (error_details is null or jsonb_typeof(error_details) = 'object'),
  constraint platform_async_job_attempt_result_summary_check
    check (result_summary is null or jsonb_typeof(result_summary) = 'object'),
  constraint platform_async_job_attempt_duration_ms_check
    check (duration_ms is null or duration_ms >= 0)
);

create unique index if not exists uq_platform_async_job_attempt_job_attempt
  on public.platform_async_job_attempt (job_id, attempt_number);

create index if not exists idx_platform_async_job_attempt_started_at
  on public.platform_async_job_attempt (started_at desc);

alter table public.platform_async_job_attempt enable row level security;

create or replace view public.platform_async_dispatch_readiness_view as
with due_jobs as (
  select
    paj.worker_code,
    paj.module_code,
    paj.dispatch_mode,
    paj.tenant_id,
    paj.priority,
    case
      when paj.job_state = 'queued' then paj.available_at
      else coalesce(paj.next_retry_at, paj.available_at)
    end as due_at
  from public.platform_async_job paj
  join public.platform_tenant_registry_view ptrv
    on ptrv.tenant_id = paj.tenant_id
  join public.platform_async_worker_registry pawr
    on pawr.worker_code = paj.worker_code
  where paj.job_state in ('queued', 'retry_wait')
    and ptrv.ready_for_routing = true
    and ptrv.background_processing_allowed = true
    and pawr.is_active = true
    and (
      (paj.job_state = 'queued' and paj.available_at <= timezone('utc', now()))
      or
      (paj.job_state = 'retry_wait' and coalesce(paj.next_retry_at, paj.available_at) <= timezone('utc', now()))
    )
)
select
  worker_code,
  module_code,
  dispatch_mode,
  count(*) as due_job_count,
  min(due_at) as oldest_due_at,
  min(priority) as highest_priority
from due_jobs
group by worker_code, module_code, dispatch_mode;

create or replace view public.platform_async_stale_lease_view as
select
  paj.job_id,
  paj.tenant_id,
  pt.tenant_code,
  paj.tenant_schema,
  paj.module_code,
  paj.worker_code,
  paj.job_type,
  paj.job_state,
  paj.claimed_at,
  paj.lease_expires_at,
  paj.heartbeat_at,
  paj.attempt_count,
  paj.max_attempts,
  paj.claimed_by_worker,
  paj.last_error_code,
  paj.last_error_message
from public.platform_async_job paj
join public.platform_tenant pt on pt.tenant_id = paj.tenant_id
where paj.job_state in ('claimed', 'running')
  and paj.lease_expires_at is not null
  and paj.lease_expires_at < timezone('utc', now());

create or replace view public.platform_async_dead_letter_view as
select
  paj.job_id,
  paj.tenant_id,
  pt.tenant_code,
  paj.tenant_schema,
  paj.module_code,
  paj.worker_code,
  paj.job_type,
  paj.attempt_count,
  paj.max_attempts,
  paj.last_error_code,
  paj.last_error_message,
  paj.dead_lettered_at,
  paj.updated_at
from public.platform_async_job paj
join public.platform_tenant pt on pt.tenant_id = paj.tenant_id
where paj.job_state = 'dead_lettered';

create or replace view public.platform_async_queue_health_view as
select
  paj.tenant_id,
  pt.tenant_code,
  paj.tenant_schema,
  paj.module_code,
  paj.worker_code,
  count(*) filter (where paj.job_state = 'queued') as queued_count,
  count(*) filter (where paj.job_state in ('claimed', 'running')) as running_count,
  count(*) filter (where paj.job_state = 'retry_wait') as retry_wait_count,
  count(*) filter (where paj.job_state = 'dead_lettered') as dead_letter_count,
  count(*) filter (
    where paj.job_state in ('claimed', 'running')
      and paj.lease_expires_at is not null
      and paj.lease_expires_at < timezone('utc', now())
  ) as stale_lease_count,
  min(
    case
      when paj.job_state = 'queued' then paj.available_at
      when paj.job_state = 'retry_wait' then coalesce(paj.next_retry_at, paj.available_at)
      else null
    end
  ) as oldest_due_at,
  max(paj.completed_at) as last_completed_at
from public.platform_async_job paj
join public.platform_tenant pt on pt.tenant_id = paj.tenant_id
group by paj.tenant_id, pt.tenant_code, paj.tenant_schema, paj.module_code, paj.worker_code;

create or replace function public.platform_async_calculate_next_retry_at(
  p_attempt_count integer,
  p_retry_backoff_policy jsonb default '{}'::jsonb
)
returns timestamptz
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_base_seconds integer := greatest(coalesce((p_retry_backoff_policy->>'base_seconds')::integer, 60), 1);
  v_multiplier numeric := greatest(coalesce((p_retry_backoff_policy->>'multiplier')::numeric, 2), 1);
  v_max_seconds integer := greatest(coalesce((p_retry_backoff_policy->>'max_seconds')::integer, 3600), v_base_seconds);
  v_delay_seconds numeric;
begin
  v_delay_seconds := least(
    v_max_seconds::numeric,
    v_base_seconds::numeric * power(v_multiplier, greatest(coalesce(p_attempt_count, 1) - 1, 0))
  );
  return timezone('utc', now()) + make_interval(secs => ceil(v_delay_seconds)::integer);
end;
$function$;;
