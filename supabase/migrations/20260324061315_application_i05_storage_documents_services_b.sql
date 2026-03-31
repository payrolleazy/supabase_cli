create or replace function public.platform_register_document_class(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_document_class_code text := lower(btrim(coalesce(p_params->>'document_class_code', '')));
  v_class_label text := nullif(btrim(coalesce(p_params->>'class_label', '')), '');
  v_owner_module_code text := lower(btrim(coalesce(p_params->>'owner_module_code', '')));
  v_default_bucket_code text := lower(btrim(coalesce(p_params->>'default_bucket_code', '')));
  v_sensitivity_level text := lower(coalesce(nullif(p_params->>'sensitivity_level', ''), 'normal'));
  v_default_access_mode text := lower(coalesce(nullif(p_params->>'default_access_mode', ''), 'owner_only'));
  v_default_protection_mode text := lower(coalesce(nullif(p_params->>'default_protection_mode', ''), 'signed_url'));
  v_max_file_size_bytes bigint := case when p_params ? 'max_file_size_bytes' then (p_params->>'max_file_size_bytes')::bigint else null end;
  v_allow_multiple_bindings boolean := case when p_params ? 'allow_multiple_bindings' then (p_params->>'allow_multiple_bindings')::boolean else true end;
  v_application_encryption_required boolean := case when p_params ? 'application_encryption_required' then (p_params->>'application_encryption_required')::boolean else false end;
  v_class_status text := lower(coalesce(nullif(p_params->>'class_status', ''), 'active'));
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_created_by uuid := coalesce(public.platform_try_uuid(p_params->>'created_by'), public.platform_resolve_actor());
  v_allowed_role_codes text[];
  v_allowed_mime_types text[];
  v_bucket public.platform_storage_bucket_catalog%rowtype;
  v_missing_role_codes text[];
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Document-class registration is restricted to internal callers.', '{}'::jsonb);
  end if;
  if v_document_class_code = '' then
    return public.platform_json_response(false, 'DOCUMENT_CLASS_CODE_REQUIRED', 'document_class_code is required.', '{}'::jsonb);
  end if;
  if v_class_label is null then
    return public.platform_json_response(false, 'CLASS_LABEL_REQUIRED', 'class_label is required.', '{}'::jsonb);
  end if;
  if v_owner_module_code = '' then
    return public.platform_json_response(false, 'OWNER_MODULE_CODE_REQUIRED', 'owner_module_code is required.', '{}'::jsonb);
  end if;
  if v_default_bucket_code = '' then
    return public.platform_json_response(false, 'DEFAULT_BUCKET_CODE_REQUIRED', 'default_bucket_code is required.', '{}'::jsonb);
  end if;
  if v_sensitivity_level not in ('normal', 'sensitive', 'restricted') then
    return public.platform_json_response(false, 'INVALID_SENSITIVITY_LEVEL', 'sensitivity_level is invalid.', jsonb_build_object('sensitivity_level', v_sensitivity_level));
  end if;
  if v_default_access_mode not in ('owner_only', 'owner_and_admin', 'role_bound', 'tenant_membership', 'service_only') then
    return public.platform_json_response(false, 'INVALID_ACCESS_MODE', 'default_access_mode is invalid.', jsonb_build_object('default_access_mode', v_default_access_mode));
  end if;
  if v_default_protection_mode not in ('signed_url', 'edge_stream', 'encrypted_edge_stream') then
    return public.platform_json_response(false, 'INVALID_PROTECTION_MODE', 'default_protection_mode is invalid.', jsonb_build_object('default_protection_mode', v_default_protection_mode));
  end if;
  if v_class_status not in ('active', 'inactive') then
    return public.platform_json_response(false, 'INVALID_CLASS_STATUS', 'class_status is invalid.', jsonb_build_object('class_status', v_class_status));
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  v_allowed_role_codes := public.platform_jsonb_text_array(p_params->'allowed_role_codes');
  if v_allowed_role_codes is null then
    return public.platform_json_response(false, 'INVALID_ALLOWED_ROLE_CODES', 'allowed_role_codes must be a JSON array of text values.', '{}'::jsonb);
  end if;

  v_allowed_mime_types := public.platform_jsonb_text_array(p_params->'allowed_mime_types');
  if v_allowed_mime_types is null then
    return public.platform_json_response(false, 'INVALID_ALLOWED_MIME_TYPES', 'allowed_mime_types must be a JSON array of text values.', '{}'::jsonb);
  end if;

  select *
  into v_bucket
  from public.platform_storage_bucket_catalog
  where bucket_code = v_default_bucket_code
    and bucket_status = 'active';

  if not found then
    return public.platform_json_response(false, 'BUCKET_NOT_FOUND', 'Active default bucket not found.', jsonb_build_object('default_bucket_code', v_default_bucket_code));
  end if;

  if v_default_access_mode in ('owner_and_admin', 'role_bound') and array_length(v_allowed_role_codes, 1) is null then
    return public.platform_json_response(false, 'ALLOWED_ROLE_CODES_REQUIRED', 'allowed_role_codes are required for the selected access mode.', jsonb_build_object('default_access_mode', v_default_access_mode));
  end if;

  if array_length(v_allowed_role_codes, 1) is not null then
    select coalesce(array_agg(r.role_code order by r.role_code), '{}'::text[])
    into v_missing_role_codes
    from unnest(v_allowed_role_codes) as r(role_code)
    where not exists (
      select 1
      from public.platform_access_role par
      where par.role_code = r.role_code
        and par.role_status = 'active'
    );

    if array_length(v_missing_role_codes, 1) is not null then
      return public.platform_json_response(false, 'ALLOWED_ROLE_CODES_INVALID', 'One or more allowed_role_codes are not active roles.', jsonb_build_object('missing_role_codes', v_missing_role_codes));
    end if;
  end if;

  if array_length(v_allowed_mime_types, 1) is not null
     and array_length(v_bucket.allowed_mime_types, 1) is not null
     and not (v_allowed_mime_types <@ v_bucket.allowed_mime_types) then
    return public.platform_json_response(false, 'ALLOWED_MIME_TYPES_OUTSIDE_BUCKET_POLICY', 'Document-class MIME types must stay within the bucket policy.', jsonb_build_object('default_bucket_code', v_default_bucket_code));
  end if;

  if v_max_file_size_bytes is not null
     and v_bucket.file_size_limit_bytes is not null
     and v_max_file_size_bytes > v_bucket.file_size_limit_bytes then
    return public.platform_json_response(false, 'MAX_FILE_SIZE_EXCEEDS_BUCKET_LIMIT', 'Document-class max file size exceeds the bucket limit.', jsonb_build_object('max_file_size_bytes', v_max_file_size_bytes, 'bucket_file_size_limit_bytes', v_bucket.file_size_limit_bytes));
  end if;

  if v_application_encryption_required and v_default_protection_mode <> 'encrypted_edge_stream' then
    return public.platform_json_response(false, 'ENCRYPTION_REQUIRES_ENCRYPTED_STREAM', 'application_encryption_required requires default_protection_mode = encrypted_edge_stream.', '{}'::jsonb);
  end if;

  insert into public.platform_document_class (
    document_class_code,
    class_label,
    owner_module_code,
    default_bucket_code,
    sensitivity_level,
    default_access_mode,
    default_allowed_role_codes,
    default_protection_mode,
    max_file_size_bytes,
    allowed_mime_types,
    allow_multiple_bindings,
    application_encryption_required,
    class_status,
    metadata,
    created_by
  ) values (
    v_document_class_code,
    v_class_label,
    v_owner_module_code,
    v_default_bucket_code,
    v_sensitivity_level,
    v_default_access_mode,
    v_allowed_role_codes,
    v_default_protection_mode,
    v_max_file_size_bytes,
    v_allowed_mime_types,
    v_allow_multiple_bindings,
    v_application_encryption_required,
    v_class_status,
    v_metadata,
    v_created_by
  )
  on conflict (document_class_code) do update
  set class_label = excluded.class_label,
      owner_module_code = excluded.owner_module_code,
      default_bucket_code = excluded.default_bucket_code,
      sensitivity_level = excluded.sensitivity_level,
      default_access_mode = excluded.default_access_mode,
      default_allowed_role_codes = excluded.default_allowed_role_codes,
      default_protection_mode = excluded.default_protection_mode,
      max_file_size_bytes = excluded.max_file_size_bytes,
      allowed_mime_types = excluded.allowed_mime_types,
      allow_multiple_bindings = excluded.allow_multiple_bindings,
      application_encryption_required = excluded.application_encryption_required,
      class_status = excluded.class_status,
      metadata = excluded.metadata,
      created_by = excluded.created_by,
      updated_at = timezone('utc', now());

  perform public.platform_document_write_event(jsonb_build_object(
    'event_type', 'document_class_registered',
    'actor_user_id', v_created_by,
    'message', 'Document class upserted.',
    'details', jsonb_build_object(
      'document_class_code', v_document_class_code,
      'default_bucket_code', v_default_bucket_code
    )
  ));

  return public.platform_json_response(true, 'OK', 'Document class registered.', jsonb_build_object(
    'document_class_code', v_document_class_code,
    'default_bucket_code', v_default_bucket_code
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_document_class.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
