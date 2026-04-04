do $$
declare
  v_suffix text := left(replace('{{RUN_ID}}', '-', ''), 12);
  v_tenant_id uuid := gen_random_uuid();
  v_tenant_code text := 'i06_' || v_suffix;
  v_schema_name text := 'tenant_i06_' || v_suffix;
  v_bucket_code text := 'i06_' || v_suffix || '_bucket';
  v_bucket_name text := v_bucket_code;
  v_upload_class_code text := 'i06_' || v_suffix || '_upload';
  v_artifact_class_code text := 'i06_' || v_suffix || '_artifact';
  v_import_contract_code text := 'i06_' || v_suffix || '_import';
  v_export_contract_code text := 'i06_' || v_suffix || '_export';
  v_actor_user_id uuid := '{{I06_USER_ID}}'::uuid;
  v_actor_email text := '{{I06_EMAIL}}';
  v_result jsonb;
begin
  delete from public.platform_gateway_request_log where actor_user_id = v_actor_user_id;
  delete from public.platform_gateway_idempotency_claim where actor_user_id = v_actor_user_id;
  delete from public.platform_export_event_log where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_export_artifact where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_export_job where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_export_policy where contract_id in (select contract_id from public.platform_exchange_contract where contract_code in (v_import_contract_code, v_export_contract_code));
  delete from public.platform_import_validation_summary where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_import_staging_row where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_import_run where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_import_session where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.i06_proof_entity where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_document_binding where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_document_record where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_document_upload_intent where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_document_event_log where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_exchange_contract where contract_code in (v_import_contract_code, v_export_contract_code);
  delete from public.platform_document_class where document_class_code in (v_upload_class_code, v_artifact_class_code);
  delete from public.platform_storage_bucket_catalog where bucket_code = v_bucket_code;
  delete from public.platform_actor_role_grant where actor_user_id = v_actor_user_id;
  delete from public.platform_actor_tenant_membership where actor_user_id = v_actor_user_id;
  delete from public.platform_actor_profile where actor_user_id = v_actor_user_id;
  delete from public.platform_tenant_provisioning where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_tenant_access_state where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_tenant where tenant_code = v_tenant_code;
  execute format('drop schema if exists %I cascade', v_schema_name);
  execute format('create schema %I', v_schema_name);

  insert into public.platform_tenant (tenant_id, tenant_code, schema_name, display_name, legal_name, metadata)
  values (
    v_tenant_id,
    v_tenant_code,
    v_schema_name,
    'I06 Runtime Tenant',
    'I06 Runtime Tenant Legal',
    jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}')
  );

  insert into public.platform_tenant_provisioning (
    tenant_id, provisioning_status, schema_provisioned, foundation_version, latest_completed_step, ready_for_routing, details
  ) values (
    v_tenant_id,
    'ready_for_routing',
    true,
    'local_i06_cert',
    'ready_for_routing',
    true,
    jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}')
  );

  insert into public.platform_tenant_access_state (tenant_id, access_state, billing_state, reason_details)
  values (
    v_tenant_id,
    'active',
    'current',
    jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}')
  );

  insert into public.platform_actor_profile (
    actor_user_id, primary_email, display_name, profile_status, email_verified, created_via, metadata
  ) values (
    v_actor_user_id,
    v_actor_email,
    'I06 Certification User',
    'active',
    true,
    'local_certification',
    jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}')
  ) on conflict (actor_user_id) do update
  set
    primary_email = excluded.primary_email,
    display_name = excluded.display_name,
    profile_status = excluded.profile_status,
    email_verified = excluded.email_verified,
    created_via = excluded.created_via,
    metadata = excluded.metadata;

  insert into public.platform_actor_tenant_membership (
    tenant_id, actor_user_id, membership_status, is_default_tenant, routing_status, metadata
  ) values (
    v_tenant_id,
    v_actor_user_id,
    'active',
    true,
    'enabled',
    jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}')
  ) on conflict (tenant_id, actor_user_id) do update
  set
    membership_status = excluded.membership_status,
    is_default_tenant = excluded.is_default_tenant,
    routing_status = excluded.routing_status,
    metadata = excluded.metadata;

  insert into public.platform_actor_role_grant (
    tenant_id, actor_user_id, role_code, grant_status, metadata
  ) values (
    v_tenant_id,
    v_actor_user_id,
    'tenant_owner_admin',
    'active',
    jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}', 'role_code', 'tenant_owner_admin')
  ) on conflict (tenant_id, actor_user_id, role_code) do update
  set grant_status = excluded.grant_status,
      metadata = excluded.metadata;

  v_result := public.platform_register_storage_bucket(jsonb_build_object(
    'bucket_code', v_bucket_code,
    'bucket_name', v_bucket_name,
    'bucket_purpose', 'document',
    'bucket_visibility', 'private',
    'protection_mode', 'signed_url',
    'allowed_mime_types', jsonb_build_array('text/csv'),
    'file_size_limit_bytes', 1048576,
    'retention_days', 7,
    'bucket_status', 'active',
    'ensure_storage_bucket', true,
    'created_by', v_actor_user_id,
    'metadata', jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}')
  ));
  if not coalesce((v_result->>'success')::boolean, false) then
    raise exception 'I06 bucket setup failed: %', v_result::text;
  end if;

  v_result := public.platform_register_document_class(jsonb_build_object(
    'document_class_code', v_upload_class_code,
    'class_label', 'I06 Proof Upload Document',
    'owner_module_code', 'I06',
    'default_bucket_code', v_bucket_code,
    'default_access_mode', 'role_bound',
    'default_protection_mode', 'signed_url',
    'allowed_role_codes', jsonb_build_array('tenant_owner_admin'),
    'allowed_mime_types', jsonb_build_array('text/csv'),
    'max_file_size_bytes', 1048576,
    'class_status', 'active',
    'created_by', v_actor_user_id,
    'metadata', jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}', 'kind', 'upload')
  ));
  if not coalesce((v_result->>'success')::boolean, false) then
    raise exception 'I06 upload document-class setup failed: %', v_result::text;
  end if;

  v_result := public.platform_register_document_class(jsonb_build_object(
    'document_class_code', v_artifact_class_code,
    'class_label', 'I06 Proof Export Artifact',
    'owner_module_code', 'I06',
    'default_bucket_code', v_bucket_code,
    'default_access_mode', 'role_bound',
    'default_protection_mode', 'signed_url',
    'allowed_role_codes', jsonb_build_array('tenant_owner_admin'),
    'allowed_mime_types', jsonb_build_array('text/csv'),
    'max_file_size_bytes', 1048576,
    'class_status', 'active',
    'created_by', v_actor_user_id,
    'metadata', jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}', 'kind', 'artifact')
  ));
  if not coalesce((v_result->>'success')::boolean, false) then
    raise exception 'I06 artifact document-class setup failed: %', v_result::text;
  end if;

  v_result := public.platform_register_async_worker(jsonb_build_object(
    'worker_code', 'i06_import_worker',
    'module_code', 'I06',
    'dispatch_mode', 'edge_worker',
    'handler_contract', 'i06/import-worker',
    'is_active', true,
    'max_batch_size', 50,
    'default_lease_seconds', 120,
    'heartbeat_grace_seconds', 180,
    'retry_backoff_policy', '{}'::jsonb,
    'metadata', jsonb_build_object('purpose', 'local_certification_i06')
  ));
  if not coalesce((v_result->>'success')::boolean, false) then
    raise exception 'I06 import worker setup failed: %', v_result::text;
  end if;

  v_result := public.platform_register_async_worker(jsonb_build_object(
    'worker_code', 'i06_export_worker',
    'module_code', 'I06',
    'dispatch_mode', 'edge_worker',
    'handler_contract', 'i06/export-worker',
    'is_active', true,
    'max_batch_size', 50,
    'default_lease_seconds', 120,
    'heartbeat_grace_seconds', 180,
    'retry_backoff_policy', '{}'::jsonb,
    'metadata', jsonb_build_object('purpose', 'local_certification_i06')
  ));
  if not coalesce((v_result->>'success')::boolean, false) then
    raise exception 'I06 export worker setup failed: %', v_result::text;
  end if;

  v_result := public.platform_register_exchange_contract(jsonb_build_object(
    'contract_code', v_import_contract_code,
    'direction', 'import',
    'contract_label', 'I06 Proof Employee Import',
    'owner_module_code', 'I06',
    'entity_code', 'i06_proof_employee_extension',
    'worker_code', 'i06_import_worker',
    'join_profile_code', 'default_projection',
    'template_mode', 'i04_descriptor',
    'accepted_file_formats', jsonb_build_array('csv'),
    'allowed_role_codes', jsonb_build_array('tenant_owner_admin'),
    'upload_document_class_code', v_upload_class_code,
    'contract_status', 'active',
    'created_by', v_actor_user_id,
    'metadata', jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}', 'kind', 'import')
  ));
  if not coalesce((v_result->>'success')::boolean, false) then
    raise exception 'I06 import contract setup failed: %', v_result::text;
  end if;

  v_result := public.platform_register_exchange_contract(jsonb_build_object(
    'contract_code', v_export_contract_code,
    'direction', 'export',
    'contract_label', 'I06 Proof Employee Export',
    'owner_module_code', 'I06',
    'entity_code', 'i06_proof_employee_extension',
    'worker_code', 'i06_export_worker',
    'join_profile_code', 'default_projection',
    'template_mode', 'i04_descriptor',
    'accepted_file_formats', jsonb_build_array('csv'),
    'allowed_role_codes', jsonb_build_array('tenant_owner_admin'),
    'artifact_document_class_code', v_artifact_class_code,
    'artifact_bucket_code', v_bucket_code,
    'contract_status', 'active',
    'created_by', v_actor_user_id,
    'metadata', jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}', 'kind', 'export')
  ));
  if not coalesce((v_result->>'success')::boolean, false) then
    raise exception 'I06 export contract setup failed: %', v_result::text;
  end if;

  v_result := public.platform_upsert_export_policy(jsonb_build_object(
    'contract_code', v_export_contract_code,
    'default_retention_days', 7,
    'cleanup_enabled', true,
    'policy_status', 'active',
    'created_by', v_actor_user_id,
    'metadata', jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}')
  ));
  if not coalesce((v_result->>'success')::boolean, false) then
    raise exception 'I06 export policy setup failed: %', v_result::text;
  end if;

  insert into public.i06_proof_entity (
    tenant_id, employee_code, full_name, salary, start_date, metadata, created_by
  ) values
  (
    v_tenant_id,
    'EMP-001',
    'Alice Example',
    1200,
    date '2026-04-01',
    jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}', 'seeded', true),
    v_actor_user_id
  ),
  (
    v_tenant_id,
    'EMP-002',
    'Bob Example',
    1350,
    date '2026-04-02',
    jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}', 'seeded', true),
    v_actor_user_id
  )
  on conflict (tenant_id, employee_code) do update
  set full_name = excluded.full_name,
      salary = excluded.salary,
      start_date = excluded.start_date,
      metadata = excluded.metadata,
      created_by = excluded.created_by,
      updated_at = timezone('utc', now());
end;
$$;

select json_build_object(
  'I06_TENANT_ID', (select tenant_id::text from public.platform_tenant where tenant_code = 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12)),
  'I06_IMPORT_CONTRACT_CODE', 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12) || '_import',
  'I06_EXPORT_CONTRACT_CODE', 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12) || '_export'
)::text;


