begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(39);

select has_table('public', 'platform_exchange_contract', 'I06 exposes the exchange contract table.');
select has_table('public', 'platform_import_session', 'I06 exposes the import session table.');
select has_table('public', 'platform_import_staging_row', 'I06 exposes the import staging row table.');
select has_table('public', 'platform_import_run', 'I06 exposes the import run table.');
select has_table('public', 'platform_import_validation_summary', 'I06 exposes the import validation summary table.');
select has_table('public', 'platform_export_policy', 'I06 exposes the export policy table.');
select has_table('public', 'platform_export_job', 'I06 exposes the export job table.');
select has_table('public', 'platform_export_artifact', 'I06 exposes the export artifact table.');
select has_table('public', 'platform_export_event_log', 'I06 exposes the export event log table.');
select has_table('public', 'platform_i06_maintenance_run', 'I06 exposes the maintenance run table.');
select has_table('public', 'i06_proof_entity', 'I06 exposes the proof target table.');
select has_view('public', 'platform_rm_exchange_contract_catalog', 'I06 exposes the exchange contract catalog read model.');
select has_view('public', 'platform_rm_import_session_overview', 'I06 exposes the import session overview read model.');
select has_view('public', 'platform_rm_import_validation_summary', 'I06 exposes the import validation summary read model.');
select has_view('public', 'platform_rm_export_job_overview', 'I06 exposes the export job overview read model.');
select has_view('public', 'platform_rm_export_queue_health', 'I06 exposes the export queue health read model.');
select has_view('public', 'platform_rm_exchange_runtime_overview', 'I06 exposes the exchange runtime overview read model.');
select has_view('public', 'platform_rm_exchange_alert_overview', 'I06 exposes the exchange alert overview read model.');
select has_view('public', 'platform_rm_exchange_maintenance_status', 'I06 exposes the exchange maintenance status read model.');
select ok(to_regprocedure('public.platform_get_exchange_contract(jsonb)') is not null, 'I06 exposes the exchange contract resolver.') as i06_get_contract_exists;
select ok(to_regprocedure('public.platform_issue_import_session(jsonb)') is not null, 'I06 exposes the import-session issue contract.') as i06_issue_import_exists;
select ok(to_regprocedure('public.platform_preview_import_session(jsonb)') is not null, 'I06 exposes the import preview contract.') as i06_preview_import_exists;
select ok(to_regprocedure('public.platform_commit_import_session(jsonb)') is not null, 'I06 exposes the import commit contract.') as i06_commit_import_exists;
select ok(to_regprocedure('public.platform_request_export_job(jsonb)') is not null, 'I06 exposes the export request contract.') as i06_request_export_exists;
select ok(to_regprocedure('public.platform_get_export_delivery_descriptor(jsonb)') is not null, 'I06 exposes the export delivery descriptor contract.') as i06_get_delivery_exists;
select ok(to_regprocedure('public.platform_i06_cleanup_expired_import_sessions(jsonb)') is not null, 'I06 exposes the expired import-session cleanup helper.') as i06_cleanup_import_exists;
select ok(to_regprocedure('public.platform_i06_cleanup_expired_export_artifacts(jsonb)') is not null, 'I06 exposes the expired export-artifact cleanup helper.') as i06_cleanup_export_exists;
select ok(to_regprocedure('public.platform_i06_run_exchange_maintenance(jsonb)') is not null, 'I06 exposes the exchange maintenance runner.') as i06_run_maintenance_exists;
select ok(to_regprocedure('public.platform_i06_run_runtime_scheduler()') is not null, 'I06 exposes the runtime scheduler helper.') as i06_scheduler_exists;
select ok(to_regprocedure('public.platform_i06_assert_actor_access(uuid,uuid,text[])') is not null, 'I06 exposes the actor-access assertion helper.') as i06_assert_access_exists;
select is((
  select count(*)::integer
  from public.platform_read_model_catalog
  where module_code = 'I06'
    and object_name in (
      'platform_rm_exchange_contract_catalog',
      'platform_rm_import_session_overview',
      'platform_rm_import_validation_summary',
      'platform_rm_export_job_overview',
      'platform_rm_export_queue_health'
    )
), 5, 'I06 catalogs the currently replayed governed read models.');
select is((
  select count(*)::integer
  from public.platform_extensible_entity_registry
  where entity_code = 'i06_proof_employee_extension'
    and entity_status = 'active'
), 1, 'I06 proof extensible entity remains active.');
select is((
  select count(*)::integer
  from public.platform_extensible_join_profile jp
  join public.platform_extensible_entity_registry er on er.entity_id = jp.entity_id
  where er.entity_code = 'i06_proof_employee_extension'
    and jp.join_profile_code = 'default_projection'
    and jp.profile_status = 'active'
), 1, 'I06 proof join profile remains active.');
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_import_session'), 'I06 import session keeps RLS enabled.') as i06_import_session_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_export_job'), 'I06 export job keeps RLS enabled.') as i06_export_job_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_export_artifact'), 'I06 export artifact keeps RLS enabled.') as i06_export_artifact_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_i06_maintenance_run'), 'I06 maintenance run keeps RLS enabled.') as i06_maintenance_run_rls_check;
select ok(not exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_i06_cleanup_expired_import_sessions',
      'platform_i06_cleanup_expired_export_artifacts',
      'platform_i06_run_exchange_maintenance',
      'platform_i06_run_runtime_scheduler',
      'platform_i06_assert_actor_access'
    )
    and grantee in ('anon', 'authenticated')
), 'I06 internal maintenance and access helpers are not executable by anon/authenticated.') as i06_low_privilege_grant_check;
select is((
  select count(*)::integer
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_i06_cleanup_expired_import_sessions',
      'platform_i06_cleanup_expired_export_artifacts',
      'platform_i06_run_exchange_maintenance',
      'platform_i06_run_runtime_scheduler',
      'platform_i06_assert_actor_access'
    )
    and grantee = 'service_role'
), 5, 'I06 internal maintenance and access helpers are executable by service_role only.');

select * from finish();

rollback;
