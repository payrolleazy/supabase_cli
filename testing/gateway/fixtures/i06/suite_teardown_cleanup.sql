delete from public.platform_gateway_request_log
where actor_user_id = '{{I06_USER_ID}}'::uuid
   or tenant_id in (
     select tenant_id
     from public.platform_tenant
     where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
   );

delete from public.platform_gateway_idempotency_claim
where actor_user_id = '{{I06_USER_ID}}'::uuid
   or tenant_id in (
     select tenant_id
     from public.platform_tenant
     where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
   );

delete from public.platform_async_job_attempt
where job_id in (
  select job_id from public.platform_import_run where tenant_id in (
    select tenant_id from public.platform_tenant where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
  )
  union
  select job_id from public.platform_export_job where tenant_id in (
    select tenant_id from public.platform_tenant where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
  )
);

delete from public.platform_export_event_log
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_export_artifact
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_export_job
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_export_policy
where contract_id in (
  select contract_id
  from public.platform_exchange_contract
  where contract_code in (
    'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12) || '_import',
    'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12) || '_export'
  )
);

delete from public.platform_import_validation_summary
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_import_staging_row
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_import_run
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_import_session
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_async_job
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
)
  and worker_code in ('i06_import_worker', 'i06_export_worker');

delete from public.i06_proof_entity
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_document_binding
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_document_record
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_document_upload_intent
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_document_event_log
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);


delete from public.platform_exchange_contract
where contract_code in (
  'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12) || '_import',
  'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12) || '_export'
);

delete from public.platform_document_class
where document_class_code in (
  'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12) || '_upload',
  'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12) || '_artifact'
);

delete from public.platform_storage_bucket_catalog
where bucket_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12) || '_bucket';

delete from public.platform_actor_role_grant
where actor_user_id = '{{I06_USER_ID}}'::uuid;

delete from public.platform_actor_tenant_membership
where actor_user_id = '{{I06_USER_ID}}'::uuid;

delete from public.platform_actor_profile
where actor_user_id = '{{I06_USER_ID}}'::uuid;

delete from public.platform_tenant_provisioning
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_tenant_access_state
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_tenant
where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12);

do $$
begin
  execute format('drop schema if exists %I cascade', 'tenant_i06_' || left(replace('{{RUN_ID}}', '-', ''), 12));
end;
$$;

delete from auth.users
where id = '{{I06_USER_ID}}'::uuid;

select json_build_object(
  'I06_CLEANUP_COMPLETE',
  true
)::text;

