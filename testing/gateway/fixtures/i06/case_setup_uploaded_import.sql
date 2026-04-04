do $$
declare
  v_issue_result jsonb;
  v_complete_result jsonb;
  v_upload_intent_id uuid;
  v_bucket_name text;
  v_storage_object_name text;
begin
  v_issue_result := public.platform_issue_import_session(jsonb_build_object(
    'tenant_id', '{{I06_TENANT_ID}}',
    'contract_code', '{{I06_IMPORT_CONTRACT_CODE}}',
    'actor_user_id', '{{I06_USER_ID}}',
    'source_file_name', 'i06-preview.csv',
    'content_type', 'text/csv',
    'expected_size_bytes', 64,
    'idempotency_key', 'i06-{{RUN_ID}}-preview-fixture'
  ));
  if not coalesce((v_issue_result->>'success')::boolean, false) then
    raise exception 'I06 preview fixture issue failed: %', v_issue_result::text;
  end if;

  v_upload_intent_id := public.platform_try_uuid(v_issue_result->'details'->>'upload_intent_id');
  v_bucket_name := nullif(v_issue_result->'details'->>'bucket_name', '');
  v_storage_object_name := nullif(v_issue_result->'details'->>'storage_object_name', '');
  if v_upload_intent_id is null or v_bucket_name is null or v_storage_object_name is null then
    raise exception 'I06 preview fixture returned incomplete upload intent details: %', v_issue_result::text;
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
    'document_metadata', jsonb_build_object('certification_module', 'I06', 'run_id', '{{RUN_ID}}', 'fixture', 'preview')
  ));
  if not coalesce((v_complete_result->>'success')::boolean, false) then
    raise exception 'I06 preview fixture completion failed: %', v_complete_result::text;
  end if;
end;
$$;

select json_build_object(
  'I06_PREVIEW_IMPORT_SESSION_ID',
  (
    select import_session_id::text
    from public.platform_import_session
    where idempotency_key = 'i06-{{RUN_ID}}-preview-fixture'
    order by created_at desc
    limit 1
  )
)::text;
