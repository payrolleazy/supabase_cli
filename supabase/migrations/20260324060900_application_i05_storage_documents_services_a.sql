create or replace function public.platform_document_write_event(p_params jsonb)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  insert into public.platform_document_event_log (
    event_type,
    severity,
    tenant_id,
    document_id,
    upload_intent_id,
    actor_user_id,
    message,
    details
  ) values (
    btrim(coalesce(p_params->>'event_type', 'document_event')),
    lower(coalesce(nullif(p_params->>'severity', ''), 'info')),
    public.platform_try_uuid(p_params->>'tenant_id'),
    public.platform_try_uuid(p_params->>'document_id'),
    public.platform_try_uuid(p_params->>'upload_intent_id'),
    public.platform_try_uuid(p_params->>'actor_user_id'),
    btrim(coalesce(p_params->>'message', 'document event')),
    coalesce(p_params->'details', '{}'::jsonb)
  );
end;
$function$;

create or replace function public.platform_register_storage_bucket(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_bucket_code text := lower(btrim(coalesce(p_params->>'bucket_code', '')));
  v_bucket_name text := lower(btrim(coalesce(p_params->>'bucket_name', '')));
  v_bucket_purpose text := lower(coalesce(nullif(p_params->>'bucket_purpose', ''), 'document'));
  v_bucket_visibility text := lower(coalesce(nullif(p_params->>'bucket_visibility', ''), 'private'));
  v_protection_mode text := lower(coalesce(nullif(p_params->>'protection_mode', ''), 'signed_url'));
  v_file_size_limit_bytes bigint := case when p_params ? 'file_size_limit_bytes' then (p_params->>'file_size_limit_bytes')::bigint else null end;
  v_retention_days integer := case when p_params ? 'retention_days' then (p_params->>'retention_days')::integer else null end;
  v_bucket_status text := lower(coalesce(nullif(p_params->>'bucket_status', ''), 'active'));
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_created_by uuid := coalesce(public.platform_try_uuid(p_params->>'created_by'), public.platform_resolve_actor());
  v_ensure_storage_bucket boolean := coalesce((p_params->>'ensure_storage_bucket')::boolean, false);
  v_allowed_mime_types text[];
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Bucket registration is restricted to internal callers.', '{}'::jsonb);
  end if;
  if v_bucket_code = '' then
    return public.platform_json_response(false, 'BUCKET_CODE_REQUIRED', 'bucket_code is required.', '{}'::jsonb);
  end if;
  if v_bucket_name = '' then
    return public.platform_json_response(false, 'BUCKET_NAME_REQUIRED', 'bucket_name is required.', '{}'::jsonb);
  end if;
  if v_bucket_purpose not in ('document', 'template', 'temporary', 'artifact') then
    return public.platform_json_response(false, 'INVALID_BUCKET_PURPOSE', 'bucket_purpose is invalid.', jsonb_build_object('bucket_purpose', v_bucket_purpose));
  end if;
  if v_bucket_visibility not in ('private', 'public') then
    return public.platform_json_response(false, 'INVALID_BUCKET_VISIBILITY', 'bucket_visibility is invalid.', jsonb_build_object('bucket_visibility', v_bucket_visibility));
  end if;
  if v_protection_mode not in ('signed_url', 'edge_stream', 'encrypted_edge_stream') then
    return public.platform_json_response(false, 'INVALID_PROTECTION_MODE', 'protection_mode is invalid.', jsonb_build_object('protection_mode', v_protection_mode));
  end if;
  if v_bucket_status not in ('active', 'inactive') then
    return public.platform_json_response(false, 'INVALID_BUCKET_STATUS', 'bucket_status is invalid.', jsonb_build_object('bucket_status', v_bucket_status));
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  v_allowed_mime_types := public.platform_jsonb_text_array(p_params->'allowed_mime_types');
  if v_allowed_mime_types is null then
    return public.platform_json_response(false, 'INVALID_ALLOWED_MIME_TYPES', 'allowed_mime_types must be a JSON array of text values.', '{}'::jsonb);
  end if;

  insert into public.platform_storage_bucket_catalog (
    bucket_code,
    bucket_name,
    bucket_purpose,
    bucket_visibility,
    protection_mode,
    file_size_limit_bytes,
    allowed_mime_types,
    retention_days,
    bucket_status,
    metadata,
    created_by
  ) values (
    v_bucket_code,
    v_bucket_name,
    v_bucket_purpose,
    v_bucket_visibility,
    v_protection_mode,
    v_file_size_limit_bytes,
    v_allowed_mime_types,
    v_retention_days,
    v_bucket_status,
    v_metadata,
    v_created_by
  )
  on conflict (bucket_code) do update
  set bucket_name = excluded.bucket_name,
      bucket_purpose = excluded.bucket_purpose,
      bucket_visibility = excluded.bucket_visibility,
      protection_mode = excluded.protection_mode,
      file_size_limit_bytes = excluded.file_size_limit_bytes,
      allowed_mime_types = excluded.allowed_mime_types,
      retention_days = excluded.retention_days,
      bucket_status = excluded.bucket_status,
      metadata = excluded.metadata,
      created_by = excluded.created_by,
      updated_at = timezone('utc', now());

  if v_ensure_storage_bucket then
    insert into storage.buckets (
      id,
      name,
      public,
      file_size_limit,
      allowed_mime_types
    ) values (
      v_bucket_name,
      v_bucket_name,
      v_bucket_visibility = 'public',
      v_file_size_limit_bytes,
      case when array_length(v_allowed_mime_types, 1) is null then null else v_allowed_mime_types end
    )
    on conflict (id) do update
    set name = excluded.name,
        public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;
  end if;

  perform public.platform_document_write_event(jsonb_build_object(
    'event_type', 'storage_bucket_registered',
    'actor_user_id', v_created_by,
    'message', 'Storage bucket catalog row upserted.',
    'details', jsonb_build_object(
      'bucket_code', v_bucket_code,
      'bucket_name', v_bucket_name,
      'ensure_storage_bucket', v_ensure_storage_bucket
    )
  ));

  return public.platform_json_response(true, 'OK', 'Storage bucket registered.', jsonb_build_object(
    'bucket_code', v_bucket_code,
    'bucket_name', v_bucket_name,
    'ensure_storage_bucket', v_ensure_storage_bucket
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_storage_bucket.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
