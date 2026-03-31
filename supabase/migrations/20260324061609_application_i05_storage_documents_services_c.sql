create or replace function public.platform_issue_document_upload_intent(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_document_class_code text := lower(btrim(coalesce(p_params->>'document_class_code', '')));
  v_requested_by_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'requested_by_actor_user_id'), public.platform_resolve_actor());
  v_owner_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'owner_actor_user_id'), public.platform_try_uuid(p_params->>'requested_by_actor_user_id'), public.platform_resolve_actor());
  v_original_file_name text := nullif(btrim(coalesce(p_params->>'original_file_name', '')), '');
  v_content_type text := lower(btrim(coalesce(p_params->>'content_type', '')));
  v_expected_size_bytes bigint := case when p_params ? 'expected_size_bytes' then (p_params->>'expected_size_bytes')::bigint else null end;
  v_binding_target_entity_code text := lower(nullif(btrim(coalesce(p_params->>'binding_target_entity_code', '')), ''));
  v_binding_target_key text := nullif(btrim(coalesce(p_params->>'binding_target_key', '')), '');
  v_binding_relation_purpose text := lower(nullif(btrim(coalesce(p_params->>'binding_relation_purpose', '')), ''));
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_expires_in_seconds integer := coalesce(case when p_params ? 'expires_in_seconds' then (p_params->>'expires_in_seconds')::integer else null end, 1800);
  v_bypass_membership_check boolean := coalesce((p_params->>'bypass_membership_check')::boolean, false);
  v_document_class public.platform_document_class%rowtype;
  v_bucket public.platform_storage_bucket_catalog%rowtype;
  v_access_row public.platform_rm_actor_access_overview%rowtype;
  v_upload_intent_id uuid := gen_random_uuid();
  v_sanitized_file_name text;
  v_storage_object_name text;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;
  if v_document_class_code = '' then
    return public.platform_json_response(false, 'DOCUMENT_CLASS_CODE_REQUIRED', 'document_class_code is required.', '{}'::jsonb);
  end if;
  if v_original_file_name is null then
    return public.platform_json_response(false, 'ORIGINAL_FILE_NAME_REQUIRED', 'original_file_name is required.', '{}'::jsonb);
  end if;
  if v_content_type = '' then
    return public.platform_json_response(false, 'CONTENT_TYPE_REQUIRED', 'content_type is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;
  if (v_binding_target_entity_code is null and v_binding_target_key is not null)
     or (v_binding_target_entity_code is not null and v_binding_target_key is null) then
    return public.platform_json_response(false, 'BINDING_TARGET_ARGUMENTS_INVALID', 'binding_target_entity_code and binding_target_key must be provided together.', '{}'::jsonb);
  end if;
  if v_binding_relation_purpose is null then
    v_binding_relation_purpose := 'attachment';
  end if;
  if v_expires_in_seconds < 60 or v_expires_in_seconds > 86400 then
    return public.platform_json_response(false, 'INVALID_INTENT_EXPIRY', 'expires_in_seconds must be between 60 and 86400.', jsonb_build_object('expires_in_seconds', v_expires_in_seconds));
  end if;

  select *
  into v_document_class
  from public.platform_document_class
  where document_class_code = v_document_class_code
    and class_status = 'active';

  if not found then
    return public.platform_json_response(false, 'DOCUMENT_CLASS_NOT_FOUND', 'Active document class not found.', jsonb_build_object('document_class_code', v_document_class_code));
  end if;

  select *
  into v_bucket
  from public.platform_storage_bucket_catalog
  where bucket_code = v_document_class.default_bucket_code
    and bucket_status = 'active';

  if not found then
    return public.platform_json_response(false, 'BUCKET_NOT_FOUND', 'Active default bucket not found.', jsonb_build_object('bucket_code', v_document_class.default_bucket_code));
  end if;

  if array_length(v_document_class.allowed_mime_types, 1) is not null and not (v_content_type = any(v_document_class.allowed_mime_types)) then
    return public.platform_json_response(false, 'CONTENT_TYPE_NOT_ALLOWED', 'content_type is not allowed for the document class.', jsonb_build_object('content_type', v_content_type, 'document_class_code', v_document_class_code));
  end if;

  if array_length(v_document_class.allowed_mime_types, 1) is null
     and array_length(v_bucket.allowed_mime_types, 1) is not null
     and not (v_content_type = any(v_bucket.allowed_mime_types)) then
    return public.platform_json_response(false, 'CONTENT_TYPE_NOT_ALLOWED', 'content_type is not allowed for the bucket.', jsonb_build_object('content_type', v_content_type, 'bucket_code', v_bucket.bucket_code));
  end if;

  if v_expected_size_bytes is not null and v_expected_size_bytes <= 0 then
    return public.platform_json_response(false, 'INVALID_EXPECTED_SIZE', 'expected_size_bytes must be greater than zero.', '{}'::jsonb);
  end if;

  if v_expected_size_bytes is not null
     and v_document_class.max_file_size_bytes is not null
     and v_expected_size_bytes > v_document_class.max_file_size_bytes then
    return public.platform_json_response(false, 'FILE_SIZE_EXCEEDS_CLASS_LIMIT', 'expected_size_bytes exceeds the document-class limit.', jsonb_build_object('expected_size_bytes', v_expected_size_bytes, 'max_file_size_bytes', v_document_class.max_file_size_bytes));
  end if;

  if v_expected_size_bytes is not null
     and v_document_class.max_file_size_bytes is null
     and v_bucket.file_size_limit_bytes is not null
     and v_expected_size_bytes > v_bucket.file_size_limit_bytes then
    return public.platform_json_response(false, 'FILE_SIZE_EXCEEDS_BUCKET_LIMIT', 'expected_size_bytes exceeds the bucket limit.', jsonb_build_object('expected_size_bytes', v_expected_size_bytes, 'bucket_file_size_limit_bytes', v_bucket.file_size_limit_bytes));
  end if;

  if not v_bypass_membership_check then
    if v_requested_by_actor_user_id is null then
      return public.platform_json_response(false, 'REQUESTED_BY_ACTOR_REQUIRED', 'requested_by_actor_user_id is required for upload intent issue.', '{}'::jsonb);
    end if;

    select *
    into v_access_row
    from public.platform_rm_actor_access_overview
    where actor_user_id = v_requested_by_actor_user_id
      and tenant_id = v_tenant_id
      and membership_status = 'active'
      and routing_status = 'enabled'
      and client_access_allowed = true
    order by is_default_tenant desc
    limit 1;

    if not found then
      return public.platform_json_response(false, 'ACTOR_TENANT_ACCESS_REQUIRED', 'Requested actor does not have active tenant access for upload intent issue.', jsonb_build_object('tenant_id', v_tenant_id, 'actor_user_id', v_requested_by_actor_user_id));
    end if;
  elsif not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'bypass_membership_check is restricted to internal callers.', '{}'::jsonb);
  end if;

  v_sanitized_file_name := public.platform_sanitize_storage_filename(v_original_file_name);
  v_storage_object_name := public.platform_build_document_storage_object_name(
    v_tenant_id,
    v_document_class.document_class_code,
    v_owner_actor_user_id,
    v_upload_intent_id,
    v_sanitized_file_name
  );

  insert into public.platform_document_upload_intent (
    upload_intent_id,
    tenant_id,
    document_class_id,
    bucket_code,
    requested_by_actor_user_id,
    owner_actor_user_id,
    binding_target_entity_code,
    binding_target_key,
    binding_relation_purpose,
    original_file_name,
    sanitized_file_name,
    content_type,
    expected_size_bytes,
    storage_object_name,
    upload_status,
    protection_mode,
    access_mode,
    allowed_role_codes,
    intent_expires_at,
    metadata
  ) values (
    v_upload_intent_id,
    v_tenant_id,
    v_document_class.document_class_id,
    v_bucket.bucket_code,
    v_requested_by_actor_user_id,
    v_owner_actor_user_id,
    v_binding_target_entity_code,
    v_binding_target_key,
    v_binding_relation_purpose,
    v_original_file_name,
    v_sanitized_file_name,
    v_content_type,
    v_expected_size_bytes,
    v_storage_object_name,
    'pending',
    v_document_class.default_protection_mode,
    v_document_class.default_access_mode,
    v_document_class.default_allowed_role_codes,
    timezone('utc', now()) + make_interval(secs => v_expires_in_seconds),
    v_metadata
  );

  perform public.platform_document_write_event(jsonb_build_object(
    'event_type', 'document_upload_intent_issued',
    'tenant_id', v_tenant_id,
    'upload_intent_id', v_upload_intent_id,
    'actor_user_id', v_requested_by_actor_user_id,
    'message', 'Document upload intent issued.',
    'details', jsonb_build_object(
      'document_class_code', v_document_class.document_class_code,
      'bucket_code', v_bucket.bucket_code,
      'storage_object_name', v_storage_object_name
    )
  ));

  return public.platform_json_response(true, 'OK', 'Document upload intent issued.', jsonb_build_object(
    'upload_intent_id', v_upload_intent_id,
    'tenant_id', v_tenant_id,
    'document_class_code', v_document_class.document_class_code,
    'bucket_code', v_bucket.bucket_code,
    'bucket_name', v_bucket.bucket_name,
    'storage_object_name', v_storage_object_name,
    'original_file_name', v_original_file_name,
    'content_type', v_content_type,
    'protection_mode', v_document_class.default_protection_mode,
    'access_mode', v_document_class.default_access_mode,
    'allowed_role_codes', to_jsonb(v_document_class.default_allowed_role_codes),
    'intent_expires_at', timezone('utc', now()) + make_interval(secs => v_expires_in_seconds)
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_issue_document_upload_intent.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
