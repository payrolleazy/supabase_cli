do $$
declare
  v_request_result jsonb;
  v_issue_result jsonb;
  v_complete_result jsonb;
  v_register_result jsonb;
  v_export_job_id uuid;
  v_upload_intent_id uuid;
  v_document_id uuid;
  v_bucket_name text;
  v_storage_object_name text;
begin
  v_request_result := public.platform_request_export_job(jsonb_build_object(
    'tenant_id', '{{I06_TENANT_ID}}',
    'contract_code', '{{I06_EXPORT_CONTRACT_CODE}}',
    'actor_user_id', '{{I06_USER_ID}}',
    'request_payload', jsonb_build_object('format', 'csv'),
    'idempotency_key', 'i06-{{RUN_ID}}-completed-export-fixture'
  ));
  if not coalesce((v_request_result->>'success')::boolean, false) then
    raise exception 'I06 completed export fixture request failed: %', v_request_result::text;
  end if;

  v_export_job_id := public.platform_try_uuid(v_request_result->'details'->>'export_job_id');
  if v_export_job_id is null then
    raise exception 'I06 completed export fixture missing export_job_id: %', v_request_result::text;
  end if;

  v_issue_result := public.platform_issue_document_upload_intent(jsonb_build_object(
    'tenant_id', '{{I06_TENANT_ID}}',
    'document_class_code', 'i06_' || left(replace('{{RUN_ID}}', '-', ''), 12) || '_artifact',
    'requested_by_actor_user_id', '{{I06_USER_ID}}',
    'owner_actor_user_id', '{{I06_USER_ID}}',
    'original_file_name', 'i06-proof-export.csv',
    'content_type', 'text/csv',
    'expected_size_bytes', 64,
    'bypass_membership_check', true,
    'metadata', jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}', 'fixture', 'completed_export')
  ));
  if not coalesce((v_issue_result->>'success')::boolean, false) then
    raise exception 'I06 completed export fixture upload-intent issue failed: %', v_issue_result::text;
  end if;

  v_upload_intent_id := public.platform_try_uuid(v_issue_result->'details'->>'upload_intent_id');
  v_bucket_name := nullif(v_issue_result->'details'->>'bucket_name', '');
  v_storage_object_name := nullif(v_issue_result->'details'->>'storage_object_name', '');
  if v_upload_intent_id is null or v_bucket_name is null or v_storage_object_name is null then
    raise exception 'I06 completed export fixture returned incomplete document issue details: %', v_issue_result::text;
  end if;

  insert into storage.objects (bucket_id, name, owner, owner_id, metadata, version)
  values (
    v_bucket_name,
    v_storage_object_name,
    '{{I06_USER_ID}}',
    '{{I06_USER_ID}}',
    jsonb_build_object('mimetype', 'text/csv', 'size', 64),
    '1'
  );

  v_complete_result := public.platform_complete_document_upload(jsonb_build_object(
    'upload_intent_id', v_upload_intent_id,
    'uploaded_by_actor_user_id', '{{I06_USER_ID}}',
    'file_size_bytes', 64,
    'document_metadata', jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}', 'fixture', 'completed_export')
  ));
  if not coalesce((v_complete_result->>'success')::boolean, false) then
    raise exception 'I06 completed export fixture completion failed: %', v_complete_result::text;
  end if;

  v_document_id := public.platform_try_uuid(v_complete_result->'details'->>'document_id');
  if v_document_id is null then
    raise exception 'I06 completed export fixture missing document_id: %', v_complete_result::text;
  end if;

  v_register_result := public.platform_register_export_artifact(jsonb_build_object(
    'export_job_id', v_export_job_id,
    'document_id', v_document_id,
    'created_by', '{{I06_USER_ID}}',
    'metadata', jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}', 'fixture', 'completed_export')
  ));
  if not coalesce((v_register_result->>'success')::boolean, false) then
    raise exception 'I06 completed export fixture register-artifact failed: %', v_register_result::text;
  end if;
end;
$$;

select json_build_object(
  'I06_EXPORT_JOB_ID',
  (
    select export_job_id::text
    from public.platform_export_job
    where idempotency_key = 'i06-{{RUN_ID}}-completed-export-fixture'
    order by created_at desc
    limit 1
  )
)::text;
