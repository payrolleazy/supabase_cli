begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(30);

select has_table('public', 'platform_storage_bucket_catalog', 'I05 exposes the governed storage bucket catalog table.');
select has_table('public', 'platform_document_class', 'I05 exposes the governed document class table.');
select has_table('public', 'platform_document_upload_intent', 'I05 exposes the document upload intent table.');
select has_table('public', 'platform_document_record', 'I05 exposes the document record table.');
select has_table('public', 'platform_document_binding', 'I05 exposes the document binding table.');
select has_table('public', 'platform_document_event_log', 'I05 exposes the document event log table.');
select has_view('public', 'platform_rm_storage_bucket_catalog', 'I05 exposes the storage bucket catalog read model.');
select has_view('public', 'platform_rm_document_catalog', 'I05 exposes the document catalog read model.');
select has_view('public', 'platform_rm_document_binding_catalog', 'I05 exposes the document binding catalog read model.');
select has_view('public', 'platform_rm_eoap_document_readiness', 'I05 exposes the EOAP document readiness read model.');
select ok(to_regprocedure('public.platform_register_storage_bucket(jsonb)') is not null, 'I05 exposes the storage bucket registration contract.') as i05_register_bucket_exists;
select ok(to_regprocedure('public.platform_register_document_class(jsonb)') is not null, 'I05 exposes the document class registration contract.') as i05_register_document_class_exists;
select ok(to_regprocedure('public.platform_issue_document_upload_intent(jsonb)') is not null, 'I05 exposes the upload intent contract.') as i05_issue_upload_intent_exists;
select ok(to_regprocedure('public.platform_complete_document_upload(jsonb)') is not null, 'I05 exposes the upload completion contract.') as i05_complete_upload_exists;
select ok(to_regprocedure('public.platform_get_document_access_descriptor(jsonb)') is not null, 'I05 exposes the document access descriptor contract.') as i05_document_access_exists;
select ok(to_regprocedure('public.platform_bind_document_record(jsonb)') is not null, 'I05 exposes the document binding contract.') as i05_bind_document_exists;
select ok(to_regprocedure('public.platform_i05_run_document_maintenance(jsonb)') is not null, 'I05 exposes the document maintenance contract.') as i05_maintenance_exists;
select ok(to_regprocedure('public.platform_i05_run_document_maintenance_scheduler()') is not null, 'I05 exposes the maintenance scheduler helper.') as i05_scheduler_exists;
select ok(exists (select 1 from cron.job where jobname = 'i05-document-maintenance' and active), 'I05 keeps the document maintenance cron job active.') as i05_cron_active_check;
select ok(not exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_i05_run_document_maintenance',
      'platform_i05_run_document_maintenance_scheduler'
    )
    and grantee in ('anon', 'authenticated')
), 'I05 maintenance functions are not executable by anon/authenticated.') as i05_low_privilege_grant_check;
select is((
  select count(*)::integer
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_i05_run_document_maintenance',
      'platform_i05_run_document_maintenance_scheduler'
    )
    and grantee = 'service_role'
), 2, 'I05 maintenance functions are executable by service_role only.');
select is((
  select count(*)::integer
  from public.platform_read_model_catalog
  where module_code = 'I05'
    and object_name in (
      'platform_rm_storage_bucket_catalog',
      'platform_rm_document_catalog',
      'platform_rm_document_binding_catalog'
    )
), 3, 'I05 catalogs its governed storage/document read models in the current slice.');
select is((
  select count(*)::integer
  from public.platform_rm_gateway_operation_catalog
  where operation_code like 'i05_%'
), 5, 'I05 exposes five proof gateway operations in the live gateway catalog.');
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_storage_bucket_catalog'), 'I05 storage bucket catalog keeps RLS enabled.') as i05_storage_bucket_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_document_class'), 'I05 document class table keeps RLS enabled.') as i05_document_class_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_document_upload_intent'), 'I05 upload intent table keeps RLS enabled.') as i05_upload_intent_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_document_record'), 'I05 document record table keeps RLS enabled.') as i05_document_record_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_document_binding'), 'I05 document binding table keeps RLS enabled.') as i05_document_binding_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_document_event_log'), 'I05 document event log table keeps RLS enabled.') as i05_document_event_log_rls_check;
select is((
  select count(*)::integer
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in (
      'platform_rm_storage_bucket_catalog',
      'platform_rm_document_catalog',
      'platform_rm_document_binding_catalog'
    )
    and c.reloptions @> array['security_invoker=true']
), 3, 'I05 governed read-model views run with security_invoker enabled.');

select * from finish();

rollback;
