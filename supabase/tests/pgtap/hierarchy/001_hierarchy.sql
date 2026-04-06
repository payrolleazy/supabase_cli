begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(38);

select has_table('public', 'hierarchy_position_group', 'HIERARCHY exposes the source position-group template table.');
select has_table('public', 'hierarchy_position', 'HIERARCHY exposes the source position template table.');
select has_table('public', 'hierarchy_position_occupancy', 'HIERARCHY exposes the source occupancy template table.');
select has_view('public', 'platform_rm_hierarchy_position_group_catalog', 'HIERARCHY exposes the position-group catalog read model.');
select has_view('public', 'platform_rm_hierarchy_position_catalog', 'HIERARCHY exposes the position catalog read model.');
select has_view('public', 'platform_rm_hierarchy_org_chart', 'HIERARCHY exposes the org-chart read model.');
select has_view('public', 'platform_rm_hierarchy_operational_occupancy', 'HIERARCHY exposes the operational-occupancy read model.');
select has_view('public', 'platform_rm_hierarchy_team_scope', 'HIERARCHY exposes the team-scope read model.');
select ok(to_regclass('public.platform_rm_hierarchy_org_chart_cached_store') is not null, 'HIERARCHY exposes the cached org-chart materialized store.');
select has_view('public', 'platform_rm_hierarchy_org_chart_cached', 'HIERARCHY exposes the cached org-chart read model alias.');
select has_view('public', 'platform_rm_hierarchy_position_history', 'HIERARCHY exposes the position-history read model.');
select has_view('public', 'platform_rm_hierarchy_metrics_summary', 'HIERARCHY exposes the metrics-summary read model.');
select has_view('public', 'platform_rm_hierarchy_health_status', 'HIERARCHY exposes the health-status read model.');
select has_table('public', 'platform_hierarchy_metadata', 'HIERARCHY exposes the metadata runtime table.');
select has_table('public', 'platform_hierarchy_health_status', 'HIERARCHY exposes the health runtime table.');
select has_table('public', 'platform_hierarchy_error_log', 'HIERARCHY exposes the error-log runtime table.');
select has_table('public', 'platform_hierarchy_performance_log', 'HIERARCHY exposes the performance-log runtime table.');
select has_table('public', 'platform_hierarchy_backup_log', 'HIERARCHY exposes the backup-log runtime table.');
select has_table('public', 'platform_hierarchy_maintenance_lock', 'HIERARCHY exposes the maintenance-lock runtime table.');
select has_table('public', 'platform_hierarchy_maintenance_run', 'HIERARCHY exposes the maintenance-run runtime table.');
select ok(to_regprocedure('public.platform_apply_hierarchy_to_tenant(jsonb)') is not null, 'HIERARCHY exposes the tenant apply helper.');
select ok(to_regprocedure('public.platform_register_hierarchy_position_group(jsonb)') is not null, 'HIERARCHY exposes the register-position-group contract.');
select ok(to_regprocedure('public.platform_register_hierarchy_position(jsonb)') is not null, 'HIERARCHY exposes the register-position contract.');
select ok(to_regprocedure('public.platform_upsert_hierarchy_position_occupancy(jsonb)') is not null, 'HIERARCHY exposes the occupancy upsert contract.');
select ok(to_regprocedure('public.platform_get_hierarchy_manager_resolution(jsonb)') is not null, 'HIERARCHY exposes the manager-resolution contract.');
select ok(to_regprocedure('public.platform_get_hierarchy_operational_occupant(jsonb)') is not null, 'HIERARCHY exposes the operational-occupant contract.');
select ok(to_regprocedure('public.platform_search_hierarchy_positions(jsonb)') is not null, 'HIERARCHY exposes the search contract.');
select ok(to_regprocedure('public.platform_hierarchy_health_check(jsonb)') is not null, 'HIERARCHY exposes the health-check contract.');
select ok(to_regprocedure('public.platform_hierarchy_self_test(jsonb)') is not null, 'HIERARCHY exposes the self-test contract.');
select ok(to_regprocedure('public.platform_hierarchy_capture_backup(jsonb)') is not null, 'HIERARCHY exposes the backup contract.');
select ok(to_regprocedure('public.platform_hierarchy_run_maintenance(jsonb)') is not null, 'HIERARCHY exposes the maintenance contract.');
select ok(to_regprocedure('public.platform_hierarchy_run_maintenance_scheduler()') is not null, 'HIERARCHY exposes the maintenance scheduler contract.');
select is((select count(*)::integer from public.platform_read_model_catalog where module_code = 'HIERARCHY'), 10, 'HIERARCHY catalogs all ten read-model surfaces in the current slice.');
select is((select count(*)::integer from public.platform_gateway_operation where group_name = 'Hierarchy'), 17, 'HIERARCHY exposes all seventeen application-gateway operations in the current slice.');
select is((
  select count(*)::integer
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in (
      'platform_rm_hierarchy_position_group_catalog',
      'platform_rm_hierarchy_position_catalog',
      'platform_rm_hierarchy_org_chart',
      'platform_rm_hierarchy_operational_occupancy',
      'platform_rm_hierarchy_team_scope',
      'platform_rm_hierarchy_org_chart_cached',
      'platform_rm_hierarchy_position_history',
      'platform_rm_hierarchy_metrics_summary',
      'platform_rm_hierarchy_health_status'
    )
    and c.reloptions @> array['security_invoker=true']
), 9, 'HIERARCHY read-model views run with security_invoker enabled.');
select ok(not exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_hierarchy_org_chart_rows_for_schema',
      'platform_hierarchy_org_chart_cache_seed_rows',
      'platform_hierarchy_position_history_rows',
      'platform_hierarchy_metrics_summary_rows',
      'platform_hierarchy_health_status_rows',
      'platform_hierarchy_run_diagnostics_internal',
      'platform_hierarchy_health_check',
      'platform_hierarchy_self_test',
      'platform_search_hierarchy_positions',
      'platform_hierarchy_capture_backup',
      'platform_hierarchy_run_maintenance',
      'platform_hierarchy_run_maintenance_scheduler'
    )
    and grantee in ('anon', 'authenticated')
), 'HIERARCHY internal runtime functions are not executable by anon/authenticated.');
select ok(exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name = 'platform_hierarchy_health_check'
    and grantee = 'service_role'
), 'HIERARCHY health-check contract remains executable by service_role.');
select ok(exists (
  select 1
  from cron.job
  where jobname = 'hierarchy-maintenance'
    and active
), 'HIERARCHY keeps the maintenance cron job active.');

select * from finish();

rollback;
