create or replace function public.platform_complete_document_upload(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_upload_intent_id uuid := public.platform_try_uuid(p_params->>'upload_intent_id');
  v_uploaded_by_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'uploaded_by_actor_user_id'), public.platform_resolve_actor());
  v_file_size_bytes bigint := case when p_params ? 'file_size_bytes' then (p_params->>'file_size_bytes')::bigint else null end;
  v_checksum_sha256 text := nullif(btrim(coalesce(p_params->>'checksum_sha256', '')), '');
  v_storage_metadata jsonb := coalesce(p_params->'storage_metadata', '{}'::jsonb);
  v_document_metadata jsonb := coalesce(p_params->'document_metadata', '{}'::jsonb);
  v_expires_on date := case when p_params ? 'expires_on' then (p_params->>'expires_on')::date else null end;
  v_intent public.platform_document_upload_intent%rowtype;
  v_document_class public.platform_document_class%rowtype;
  v_bucket public.platform_storage_bucket_catalog%rowtype;
  v_access_row public.platform_rm_actor_access_overview%rowtype;
  v_effective_actor_user_id uuid;
  v_document_id uuid;
  v_binding_result jsonb;
begin
  if v_upload_intent_id is null then
    return public.platform_json_response(false, 'UPLOAD_INTENT_ID_REQUIRED', 'upload_intent_id is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_storage_metadata) <> 'object' or jsonb_typeof(v_document_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'storage_metadata and document_metadata must be JSON objects.', '{}'::jsonb);
  end if;
  if v_checksum_sha256 is not null and v_checksum_sha256 !~ '^[A-Fa-f0-9]{64}$' then
    return public.platform_json_response(false, 'INVALID_CHECKSUM', 'checksum_sha256 must be a 64-character hexadecimal string.', '{}'::jsonb);
  end if;

  select *
  into v_intent
  from public.platform_document_upload_intent
  where upload_intent_id = v_upload_intent_id;

  if not found then
    return public.platform_json_response(false, 'UPLOAD_INTENT_NOT_FOUND', 'Upload intent not found.', jsonb_build_object('upload_intent_id', v_upload_intent_id));
  end if;

  select *
  into v_document_class
  from public.platform_document_class
  where document_class_id = v_intent.document_class_id;

  select *
  into v_bucket
  from public.platform_storage_bucket_catalog
  where bucket_code = v_intent.bucket_code;

  if not found then
    return public.platform_json_response(false, 'BUCKET_NOT_FOUND', 'Bucket not found for upload intent.', jsonb_build_object('bucket_code', v_intent.bucket_code));
  end if;

  if v_intent.upload_status = 'completed' then
    select document_id
    into v_document_id
    from public.platform_document_record
    where upload_intent_id = v_upload_intent_id;

    if v_document_id is not null then
      return public.platform_json_response(true, 'OK', 'Upload intent already completed.', jsonb_build_object(
        'upload_intent_id', v_upload_intent_id,
        'document_id', v_document_id,
        'tenant_id', v_intent.tenant_id
      ));
    end if;

    return public.platform_json_response(false, 'UPLOAD_ALREADY_MARKED_COMPLETED', 'Upload intent is marked completed without a document record.', jsonb_build_object('upload_intent_id', v_upload_intent_id));
  end if;

  if v_intent.upload_status <> 'pending' then
    return public.platform_json_response(false, 'UPLOAD_INTENT_NOT_PENDING', 'Only pending upload intents can be completed.', jsonb_build_object('upload_status', v_intent.upload_status));
  end if;

  if v_intent.intent_expires_at < timezone('utc', now()) then
    update public.platform_document_upload_intent
    set upload_status = 'expired',
        updated_at = timezone('utc', now())
    where upload_intent_id = v_upload_intent_id;

    return public.platform_json_response(false, 'UPLOAD_INTENT_EXPIRED', 'Upload intent has expired.', jsonb_build_object('upload_intent_id', v_upload_intent_id));
  end if;

  v_effective_actor_user_id := coalesce(v_uploaded_by_actor_user_id, v_intent.requested_by_actor_user_id, v_intent.owner_actor_user_id);
  if v_effective_actor_user_id is null then
    return public.platform_json_response(false, 'UPLOADED_BY_ACTOR_REQUIRED', 'An actor context is required to complete document upload.', '{}'::jsonb);
  end if;

  if not public.platform_is_internal_caller() then
    if v_intent.requested_by_actor_user_id is not null
       and v_effective_actor_user_id not in (v_intent.requested_by_actor_user_id, coalesce(v_intent.owner_actor_user_id, v_intent.requested_by_actor_user_id)) then
      return public.platform_json_response(false, 'UPLOAD_COMPLETION_NOT_ALLOWED', 'Upload completion is restricted to the request actor or owner actor.', jsonb_build_object(
        'upload_intent_id', v_upload_intent_id,
        'actor_user_id', v_effective_actor_user_id
      ));
    end if;

    select *
    into v_access_row
    from public.platform_rm_actor_access_overview
    where actor_user_id = v_effective_actor_user_id
      and tenant_id = v_intent.tenant_id
      and membership_status = 'active'
      and routing_status = 'enabled'
      and client_access_allowed = true
    order by is_default_tenant desc
    limit 1;

    if not found then
      return public.platform_json_response(false, 'ACTOR_TENANT_ACCESS_REQUIRED', 'Uploaded actor does not have active tenant access for upload completion.', jsonb_build_object(
        'tenant_id', v_intent.tenant_id,
        'actor_user_id', v_effective_actor_user_id
      ));
    end if;
  end if;

  if v_file_size_bytes is not null and v_file_size_bytes <= 0 then
    return public.platform_json_response(false, 'INVALID_FILE_SIZE', 'file_size_bytes must be greater than zero.', '{}'::jsonb);
  end if;

  if v_file_size_bytes is not null
     and v_document_class.max_file_size_bytes is not null
     and v_file_size_bytes > v_document_class.max_file_size_bytes then
    return public.platform_json_response(false, 'FILE_SIZE_EXCEEDS_CLASS_LIMIT', 'file_size_bytes exceeds the document-class limit.', jsonb_build_object('file_size_bytes', v_file_size_bytes, 'max_file_size_bytes', v_document_class.max_file_size_bytes));
  end if;

  if not exists (
    select 1
    from storage.objects so
    where so.bucket_id = v_bucket.bucket_name
      and so.name = v_intent.storage_object_name
  ) then
    return public.platform_json_response(false, 'STORAGE_OBJECT_NOT_FOUND', 'Uploaded storage object not found for upload intent.', jsonb_build_object(
      'upload_intent_id', v_upload_intent_id,
      'bucket_name', v_bucket.bucket_name,
      'storage_object_name', v_intent.storage_object_name
    ));
  end if;

  insert into public.platform_document_record (
    tenant_id,
    document_class_id,
    bucket_code,
    upload_intent_id,
    owner_actor_user_id,
    uploaded_by_actor_user_id,
    storage_object_name,
    original_file_name,
    content_type,
    file_size_bytes,
    checksum_sha256,
    protection_mode,
    access_mode,
    allowed_role_codes,
    document_status,
    version_no,
    expires_on,
    storage_metadata,
    document_metadata
  ) values (
    v_intent.tenant_id,
    v_intent.document_class_id,
    v_intent.bucket_code,
    v_upload_intent_id,
    v_intent.owner_actor_user_id,
    v_effective_actor_user_id,
    v_intent.storage_object_name,
    v_intent.original_file_name,
    v_intent.content_type,
    coalesce(v_file_size_bytes, v_intent.expected_size_bytes),
    v_checksum_sha256,
    v_intent.protection_mode,
    v_intent.access_mode,
    v_intent.allowed_role_codes,
    'active',
    1,
    v_expires_on,
    v_storage_metadata,
    v_document_metadata
  )
  on conflict (upload_intent_id) do nothing
  returning document_id into v_document_id;

  if v_document_id is null then
    select document_id
    into v_document_id
    from public.platform_document_record
    where upload_intent_id = v_upload_intent_id;
  end if;

  update public.platform_document_upload_intent
  set upload_status = 'completed',
      updated_at = timezone('utc', now())
  where upload_intent_id = v_upload_intent_id;

  if v_intent.binding_target_entity_code is not null then
    v_binding_result := public.platform_bind_document_record(jsonb_build_object(
      'document_id', v_document_id,
      'target_entity_code', v_intent.binding_target_entity_code,
      'target_key', v_intent.binding_target_key,
      'relation_purpose', coalesce(v_intent.binding_relation_purpose, 'attachment'),
      'bound_by_actor_user_id', coalesce(v_uploaded_by_actor_user_id, v_intent.requested_by_actor_user_id),
      'metadata', jsonb_build_object('source', 'upload_intent')
    ));

    if not coalesce((v_binding_result->>'success')::boolean, false) then
      raise exception 'document binding failed during upload completion: %', v_binding_result::text;
    end if;
  end if;

  perform public.platform_document_write_event(jsonb_build_object(
    'event_type', 'document_upload_completed',
    'tenant_id', v_intent.tenant_id,
    'document_id', v_document_id,
    'upload_intent_id', v_upload_intent_id,
    'actor_user_id', coalesce(v_uploaded_by_actor_user_id, v_intent.requested_by_actor_user_id),
    'message', 'Document upload completed.',
    'details', jsonb_build_object(
      'document_class_id', v_intent.document_class_id,
      'bucket_code', v_intent.bucket_code,
      'bucket_name', v_bucket.bucket_name,
      'storage_object_name', v_intent.storage_object_name
    )
  ));

  return public.platform_json_response(true, 'OK', 'Document upload completed.', jsonb_build_object(
    'upload_intent_id', v_upload_intent_id,
    'document_id', v_document_id,
    'tenant_id', v_intent.tenant_id,
    'bucket_code', v_intent.bucket_code,
    'storage_object_name', v_intent.storage_object_name
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_complete_document_upload.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
