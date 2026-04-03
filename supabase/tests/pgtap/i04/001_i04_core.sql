begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(31);

select has_table('public', 'platform_extensible_entity_registry', 'I04 exposes the extensible entity registry table.');
select has_table('public', 'platform_extensible_attribute_schema', 'I04 exposes the extensible attribute schema table.');
select has_table('public', 'platform_extensible_join_profile', 'I04 exposes the extensible join profile table.');
select has_table('public', 'platform_extensible_schema_cache', 'I04 exposes the extensible schema cache table.');
select has_table('public', 'platform_extensible_maintenance_run', 'I04 exposes the extensible maintenance run table.');
select has_view('public', 'platform_rm_extensible_entity_catalog', 'I04 exposes the extensible entity catalog read model.');
select has_view('public', 'platform_rm_extensible_attribute_catalog', 'I04 exposes the extensible attribute catalog read model.');
select has_view('public', 'platform_rm_extensible_runtime_overview', 'I04 exposes the extensible runtime overview read model.');
select has_view('public', 'platform_rm_extensible_maintenance_status', 'I04 exposes the extensible maintenance status read model.');
select ok(to_regprocedure('public.platform_register_extensible_entity(jsonb)') is not null, 'I04 exposes the extensible entity registration contract.') as i04_register_entity_exists;
select ok(to_regprocedure('public.platform_upsert_extensible_attribute_schema(jsonb)') is not null, 'I04 exposes the attribute schema upsert contract.') as i04_upsert_attribute_exists;
select ok(to_regprocedure('public.platform_validate_extensible_attribute_value(jsonb, jsonb)') is not null, 'I04 exposes the attribute value validation helper.') as i04_validate_attribute_value_exists;
select ok(to_regprocedure('public.platform_get_extensible_attribute_schema(jsonb)') is not null, 'I04 exposes the extensible schema resolver.') as i04_get_schema_exists;
select ok(to_regprocedure('public.platform_register_extensible_join_profile(jsonb)') is not null, 'I04 exposes the join profile registration contract.') as i04_register_join_profile_exists;
select ok(to_regprocedure('public.platform_get_extensible_join_profile(jsonb)') is not null, 'I04 exposes the join profile resolver.') as i04_get_join_profile_exists;
select ok(to_regprocedure('public.platform_validate_extensible_payload(jsonb)') is not null, 'I04 exposes the payload validation contract.') as i04_validate_payload_exists;
select ok(to_regprocedure('public.platform_get_extensible_template_descriptor(jsonb)') is not null, 'I04 exposes the template descriptor resolver.') as i04_get_template_descriptor_exists;
select ok(to_regprocedure('public.platform_invalidate_extensible_schema_cache(jsonb)') is not null, 'I04 exposes the schema cache invalidation contract.') as i04_invalidate_cache_exists;
select ok(to_regprocedure('public.platform_cleanup_extensible_schema_cache(jsonb)') is not null, 'I04 exposes the schema cache cleanup helper.') as i04_cleanup_cache_exists;
select ok(to_regprocedure('public.platform_i04_run_extensible_maintenance_scheduler()') is not null, 'I04 exposes the maintenance scheduler helper.') as i04_scheduler_exists;
select ok(exists (select 1 from cron.job where jobname = 'i04-extensible-cache-maintenance' and active), 'I04 keeps the extensible cache maintenance cron job active.') as i04_cron_active_check;
select ok(not exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_cleanup_extensible_schema_cache',
      'platform_i04_run_extensible_maintenance_scheduler'
    )
    and grantee in ('anon', 'authenticated')
), 'I04 cleanup and scheduler functions are not executable by anon/authenticated.') as i04_low_privilege_grant_check;
select is((
  select count(*)::integer
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_cleanup_extensible_schema_cache',
      'platform_i04_run_extensible_maintenance_scheduler'
    )
    and grantee = 'service_role'
), 2, 'I04 cleanup and scheduler functions are executable by service_role only.');
select is((
  select count(*)::integer
  from public.platform_read_model_catalog
  where module_code = 'I04'
    and object_name in (
      'platform_rm_extensible_entity_catalog',
      'platform_rm_extensible_attribute_catalog',
      'platform_rm_extensible_runtime_overview',
      'platform_rm_extensible_maintenance_status'
    )
), 4, 'I04 catalogs all current extensible read models in the current slice.');
select is((
  select count(*)::integer
  from public.platform_rm_gateway_operation_catalog
  where operation_code like 'i04_%'
), 5, 'I04 exposes five proof gateway operations in the live gateway catalog.');
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_extensible_entity_registry'), 'I04 entity registry keeps RLS enabled.') as i04_entity_registry_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_extensible_attribute_schema'), 'I04 attribute schema table keeps RLS enabled.') as i04_attribute_schema_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_extensible_join_profile'), 'I04 join profile table keeps RLS enabled.') as i04_join_profile_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_extensible_schema_cache'), 'I04 schema cache table keeps RLS enabled.') as i04_schema_cache_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_extensible_maintenance_run'), 'I04 maintenance run table keeps RLS enabled.') as i04_maintenance_run_rls_check;
select is((
  select count(*)::integer
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in (
      'platform_rm_extensible_entity_catalog',
      'platform_rm_extensible_attribute_catalog',
      'platform_rm_extensible_runtime_overview',
      'platform_rm_extensible_maintenance_status'
    )
    and c.reloptions @> array['security_invoker=true']
), 4, 'I04 read-model views run with security_invoker enabled.');

select * from finish();

rollback;
