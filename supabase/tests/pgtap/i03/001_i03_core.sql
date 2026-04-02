begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(25);

select has_table('public', 'platform_gateway_operation', 'I03 exposes the gateway operation registry table.');
select has_table('public', 'platform_gateway_operation_role', 'I03 exposes the gateway operation-role table.');
select has_table('public', 'platform_gateway_request_log', 'I03 exposes the gateway request-log table.');
select has_table('public', 'platform_gateway_idempotency_claim', 'I03 exposes the gateway idempotency-claim table.');
select has_table('public', 'platform_gateway_maintenance_run', 'I03 exposes the gateway maintenance-run table.');
select has_view('public', 'platform_rm_gateway_operation_catalog', 'I03 exposes the gateway operation catalog read model.');
select has_view('public', 'platform_rm_gateway_runtime_overview', 'I03 exposes the gateway runtime-overview read model.');
select has_view('public', 'platform_rm_gateway_error_breakdown', 'I03 exposes the gateway error-breakdown read model.');
select has_view('public', 'platform_rm_gateway_maintenance_status', 'I03 exposes the gateway maintenance-status read model.');
select ok(to_regprocedure('public.platform_execute_gateway_request(jsonb)') is not null, 'I03 exposes the authenticated gateway entrypoint.') as i03_execute_gateway_request_exists;
select ok(to_regprocedure('public.platform_execute_gateway_read(jsonb)') is not null, 'I03 exposes the gateway read dispatcher.') as i03_execute_gateway_read_exists;
select ok(to_regprocedure('public.platform_execute_gateway_mutation(jsonb)') is not null, 'I03 exposes the gateway mutation dispatcher.') as i03_execute_gateway_mutation_exists;
select ok(to_regprocedure('public.platform_execute_gateway_action(jsonb)') is not null, 'I03 exposes the gateway action dispatcher.') as i03_execute_gateway_action_exists;
select ok(to_regprocedure('public.platform_cleanup_gateway_request_log(jsonb)') is not null, 'I03 exposes the request-log cleanup contract.') as i03_cleanup_request_log_exists;
select ok(to_regprocedure('public.platform_cleanup_gateway_idempotency_claim(jsonb)') is not null, 'I03 exposes the idempotency cleanup contract.') as i03_cleanup_idempotency_exists;
select ok(to_regprocedure('public.platform_i03_run_gateway_maintenance_scheduler()') is not null, 'I03 exposes the gateway maintenance scheduler helper.') as i03_scheduler_exists;
select ok(exists (select 1 from cron.job where jobname = 'i03-gateway-maintenance' and active), 'I03 keeps the gateway maintenance cron job active.') as i03_cron_active_check;
select ok(not exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_cleanup_gateway_request_log',
      'platform_cleanup_gateway_idempotency_claim',
      'platform_i03_run_gateway_maintenance_scheduler'
    )
    and grantee in ('anon', 'authenticated')
), 'I03 cleanup and scheduler functions are not executable by anon/authenticated.') as i03_low_privilege_grant_check;
select is((
  select count(*)::integer
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_cleanup_gateway_request_log',
      'platform_cleanup_gateway_idempotency_claim',
      'platform_i03_run_gateway_maintenance_scheduler'
    )
    and grantee = 'service_role'
), 3, 'I03 cleanup and scheduler functions are executable by service_role only.');
select is((
  select count(*)::integer
  from public.platform_read_model_catalog
  where module_code = 'I03'
    and object_name in (
      'platform_rm_gateway_operation_catalog',
      'platform_rm_gateway_runtime_overview',
      'platform_rm_gateway_error_breakdown',
      'platform_rm_gateway_maintenance_status'
    )
), 4, 'I03 catalogs all gateway observability read models in the current slice.');
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_gateway_operation'), 'I03 gateway operation registry keeps RLS enabled.') as i03_gateway_operation_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_gateway_operation_role'), 'I03 gateway operation-role registry keeps RLS enabled.') as i03_gateway_operation_role_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_gateway_request_log'), 'I03 gateway request log keeps RLS enabled.') as i03_gateway_request_log_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_gateway_idempotency_claim'), 'I03 gateway idempotency claim registry keeps RLS enabled.') as i03_gateway_idempotency_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_gateway_maintenance_run'), 'I03 gateway maintenance-run table keeps RLS enabled.') as i03_gateway_maintenance_rls_check;

select * from finish();

rollback;