begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(34);

select has_table('public', 'wcm_employee', 'WCM_CORE exposes the source employee template table.');
select has_table('public', 'wcm_employee_service_state', 'WCM_CORE exposes the source employee service-state template table.');
select has_table('public', 'wcm_employee_lifecycle_event', 'WCM_CORE exposes the source employee lifecycle-event template table.');
select has_table('public', 'platform_wcm_resignation_request', 'WCM_CORE exposes the resignation request runtime table.');
select has_table('public', 'platform_wcm_lifecycle_rollback_audit', 'WCM_CORE exposes the lifecycle rollback audit table.');
select has_table('public', 'platform_wcm_lifecycle_event_queue', 'WCM_CORE exposes the lifecycle event queue table.');
select has_view('public', 'platform_rm_wcm_employee_catalog', 'WCM_CORE exposes the employee catalog read model.');
select has_view('public', 'platform_rm_wcm_service_state_overview', 'WCM_CORE exposes the service-state overview read model.');
select has_view('public', 'platform_rm_wcm_billable_state_overview', 'WCM_CORE exposes the billable-state overview read model.');
select has_view('public', 'platform_rm_wcm_headcount_summary', 'WCM_CORE exposes the headcount summary read model.');
select has_view('public', 'platform_rm_wcm_resignation_request_catalog', 'WCM_CORE exposes the resignation request catalog read model.');
select has_view('public', 'platform_rm_wcm_lifecycle_rollback_audit', 'WCM_CORE exposes the lifecycle rollback audit read model.');
select ok(to_regprocedure('public.platform_apply_wcm_core_to_tenant(jsonb)') is not null, 'WCM_CORE exposes the tenant apply helper.') as wcm_apply_to_tenant_exists;
select ok(to_regprocedure('public.platform_register_wcm_employee(jsonb)') is not null, 'WCM_CORE exposes the employee registration contract.') as wcm_register_employee_exists;
select ok(to_regprocedure('public.platform_upsert_wcm_service_state(jsonb)') is not null, 'WCM_CORE exposes the service-state upsert contract.') as wcm_upsert_service_state_exists;
select ok(to_regprocedure('public.platform_request_wcm_resignation(jsonb)') is not null, 'WCM_CORE exposes the resignation request contract.') as wcm_request_resignation_exists;
select ok(to_regprocedure('public.platform_process_wcm_resignation_approval(jsonb)') is not null, 'WCM_CORE exposes the resignation approval contract.') as wcm_process_resignation_approval_exists;
select ok(to_regprocedure('public.platform_preview_wcm_resignation_rollback(jsonb)') is not null, 'WCM_CORE exposes the rollback preview contract.') as wcm_preview_rollback_exists;
select ok(to_regprocedure('public.platform_apply_wcm_resignation_rollback(uuid, uuid, uuid, text, jsonb)') is not null, 'WCM_CORE exposes the rollback apply contract.') as wcm_apply_rollback_exists;
select ok(to_regprocedure('public.platform_withdraw_wcm_resignation(jsonb)') is not null, 'WCM_CORE exposes the resignation withdrawal contract.') as wcm_withdraw_resignation_exists;
select ok(to_regprocedure('public.platform_process_wcm_pending_events(integer)') is not null, 'WCM_CORE exposes the lifecycle event processor.') as wcm_process_events_exists;
select ok(to_regprocedure('public.platform_sync_wcm_resignation_authority(uuid, uuid, uuid)') is not null, 'WCM_CORE exposes the resignation authority sync helper.') as wcm_sync_authority_exists;
select ok(to_regprocedure('public.platform_write_wcm_lifecycle_rollback_audit(uuid, uuid, uuid, bigint, text, text, boolean, uuid, text, jsonb)') is not null, 'WCM_CORE exposes the lifecycle rollback audit writer.') as wcm_write_audit_exists;
select ok(exists (select 1 from cron.job where jobname = 'wcm-core-lifecycle-heartbeat' and active), 'WCM_CORE keeps the lifecycle heartbeat cron job active.') as wcm_cron_active_check;
select ok(not exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_apply_wcm_core_to_tenant',
      'platform_request_wcm_resignation',
      'platform_process_wcm_resignation_approval',
      'platform_apply_wcm_resignation_rollback',
      'platform_withdraw_wcm_resignation',
      'platform_process_wcm_pending_events',
      'platform_sync_wcm_resignation_authority',
      'platform_write_wcm_lifecycle_rollback_audit'
    )
    and grantee in ('anon', 'authenticated')
), 'WCM_CORE internal and lifecycle functions are not executable by anon/authenticated.') as wcm_low_privilege_grant_check;
select is((
  select count(*)::integer
  from public.platform_read_model_catalog
  where module_code = 'WCM_CORE'
    and object_name in (
      'platform_rm_wcm_employee_catalog',
      'platform_rm_wcm_service_state_overview',
      'platform_rm_wcm_billable_state_overview',
      'platform_rm_wcm_headcount_summary',
      'platform_rm_wcm_resignation_request_catalog',
      'platform_rm_wcm_lifecycle_rollback_audit'
    )
), 6, 'WCM_CORE catalogs all six governed read models in the current slice.');
select is((
  select count(*)::integer
  from public.platform_gateway_operation
  where group_name = 'WCM Core'
), 11, 'WCM_CORE exposes all eleven application-gateway operations in the current slice.');
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_wcm_resignation_request'), 'WCM_CORE resignation request runtime keeps RLS enabled.') as wcm_resignation_request_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_wcm_lifecycle_rollback_audit'), 'WCM_CORE lifecycle rollback audit keeps RLS enabled.') as wcm_rollback_audit_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_wcm_lifecycle_event_queue'), 'WCM_CORE lifecycle event queue keeps RLS enabled.') as wcm_event_queue_rls_check;
select is((
  select count(*)::integer
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in (
      'platform_rm_wcm_employee_catalog',
      'platform_rm_wcm_service_state_overview',
      'platform_rm_wcm_billable_state_overview',
      'platform_rm_wcm_headcount_summary',
      'platform_rm_wcm_resignation_request_catalog',
      'platform_rm_wcm_lifecycle_rollback_audit'
    )
    and c.reloptions @> array['security_invoker=true']
), 6, 'WCM_CORE read-model views run with security_invoker enabled.');
select ok(exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name = 'platform_request_wcm_resignation'
    and grantee = 'service_role'
), 'WCM_CORE resignation request contract remains executable by service_role.') as wcm_request_service_role_grant_check;
select ok(exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name = 'platform_process_wcm_resignation_approval'
    and grantee = 'service_role'
), 'WCM_CORE resignation approval contract remains executable by service_role.') as wcm_approval_service_role_grant_check;
select ok(exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name = 'platform_apply_wcm_resignation_rollback'
    and grantee = 'service_role'
), 'WCM_CORE rollback apply contract remains executable by service_role.') as wcm_apply_service_role_grant_check;

select * from finish();

rollback;
