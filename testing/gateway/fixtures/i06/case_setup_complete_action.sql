do $$
declare
  v_result jsonb;
  v_upload_intent_id uuid;
  v_bucket_name text;
  v_storage_object_name text;
begin
  v_result := public.platform_issue_import_session(jsonb_build_object(
    'tenant_id', '{{I06_TENANT_ID}}',
    'contract_code', '{{I06_IMPORT_CONTRACT_CODE}}',
    'actor_user_id', '{{I06_USER_ID}}',
    'source_file_name', 'i06-complete.csv',
    'content_type', 'text/csv',
    'expected_size_bytes', 64,
    'idempotency_key', 'i06-{{RUN_ID}}-complete-fixture'
  ));
  if not coalesce((v_result->>'success')::boolean, false) then
    raise exception 'I06 complete fixture issue failed: %', v_result::text;
  end if;

  v_upload_intent_id := public.platform_try_uuid(v_result->'details'->>'upload_intent_id');
  v_bucket_name := nullif(v_result->'details'->>'bucket_name', '');
  v_storage_object_name := nullif(v_result->'details'->>'storage_object_name', '');

  if v_upload_intent_id is null or v_bucket_name is null or v_storage_object_name is null then
    raise exception 'I06 complete fixture returned incomplete upload intent details: %', v_result::text;
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
end;
$$;

select json_build_object(
  'I06_COMPLETE_UPLOAD_INTENT_ID',
  (
    select upload_intent_id::text
    from public.platform_import_session
    where idempotency_key = 'i06-{{RUN_ID}}-complete-fixture'
    order by created_at desc
    limit 1
  )
)::text;
