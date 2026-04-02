begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(27);

select has_table('public', 'platform_signup_circuit_breaker', 'I01 exposes the signup circuit-breaker table.');
select has_table('public', 'platform_signup_autoscale_config', 'I01 exposes the signup autoscale-config table.');
select has_table('public', 'platform_signup_metrics', 'I01 exposes the signup metrics table.');
select has_view('public', 'platform_rm_signup_queue_health', 'I01 exposes the signup queue-health read model.');
select has_view('public', 'platform_rm_signup_dead_letter', 'I01 exposes the signup dead-letter read model.');
select has_view('public', 'platform_rm_signup_recent_errors', 'I01 exposes the signup recent-errors read model.');
select has_view('public', 'platform_rm_signup_worker_status', 'I01 exposes the signup worker-status read model.');
select has_view('public', 'platform_rm_signup_metrics_trend', 'I01 exposes the signup metrics-trend read model.');
select has_view('public', 'platform_rm_user_identity_contract_snapshot', 'I01 exposes the user identity-contract snapshot read model.');
select has_view('public', 'platform_rm_identity_drift_audit', 'I01 exposes the identity drift-audit read model.');
select ok(to_regprocedure('public.platform_signup_circuit_breaker_check(jsonb)') is not null, 'I01 exposes the signup circuit-breaker check contract.') as i01_circuit_breaker_check_exists;
select ok(to_regprocedure('public.platform_signup_circuit_breaker_record_success(jsonb)') is not null, 'I01 exposes the signup circuit-breaker success contract.') as i01_circuit_breaker_success_exists;
select ok(to_regprocedure('public.platform_signup_circuit_breaker_record_failure(jsonb)') is not null, 'I01 exposes the signup circuit-breaker failure contract.') as i01_circuit_breaker_failure_exists;
select ok(to_regprocedure('public.platform_enqueue_signup_request(jsonb)') is not null, 'I01 exposes the signup enqueue contract.') as i01_enqueue_exists;
select ok(to_regprocedure('public.platform_capture_signup_metrics(jsonb)') is not null, 'I01 exposes the signup metrics capture contract.') as i01_metrics_capture_exists;
select ok(to_regprocedure('public.platform_cleanup_signin_runtime(jsonb)') is not null, 'I01 exposes the signin cleanup contract.') as i01_signin_cleanup_exists;
select ok(to_regprocedure('public.platform_i01_run_signup_orchestrator_scheduler()') is not null, 'I01 exposes the signup orchestrator scheduler helper.') as i01_orchestrator_scheduler_exists;
select ok(to_regprocedure('public.platform_i01_run_signin_cleanup_scheduler()') is not null, 'I01 exposes the signin cleanup scheduler helper.') as i01_signin_scheduler_exists;
select ok(exists (
  select 1
  from public.platform_async_worker_registry
  where worker_code = 'i01_signup_worker'
    and dispatch_mode = 'edge_worker'
    and is_active
), 'I01 keeps the signup worker registered as an active edge worker.') as i01_worker_registry_check;
select ok(exists (select 1 from cron.job where jobname = 'i01-signup-orchestrator' and active), 'I01 keeps the signup orchestrator cron job active.') as i01_signup_cron_active_check;
select ok(exists (select 1 from cron.job where jobname = 'i01-signin-cleanup' and active), 'I01 keeps the signin cleanup cron job active.') as i01_signin_cron_active_check;
select ok(not exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_signup_circuit_breaker_check',
      'platform_signup_circuit_breaker_record_success',
      'platform_signup_circuit_breaker_record_failure',
      'platform_enqueue_signup_request',
      'platform_capture_signup_metrics',
      'platform_cleanup_signin_runtime',
      'platform_i01_run_signup_orchestrator_scheduler',
      'platform_i01_run_signin_cleanup_scheduler'
    )
    and grantee in ('anon', 'authenticated')
), 'I01 runtime and scheduler functions are not executable by anon/authenticated.') as i01_low_privilege_grant_check;
select is((
  select count(*)::integer
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_signup_circuit_breaker_check',
      'platform_signup_circuit_breaker_record_success',
      'platform_signup_circuit_breaker_record_failure',
      'platform_enqueue_signup_request',
      'platform_capture_signup_metrics',
      'platform_cleanup_signin_runtime',
      'platform_i01_run_signup_orchestrator_scheduler',
      'platform_i01_run_signin_cleanup_scheduler'
    )
    and grantee = 'service_role'
), 8, 'I01 runtime and scheduler functions are executable by service_role only in the current slice.');
select is((
  select count(*)::integer
  from public.platform_read_model_catalog
  where module_code = 'I01'
    and object_name = 'platform_rm_actor_tenant_membership'
), 1, 'I01 owns the actor-tenant membership read-model catalog entry.');
select is((
  select count(*)::integer
  from public.platform_read_model_catalog
  where module_code = 'I01'
    and object_name in (
      'platform_rm_signup_queue_health',
      'platform_rm_signup_dead_letter',
      'platform_rm_signup_recent_errors',
      'platform_rm_signup_worker_status',
      'platform_rm_signup_metrics_trend',
      'platform_rm_user_identity_contract_snapshot',
      'platform_rm_identity_drift_audit'
    )
), 7, 'I01 catalogs all newly introduced runtime read models.');
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_signup_request'), 'I01 signup-request table keeps RLS enabled.') as i01_signup_request_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_signin_attempt_log'), 'I01 signin-attempt log keeps RLS enabled.') as i01_signin_attempt_log_rls_check;

select * from finish();

rollback;
