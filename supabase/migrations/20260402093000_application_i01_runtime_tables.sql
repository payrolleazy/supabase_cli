create table if not exists public.platform_signup_circuit_breaker (
  breaker_code text primary key,
  breaker_state text not null default 'closed' check (breaker_state in ('closed', 'open', 'half_open')),
  failure_count integer not null default 0 check (failure_count >= 0),
  success_count integer not null default 0 check (success_count >= 0),
  error_threshold integer not null default 5 check (error_threshold > 0),
  success_threshold integer not null default 2 check (success_threshold > 0),
  cooldown_seconds integer not null default 300 check (cooldown_seconds > 0),
  last_error_code text null,
  last_error_message text null,
  last_failure_at timestamptz null,
  last_success_at timestamptz null,
  last_opened_at timestamptz null,
  last_state_changed_at timestamptz not null default timezone('utc', now()),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_signup_circuit_breaker_metadata_check check (jsonb_typeof(metadata) = 'object')
);

drop trigger if exists trg_platform_signup_circuit_breaker_set_updated_at on public.platform_signup_circuit_breaker;
create trigger trg_platform_signup_circuit_breaker_set_updated_at
before update on public.platform_signup_circuit_breaker
for each row
execute function public.platform_set_updated_at();

alter table public.platform_signup_circuit_breaker enable row level security;
drop policy if exists platform_signup_circuit_breaker_service_role_all on public.platform_signup_circuit_breaker;
create policy platform_signup_circuit_breaker_service_role_all
on public.platform_signup_circuit_breaker
for all
to service_role
using (true)
with check (true);

insert into public.platform_signup_circuit_breaker (
  breaker_code,
  breaker_state,
  failure_count,
  success_count,
  error_threshold,
  success_threshold,
  cooldown_seconds,
  metadata
)
values (
  'primary',
  'closed',
  0,
  0,
  5,
  2,
  300,
  jsonb_build_object('module_code', 'I01', 'managed_by', 'i01_signup_runtime')
)
on conflict (breaker_code) do update
set updated_at = timezone('utc', now());

create table if not exists public.platform_signup_autoscale_config (
  config_code text primary key,
  config_status text not null default 'active' check (config_status in ('active', 'disabled')),
  autoscale_enabled boolean not null default true,
  min_parallel_invocations integer not null default 1 check (min_parallel_invocations > 0),
  max_parallel_invocations integer not null default 3 check (max_parallel_invocations >= min_parallel_invocations),
  scale_up_threshold integer not null default 10 check (scale_up_threshold >= 0),
  scale_down_threshold integer not null default 0 check (scale_down_threshold >= 0),
  default_batch_size integer not null default 5 check (default_batch_size > 0),
  max_batch_size integer not null default 10 check (max_batch_size >= default_batch_size),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_signup_autoscale_config_metadata_check check (jsonb_typeof(metadata) = 'object')
);

drop trigger if exists trg_platform_signup_autoscale_config_set_updated_at on public.platform_signup_autoscale_config;
create trigger trg_platform_signup_autoscale_config_set_updated_at
before update on public.platform_signup_autoscale_config
for each row
execute function public.platform_set_updated_at();

alter table public.platform_signup_autoscale_config enable row level security;
drop policy if exists platform_signup_autoscale_config_service_role_all on public.platform_signup_autoscale_config;
create policy platform_signup_autoscale_config_service_role_all
on public.platform_signup_autoscale_config
for all
to service_role
using (true)
with check (true);

insert into public.platform_signup_autoscale_config (
  config_code,
  config_status,
  autoscale_enabled,
  min_parallel_invocations,
  max_parallel_invocations,
  scale_up_threshold,
  scale_down_threshold,
  default_batch_size,
  max_batch_size,
  metadata
)
values (
  'primary',
  'active',
  true,
  1,
  3,
  10,
  0,
  5,
  10,
  jsonb_build_object('module_code', 'I01', 'managed_by', 'i01_signup_runtime')
)
on conflict (config_code) do update
set updated_at = timezone('utc', now());

create table if not exists public.platform_signup_metrics (
  metric_id bigint generated always as identity primary key,
  captured_at timestamptz not null default timezone('utc', now()),
  queue_depth integer not null default 0 check (queue_depth >= 0),
  retry_wait_depth integer not null default 0 check (retry_wait_depth >= 0),
  running_depth integer not null default 0 check (running_depth >= 0),
  dead_letter_depth integer not null default 0 check (dead_letter_depth >= 0),
  stale_lease_depth integer not null default 0 check (stale_lease_depth >= 0),
  oldest_due_at timestamptz null,
  parallel_invocation_target integer not null default 1 check (parallel_invocation_target > 0),
  configured_batch_size integer not null default 1 check (configured_batch_size > 0),
  breaker_state text not null default 'closed' check (breaker_state in ('closed', 'open', 'half_open')),
  worker_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  constraint platform_signup_metrics_metadata_check check (jsonb_typeof(metadata) = 'object')
);

create index if not exists idx_platform_signup_metrics_captured_at
on public.platform_signup_metrics (captured_at desc);

alter table public.platform_signup_metrics enable row level security;
drop policy if exists platform_signup_metrics_service_role_all on public.platform_signup_metrics;
create policy platform_signup_metrics_service_role_all
on public.platform_signup_metrics
for all
to service_role
using (true)
with check (true);

create index if not exists idx_platform_signup_request_async_job
on public.platform_signup_request (async_job_id)
where async_job_id is not null;

create index if not exists idx_platform_signin_challenge_expiry
on public.platform_signin_challenge (challenge_status, expires_at);

create index if not exists idx_platform_signin_attempt_log_created_at
on public.platform_signin_attempt_log (created_at desc);

select public.platform_register_async_worker(jsonb_build_object(
  'worker_code', 'i01_signup_worker',
  'module_code', 'I01',
  'dispatch_mode', 'edge_worker',
  'handler_contract', 'i01/signup-worker',
  'is_active', true,
  'max_batch_size', 10,
  'default_lease_seconds', 300,
  'heartbeat_grace_seconds', 420,
  'retry_backoff_policy', jsonb_build_object('base_seconds', 60, 'multiplier', 2, 'max_seconds', 3600),
  'metadata', jsonb_build_object('phase', 'I01_RUNTIME_FOUNDATION', 'source', 'application_i01_runtime_tables')
));

revoke all on public.platform_signup_circuit_breaker from public, anon, authenticated;
revoke all on public.platform_signup_autoscale_config from public, anon, authenticated;
revoke all on public.platform_signup_metrics from public, anon, authenticated;
