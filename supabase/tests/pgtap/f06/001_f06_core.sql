begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(19);

select has_table('public', 'platform_read_model_catalog', 'F06 exposes the read-model catalog table.');
select has_table('public', 'platform_read_model_refresh_state', 'F06 exposes the refresh-state table.');
select has_table('public', 'platform_read_model_refresh_run', 'F06 exposes the refresh-run table.');
select ok(exists (
  select 1 from pg_matviews where schemaname = 'public' and matviewname = 'platform_rm_refresh_overview'
), 'F06 exposes the refresh-overview materialized view.') as f06_refresh_overview_matview_check;
select has_view('public', 'platform_rm_refresh_status', 'F06 exposes the refresh-status view.');
select has_function('public', 'platform_request_read_model_refresh', array['jsonb'], 'F06 refresh-request contract exists.');
select has_function('public', 'platform_execute_read_model_refresh', array['jsonb'], 'F06 refresh-execution contract exists.');
select has_function('public', 'platform_get_read_model_refresh_status', array['jsonb'], 'F06 refresh-status contract exists.');
select ok(exists (
  select 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'platform_f06_run_refresh_overview_scheduler'
), 'F06 exposes the hardened internal refresh scheduler helper.') as f06_scheduler_helper_exists_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_read_model_catalog'), 'F06 read-model catalog table has RLS enabled.') as f06_catalog_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_read_model_refresh_state'), 'F06 refresh-state table has RLS enabled.') as f06_refresh_state_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_read_model_refresh_run'), 'F06 refresh-run table has RLS enabled.') as f06_refresh_run_rls_check;
select is((select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'platform_read_model_catalog'), 1, 'F06 read-model catalog keeps exactly one policy in the current slice.');
select is((select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'platform_read_model_refresh_state'), 1, 'F06 refresh-state keeps exactly one policy in the current slice.');
select is((select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'platform_read_model_refresh_run'), 1, 'F06 refresh-run keeps exactly one policy in the current slice.');
select ok(not exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_request_read_model_refresh',
      'platform_execute_read_model_refresh',
      'platform_get_read_model_refresh_status',
      'platform_begin_read_model_refresh',
      'platform_complete_read_model_refresh',
      'platform_fail_read_model_refresh'
    )
    and grantee in ('anon', 'authenticated')
), 'F06 refresh-control functions are not executable by anon/authenticated.') as f06_runtime_grant_check;
select ok(exists (
  select 1
  from cron.job
  where jobname = 'f06-refresh-overview'
    and active
), 'F06 keeps the refresh-overview cron job active.') as f06_cron_active_check;
select is((
  select refresh_strategy
  from public.platform_read_model_catalog
  where read_model_code = 'platform_refresh_overview'
), 'scheduled', 'F06 catalog marks platform_refresh_overview as scheduled.');
select ok((
  select not is_stale
  from public.platform_rm_refresh_status
  where read_model_code = 'platform_refresh_overview'
), 'F06 refresh overview is currently inside its freshness window.') as f06_refresh_freshness_check;

select * from finish();

rollback;
