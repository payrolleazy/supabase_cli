create or replace function public.platform_bind_document_record(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_document_id uuid := public.platform_try_uuid(p_params->>'document_id');
  v_target_entity_code text := lower(btrim(coalesce(p_params->>'target_entity_code', '')));
  v_target_key text := nullif(btrim(coalesce(p_params->>'target_key', '')), '');
  v_relation_purpose text := lower(coalesce(nullif(p_params->>'relation_purpose', ''), 'attachment'));
  v_bound_by_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'bound_by_actor_user_id'), public.platform_resolve_actor());
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_document public.platform_document_record%rowtype;
  v_class public.platform_document_class%rowtype;
  v_existing_binding public.platform_document_binding%rowtype;
begin
  if v_document_id is null then
    return public.platform_json_response(false, 'DOCUMENT_ID_REQUIRED', 'document_id is required.', '{}'::jsonb);
  end if;
  if v_target_entity_code = '' then
    return public.platform_json_response(false, 'TARGET_ENTITY_CODE_REQUIRED', 'target_entity_code is required.', '{}'::jsonb);
  end if;
  if v_target_key is null then
    return public.platform_json_response(false, 'TARGET_KEY_REQUIRED', 'target_key is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  select *
  into v_document
  from public.platform_document_record
  where document_id = v_document_id
    and document_status = 'active';

  if not found then
    return public.platform_json_response(false, 'DOCUMENT_NOT_FOUND', 'Active document not found.', jsonb_build_object('document_id', v_document_id));
  end if;

  select *
  into v_class
  from public.platform_document_class
  where document_class_id = v_document.document_class_id;

  if not v_class.allow_multiple_bindings then
    select *
    into v_existing_binding
    from public.platform_document_binding
    where document_id = v_document_id
      and binding_status = 'active'
      and not (
        target_entity_code = v_target_entity_code
        and target_key = v_target_key
        and relation_purpose = v_relation_purpose
      )
    limit 1;

    if found then
      return public.platform_json_response(false, 'MULTIPLE_BINDINGS_NOT_ALLOWED', 'This document class does not allow multiple active bindings.', jsonb_build_object('document_id', v_document_id, 'document_class_code', v_class.document_class_code));
    end if;
  end if;

  insert into public.platform_document_binding (
    document_id,
    tenant_id,
    binding_status,
    target_entity_code,
    target_key,
    relation_purpose,
    bound_by_actor_user_id,
    metadata
  ) values (
    v_document_id,
    v_document.tenant_id,
    'active',
    v_target_entity_code,
    v_target_key,
    v_relation_purpose,
    v_bound_by_actor_user_id,
    v_metadata
  )
  on conflict (document_id, target_entity_code, target_key, relation_purpose) do update
  set binding_status = 'active',
      bound_by_actor_user_id = excluded.bound_by_actor_user_id,
      metadata = excluded.metadata,
      updated_at = timezone('utc', now());

  perform public.platform_document_write_event(jsonb_build_object(
    'event_type', 'document_bound',
    'tenant_id', v_document.tenant_id,
    'document_id', v_document_id,
    'actor_user_id', v_bound_by_actor_user_id,
    'message', 'Document binding upserted.',
    'details', jsonb_build_object(
      'target_entity_code', v_target_entity_code,
      'target_key', v_target_key,
      'relation_purpose', v_relation_purpose
    )
  ));

  return public.platform_json_response(true, 'OK', 'Document binding upserted.', jsonb_build_object(
    'document_id', v_document_id,
    'tenant_id', v_document.tenant_id,
    'target_entity_code', v_target_entity_code,
    'target_key', v_target_key,
    'relation_purpose', v_relation_purpose
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_bind_document_record.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
