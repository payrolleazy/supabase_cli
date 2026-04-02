create or replace view public.platform_rm_signup_queue_health
with (security_invoker = true)
as
select
  tenant_id,
  tenant_code,
  tenant_schema,
  module_code,
  worker_code,
  queued_count,
  running_count,
  retry_wait_count,
  dead_letter_count,
  stale_lease_count,
  oldest_due_at,
  last_completed_at
from public.platform_async_queue_health_view
where worker_code = 'i01_signup_worker';

create or replace view public.platform_rm_signup_dead_letter
with (security_invoker = true)
as
select
  job_id,
  tenant_id,
  tenant_code,
  tenant_schema,
  module_code,
  worker_code,
  job_type,
  attempt_count,
  max_attempts,
  last_error_code,
  last_error_message,
  dead_lettered_at,
  updated_at
from public.platform_async_dead_letter_view
where worker_code = 'i01_signup_worker';

create or replace view public.platform_rm_signup_recent_errors
with (security_invoker = true)
as
select
  paj.job_id,
  paj.tenant_id,
  pt.tenant_code,
  paj.worker_code,
  paja.attempt_number,
  paja.attempt_state,
  paja.error_code,
  paja.error_message,
  paja.started_at,
  paja.completed_at,
  paja.duration_ms
from public.platform_async_job_attempt paja
join public.platform_async_job paj on paj.job_id = paja.job_id
join public.platform_tenant pt on pt.tenant_id = paj.tenant_id
where paj.worker_code = 'i01_signup_worker'
  and paja.attempt_state in ('failed_retryable', 'failed_terminal');

create or replace view public.platform_rm_signup_worker_status
with (security_invoker = true)
as
select
  pawr.worker_code,
  pawr.module_code,
  pawr.dispatch_mode,
  pawr.handler_contract,
  pawr.is_active,
  pawr.max_batch_size,
  pawr.default_lease_seconds,
  pawr.heartbeat_grace_seconds,
  psac.config_status,
  psac.autoscale_enabled,
  psac.min_parallel_invocations,
  psac.max_parallel_invocations,
  psac.scale_up_threshold,
  psac.scale_down_threshold,
  psac.default_batch_size,
  psac.max_batch_size as autoscale_max_batch_size,
  pscb.breaker_state,
  pscb.failure_count,
  pscb.success_count,
  pscb.last_error_code,
  pscb.last_error_message,
  paq.queued_count,
  paq.running_count,
  paq.retry_wait_count,
  paq.dead_letter_count,
  paq.stale_lease_count,
  paq.oldest_due_at,
  paq.last_completed_at
from public.platform_async_worker_registry pawr
left join public.platform_signup_autoscale_config psac on psac.config_code = 'primary'
left join public.platform_signup_circuit_breaker pscb on pscb.breaker_code = 'primary'
left join public.platform_async_queue_health_view paq on paq.worker_code = pawr.worker_code
where pawr.worker_code = 'i01_signup_worker';

create or replace view public.platform_rm_signup_metrics_trend
with (security_invoker = true)
as
select
  metric_id,
  captured_at,
  queue_depth,
  retry_wait_depth,
  running_depth,
  dead_letter_depth,
  stale_lease_depth,
  oldest_due_at,
  parallel_invocation_target,
  configured_batch_size,
  breaker_state,
  worker_active,
  metadata
from public.platform_signup_metrics;

create or replace view public.platform_rm_user_identity_contract_snapshot
with (security_invoker = true)
as
select
  pap.actor_user_id,
  pap.primary_email,
  pap.primary_mobile,
  pap.display_name,
  pap.profile_status,
  pap.email_verified,
  pap.mobile_verified,
  pap.last_signin_at,
  count(distinct patm.tenant_id) filter (where patm.membership_status = 'active') as active_membership_count,
  count(distinct parg.role_code) filter (where parg.grant_status = 'active') as active_role_count,
  (array_agg(patm.tenant_id order by pt.tenant_code) filter (where patm.is_default_tenant))[1] as default_tenant_id,
  (array_agg(pt.tenant_code order by pt.tenant_code) filter (where patm.is_default_tenant))[1] as default_tenant_code
from public.platform_actor_profile pap
left join public.platform_actor_tenant_membership patm on patm.actor_user_id = pap.actor_user_id
left join public.platform_tenant pt on pt.tenant_id = patm.tenant_id
left join public.platform_actor_role_grant parg
  on parg.actor_user_id = pap.actor_user_id
 and parg.tenant_id = patm.tenant_id
group by
  pap.actor_user_id,
  pap.primary_email,
  pap.primary_mobile,
  pap.display_name,
  pap.profile_status,
  pap.email_verified,
  pap.mobile_verified,
  pap.last_signin_at;

create or replace view public.platform_rm_identity_drift_audit
with (security_invoker = true)
as
select
  'ACTIVE_MEMBERSHIP_WITHOUT_PROFILE'::text as drift_code,
  'warning'::text as severity,
  patm.actor_user_id,
  patm.tenant_id,
  null::uuid as invitation_id,
  jsonb_build_object('membership_status', patm.membership_status, 'routing_status', patm.routing_status) as details
from public.platform_actor_tenant_membership patm
left join public.platform_actor_profile pap on pap.actor_user_id = patm.actor_user_id
where patm.membership_status = 'active'
  and pap.actor_user_id is null
union all
select
  'ACTIVE_ROLE_WITHOUT_ACTIVE_MEMBERSHIP'::text as drift_code,
  'warning'::text as severity,
  parg.actor_user_id,
  parg.tenant_id,
  null::uuid as invitation_id,
  jsonb_build_object('role_code', parg.role_code, 'grant_status', parg.grant_status) as details
from public.platform_actor_role_grant parg
left join public.platform_actor_tenant_membership patm
  on patm.tenant_id = parg.tenant_id
 and patm.actor_user_id = parg.actor_user_id
 and patm.membership_status = 'active'
where parg.grant_status = 'active'
  and patm.actor_user_id is null
union all
select
  'CLAIMED_INVITATION_WITHOUT_MEMBERSHIP'::text as drift_code,
  'warning'::text as severity,
  pmi.claimed_by_user_id as actor_user_id,
  pmi.tenant_id,
  pmi.invitation_id,
  jsonb_build_object('role_code', pmi.role_code, 'invitation_status', pmi.invitation_status) as details
from public.platform_membership_invitation pmi
left join public.platform_actor_tenant_membership patm
  on patm.tenant_id = pmi.tenant_id
 and patm.actor_user_id = pmi.claimed_by_user_id
 and patm.membership_status = 'active'
where pmi.invitation_status = 'claimed'
  and pmi.claimed_by_user_id is not null
  and patm.actor_user_id is null
union all
select
  'QUEUED_SIGNUP_WITHOUT_ASYNC_JOB'::text as drift_code,
  'error'::text as severity,
  null::uuid as actor_user_id,
  pmi.tenant_id,
  psr.invitation_id,
  jsonb_build_object('signup_request_id', psr.signup_request_id, 'request_status', psr.request_status) as details
from public.platform_signup_request psr
left join public.platform_membership_invitation pmi on pmi.invitation_id = psr.invitation_id
where psr.request_status in ('queued', 'processing')
  and psr.async_job_id is null;

update public.platform_read_model_catalog
set module_code = 'I01',
    refresh_owner_code = 'I01',
    notes = 'I01 runtime alignment.',
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('phase', 'I01_RUNTIME_ALIGNMENT')
where object_name = 'platform_rm_actor_tenant_membership';

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
values
  ('signup_queue_health', 'I01', 'Signup Queue Health', 'public', 'view', 'platform_shared', 'platform_rm_signup_queue_health', 'none', 'none', 'I01', null, null, 'I01 async signup runtime baseline.', jsonb_build_object('phase', 'I01_RUNTIME_FOUNDATION')),
  ('signup_dead_letter', 'I01', 'Signup Dead Letter', 'public', 'view', 'platform_shared', 'platform_rm_signup_dead_letter', 'none', 'none', 'I01', null, null, 'I01 async signup runtime baseline.', jsonb_build_object('phase', 'I01_RUNTIME_FOUNDATION')),
  ('signup_recent_errors', 'I01', 'Signup Recent Errors', 'public', 'view', 'platform_shared', 'platform_rm_signup_recent_errors', 'none', 'none', 'I01', null, null, 'I01 async signup runtime baseline.', jsonb_build_object('phase', 'I01_RUNTIME_FOUNDATION')),
  ('signup_worker_status', 'I01', 'Signup Worker Status', 'public', 'view', 'platform_shared', 'platform_rm_signup_worker_status', 'none', 'none', 'I01', null, null, 'I01 async signup runtime baseline.', jsonb_build_object('phase', 'I01_RUNTIME_FOUNDATION')),
  ('signup_metrics_trend', 'I01', 'Signup Metrics Trend', 'public', 'view', 'platform_shared', 'platform_rm_signup_metrics_trend', 'none', 'none', 'I01', null, null, 'I01 async signup runtime baseline.', jsonb_build_object('phase', 'I01_RUNTIME_FOUNDATION')),
  ('user_identity_contract_snapshot', 'I01', 'User Identity Contract Snapshot', 'public', 'view', 'platform_shared', 'platform_rm_user_identity_contract_snapshot', 'none', 'none', 'I01', null, null, 'I01 observability baseline.', jsonb_build_object('phase', 'I01_RUNTIME_FOUNDATION')),
  ('identity_drift_audit', 'I01', 'Identity Drift Audit', 'public', 'view', 'platform_shared', 'platform_rm_identity_drift_audit', 'none', 'none', 'I01', null, null, 'I01 observability baseline.', jsonb_build_object('phase', 'I01_RUNTIME_FOUNDATION'))
on conflict (read_model_code) do update
set module_code = excluded.module_code,
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

revoke all on public.platform_rm_signup_queue_health from public, anon, authenticated;
revoke all on public.platform_rm_signup_dead_letter from public, anon, authenticated;
revoke all on public.platform_rm_signup_recent_errors from public, anon, authenticated;
revoke all on public.platform_rm_signup_worker_status from public, anon, authenticated;
revoke all on public.platform_rm_signup_metrics_trend from public, anon, authenticated;
revoke all on public.platform_rm_user_identity_contract_snapshot from public, anon, authenticated;
revoke all on public.platform_rm_identity_drift_audit from public, anon, authenticated;

grant select on public.platform_rm_signup_queue_health to service_role;
grant select on public.platform_rm_signup_dead_letter to service_role;
grant select on public.platform_rm_signup_recent_errors to service_role;
grant select on public.platform_rm_signup_worker_status to service_role;
grant select on public.platform_rm_signup_metrics_trend to service_role;
grant select on public.platform_rm_user_identity_contract_snapshot to service_role;
grant select on public.platform_rm_identity_drift_audit to service_role;
