create or replace function public.platform_get_document_access_descriptor(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_document_id uuid := public.platform_try_uuid(p_params->>'document_id');
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_resolve_actor());
  v_bypass_access_check boolean := coalesce((p_params->>'bypass_access_check')::boolean, false);
  v_document public.platform_document_record%rowtype;
  v_bucket public.platform_storage_bucket_catalog%rowtype;
  v_document_class public.platform_document_class%rowtype;
  v_access_row public.platform_rm_actor_access_overview%rowtype;
  v_access_granted boolean := false;
  v_access_reason text := 'access_denied';
begin
  if v_document_id is null then
    return public.platform_json_response(false, 'DOCUMENT_ID_REQUIRED', 'document_id is required.', '{}'::jsonb);
  end if;

  select *
  into v_document
  from public.platform_document_record
  where document_id = v_document_id;

  if not found then
    return public.platform_json_response(false, 'DOCUMENT_NOT_FOUND', 'Document not found.', jsonb_build_object('document_id', v_document_id));
  end if;

  if v_document.document_status <> 'active' then
    return public.platform_json_response(false, 'DOCUMENT_NOT_ACTIVE', 'Document is not active.', jsonb_build_object('document_id', v_document_id, 'document_status', v_document.document_status));
  end if;

  select *
  into v_bucket
  from public.platform_storage_bucket_catalog
  where bucket_code = v_document.bucket_code;

  select *
  into v_document_class
  from public.platform_document_class
  where document_class_id = v_document.document_class_id;

  if v_bypass_access_check then
    if not public.platform_is_internal_caller() then
      return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'bypass_access_check is restricted to internal callers.', '{}'::jsonb);
    end if;

    v_access_granted := true;
    v_access_reason := 'internal_bypass';
  elsif v_document.access_mode = 'service_only' then
    if public.platform_is_internal_caller() then
      v_access_granted := true;
      v_access_reason := 'service_only_internal';
    else
      v_access_granted := false;
      v_access_reason := 'service_only';
    end if;
  else
    if v_actor_user_id is null then
      return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
    end if;

    select *
    into v_access_row
    from public.platform_rm_actor_access_overview
    where actor_user_id = v_actor_user_id
      and tenant_id = v_document.tenant_id
      and membership_status = 'active'
      and routing_status = 'enabled'
      and client_access_allowed = true
    order by is_default_tenant desc
    limit 1;

    if not found then
      v_access_granted := false;
      v_access_reason := 'tenant_access_missing';
    elsif v_document.access_mode = 'tenant_membership' then
      v_access_granted := true;
      v_access_reason := 'tenant_membership';
    elsif v_document.owner_actor_user_id is not null and v_actor_user_id = v_document.owner_actor_user_id then
      v_access_granted := true;
      v_access_reason := 'owner';
    elsif v_document.access_mode in ('owner_and_admin', 'role_bound')
       and array_length(v_document.allowed_role_codes, 1) is not null
       and coalesce(v_access_row.active_role_codes, '{}'::text[]) && v_document.allowed_role_codes then
      v_access_granted := true;
      v_access_reason := 'role_grant';
    else
      v_access_granted := false;
      v_access_reason := 'role_not_permitted';
    end if;
  end if;

  if not v_access_granted then
    perform public.platform_document_write_event(jsonb_build_object(
      'event_type', 'document_access_denied',
      'severity', 'warning',
      'tenant_id', v_document.tenant_id,
      'document_id', v_document.document_id,
      'actor_user_id', v_actor_user_id,
      'message', 'Document access denied.',
      'details', jsonb_build_object(
        'access_reason', v_access_reason,
        'access_mode', v_document.access_mode,
        'protection_mode', v_document.protection_mode
      )
    ));

    return public.platform_json_response(false, 'ACCESS_DENIED', 'Document access denied.', jsonb_build_object(
      'document_id', v_document_id,
      'tenant_id', v_document.tenant_id,
      'actor_user_id', v_actor_user_id,
      'access_reason', v_access_reason
    ));
  end if;

  perform public.platform_document_write_event(jsonb_build_object(
    'event_type', 'document_access_descriptor_resolved',
    'severity', 'info',
    'tenant_id', v_document.tenant_id,
    'document_id', v_document.document_id,
    'actor_user_id', v_actor_user_id,
    'message', 'Document access descriptor resolved.',
    'details', jsonb_build_object(
      'access_reason', v_access_reason,
      'access_mode', v_document.access_mode,
      'protection_mode', v_document.protection_mode
    )
  ));

  return public.platform_json_response(true, 'OK', 'Document access descriptor resolved.', jsonb_build_object(
    'document_id', v_document.document_id,
    'tenant_id', v_document.tenant_id,
    'document_class_code', v_document_class.document_class_code,
    'bucket_code', v_document.bucket_code,
    'bucket_name', v_bucket.bucket_name,
    'storage_object_name', v_document.storage_object_name,
    'original_file_name', v_document.original_file_name,
    'content_type', v_document.content_type,
    'protection_mode', v_document.protection_mode,
    'access_mode', v_document.access_mode,
    'access_reason', v_access_reason,
    'owner_actor_user_id', v_document.owner_actor_user_id,
    'allowed_role_codes', to_jsonb(v_document.allowed_role_codes),
    'document_status', v_document.document_status
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_get_document_access_descriptor.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

revoke all on public.platform_storage_bucket_catalog from public, anon, authenticated;
revoke all on public.platform_document_class from public, anon, authenticated;
revoke all on public.platform_document_upload_intent from public, anon, authenticated;
revoke all on public.platform_document_record from public, anon, authenticated;
revoke all on public.platform_document_binding from public, anon, authenticated;
revoke all on public.platform_document_event_log from public, anon, authenticated;
revoke all on public.platform_rm_storage_bucket_catalog from public, anon, authenticated;
revoke all on public.platform_rm_document_catalog from public, anon, authenticated;
revoke all on public.platform_rm_document_binding_catalog from public, anon, authenticated;

revoke all on function public.platform_jsonb_text_array(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_sanitize_storage_filename(text) from public, anon, authenticated, service_role;
revoke all on function public.platform_build_document_storage_object_name(uuid, text, uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.platform_document_write_event(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_register_storage_bucket(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_register_document_class(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_issue_document_upload_intent(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_bind_document_record(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_complete_document_upload(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_get_document_access_descriptor(jsonb) from public, anon, authenticated, service_role;

grant select on public.platform_rm_storage_bucket_catalog to service_role;
grant select on public.platform_rm_document_catalog to service_role;
grant select on public.platform_rm_document_binding_catalog to service_role;

grant execute on function public.platform_document_write_event(jsonb) to service_role;
grant execute on function public.platform_register_storage_bucket(jsonb) to service_role;
grant execute on function public.platform_register_document_class(jsonb) to service_role;
grant execute on function public.platform_issue_document_upload_intent(jsonb) to service_role;
grant execute on function public.platform_bind_document_record(jsonb) to service_role;
grant execute on function public.platform_complete_document_upload(jsonb) to service_role;
grant execute on function public.platform_get_document_access_descriptor(jsonb) to service_role;;
