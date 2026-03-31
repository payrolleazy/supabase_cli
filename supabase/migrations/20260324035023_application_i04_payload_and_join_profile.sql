create or replace function public.platform_validate_extensible_payload(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entity_code text := lower(nullif(btrim(p_params->>'entity_code'), ''));
  v_tenant_id uuid := coalesce(public.platform_try_uuid(p_params->>'tenant_id'), public.platform_current_tenant_id());
  v_payload jsonb := coalesce(p_params->'payload', '{}'::jsonb);
  v_allow_unknown_attributes boolean := coalesce((p_params->>'allow_unknown_attributes')::boolean, false);
  v_schema_result jsonb;
  v_attributes jsonb;
  v_attribute jsonb;
  v_attribute_code text;
  v_required boolean;
  v_value_result jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_known_codes text[] := '{}'::text[];
  v_payload_key text;
  v_normalized_payload jsonb := '{}'::jsonb;
begin
  if v_entity_code is null then
    return public.platform_json_response(false, 'ENTITY_CODE_REQUIRED', 'entity_code is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_payload) <> 'object' then
    return public.platform_json_response(false, 'PAYLOAD_OBJECT_REQUIRED', 'payload must be a JSON object.', '{}'::jsonb);
  end if;

  v_normalized_payload := v_payload;
  v_schema_result := public.platform_get_extensible_attribute_schema(jsonb_build_object(
    'entity_code', v_entity_code,
    'tenant_id', v_tenant_id,
    'use_cache', true
  ));

  if not coalesce((v_schema_result->>'success')::boolean, false) then
    return v_schema_result;
  end if;

  v_attributes := coalesce(v_schema_result->'data'->'attributes', '[]'::jsonb);

  select coalesce(array_agg(attr->>'attribute_code'), '{}'::text[])
  into v_known_codes
  from jsonb_array_elements(v_attributes) attr;

  for v_attribute in
    select value
    from jsonb_array_elements(v_attributes)
  loop
    v_attribute_code := v_attribute->>'attribute_code';
    v_required := coalesce((v_attribute->>'is_required')::boolean, false);

    if not (v_payload ? v_attribute_code) or v_payload->v_attribute_code = 'null'::jsonb then
      if v_attribute ? 'default_value' and v_attribute->'default_value' <> 'null'::jsonb then
        v_normalized_payload := v_normalized_payload || jsonb_build_object(v_attribute_code, v_attribute->'default_value');
      elsif v_required then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'attribute_code', v_attribute_code,
          'reason', 'Required attribute is missing.'
        ));
      end if;
    else
      v_value_result := public.platform_validate_extensible_attribute_value(v_attribute, v_payload->v_attribute_code);
      if not coalesce((v_value_result->>'valid')::boolean, false) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'attribute_code', v_attribute_code,
          'reason', coalesce(v_value_result->>'reason', 'Attribute value is invalid.')
        ));
      end if;
    end if;
  end loop;

  if not v_allow_unknown_attributes then
    for v_payload_key in
      select key
      from jsonb_object_keys(v_payload) key
    loop
      if not v_payload_key = any(v_known_codes) then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'attribute_code', v_payload_key,
          'reason', 'Unknown attribute is not allowed for this entity.'
        ));
      end if;
    end loop;
  end if;

  if jsonb_array_length(v_errors) > 0 then
    return public.platform_json_response(false, 'INVALID_EXTENSIBLE_PAYLOAD', 'Payload failed extensible schema validation.', jsonb_build_object(
      'entity_code', v_entity_code,
      'tenant_id', v_tenant_id,
      'normalized_payload', v_normalized_payload,
      'attribute_errors', v_errors
    ));
  end if;

  return public.platform_json_response(true, 'OK', 'Payload passed extensible schema validation.', jsonb_build_object(
    'entity_code', v_entity_code,
    'tenant_id', v_tenant_id,
    'normalized_payload', v_normalized_payload,
    'attribute_count', coalesce(jsonb_array_length(v_attributes), 0)
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_validate_extensible_payload.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;

create or replace function public.platform_register_extensible_join_profile(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entity_code text := lower(nullif(btrim(p_params->>'entity_code'), ''));
  v_tenant_id uuid := public.platform_try_uuid(p_params->>'tenant_id');
  v_join_profile_code text := lower(nullif(btrim(p_params->>'join_profile_code'), ''));
  v_profile_status text := lower(coalesce(nullif(btrim(p_params->>'profile_status'), ''), 'active'));
  v_join_contract jsonb := coalesce(p_params->'join_contract', '{}'::jsonb);
  v_projection_contract jsonb := coalesce(p_params->'projection_contract', '{}'::jsonb);
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_entity public.platform_extensible_entity_registry%rowtype;
  v_row public.platform_extensible_join_profile%rowtype;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Join-profile writes are restricted to internal callers.', '{}'::jsonb);
  end if;

  if v_entity_code is null then
    return public.platform_json_response(false, 'ENTITY_CODE_REQUIRED', 'entity_code is required.', '{}'::jsonb);
  end if;
  if v_join_profile_code is null then
    return public.platform_json_response(false, 'JOIN_PROFILE_CODE_REQUIRED', 'join_profile_code is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_join_contract) <> 'object' then
    return public.platform_json_response(false, 'JOIN_CONTRACT_INVALID', 'join_contract must be a JSON object.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_projection_contract) <> 'object' then
    return public.platform_json_response(false, 'PROJECTION_CONTRACT_INVALID', 'projection_contract must be a JSON object.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'METADATA_INVALID', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  select *
  into v_entity
  from public.platform_extensible_entity_registry
  where entity_code = v_entity_code
    and entity_status = 'active';

  if not found then
    return public.platform_json_response(false, 'ENTITY_NOT_FOUND', 'Active extensible entity not found.', jsonb_build_object('entity_code', v_entity_code));
  end if;

  if not v_entity.join_profile_enabled then
    return public.platform_json_response(false, 'JOIN_PROFILE_DISABLED', 'Join profiles are not enabled for this entity.', jsonb_build_object('entity_code', v_entity_code));
  end if;

  if v_tenant_id is not null and not v_entity.allow_tenant_override then
    return public.platform_json_response(false, 'TENANT_OVERRIDE_NOT_ALLOWED', 'This entity does not allow tenant-specific join-profile overrides.', jsonb_build_object('entity_code', v_entity_code));
  end if;

  insert into public.platform_extensible_join_profile (
    entity_id,
    tenant_id,
    join_profile_code,
    profile_status,
    join_contract,
    projection_contract,
    metadata,
    created_by
  )
  values (
    v_entity.entity_id,
    v_tenant_id,
    v_join_profile_code,
    v_profile_status,
    v_join_contract,
    v_projection_contract,
    v_metadata,
    v_actor_user_id
  )
  on conflict on constraint platform_extensible_join_profile_entity_scope_profile_key do update
  set profile_status = excluded.profile_status,
      join_contract = excluded.join_contract,
      projection_contract = excluded.projection_contract,
      metadata = excluded.metadata,
      updated_at = timezone('utc', now())
  returning * into v_row;

  return public.platform_json_response(true, 'OK', 'Extensible join profile upserted.', jsonb_build_object(
    'join_profile_id', v_row.join_profile_id,
    'entity_code', v_entity.entity_code,
    'tenant_id', v_row.tenant_id,
    'join_profile_code', v_row.join_profile_code,
    'profile_status', v_row.profile_status
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_extensible_join_profile.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;

create or replace function public.platform_get_extensible_join_profile(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entity_code text := lower(nullif(btrim(p_params->>'entity_code'), ''));
  v_join_profile_code text := lower(nullif(btrim(p_params->>'join_profile_code'), ''));
  v_requested_tenant_id uuid := coalesce(public.platform_try_uuid(p_params->>'tenant_id'), public.platform_current_tenant_id());
  v_include_inactive boolean := coalesce((p_params->>'include_inactive')::boolean, false);
  v_entity public.platform_extensible_entity_registry%rowtype;
  v_row public.platform_extensible_join_profile%rowtype;
begin
  if v_entity_code is null then
    return public.platform_json_response(false, 'ENTITY_CODE_REQUIRED', 'entity_code is required.', '{}'::jsonb);
  end if;
  if v_join_profile_code is null then
    return public.platform_json_response(false, 'JOIN_PROFILE_CODE_REQUIRED', 'join_profile_code is required.', '{}'::jsonb);
  end if;

  select *
  into v_entity
  from public.platform_extensible_entity_registry
  where entity_code = v_entity_code
    and entity_status = 'active';

  if not found then
    return public.platform_json_response(false, 'ENTITY_NOT_FOUND', 'Active extensible entity not found.', jsonb_build_object('entity_code', v_entity_code));
  end if;

  if not v_entity.join_profile_enabled then
    return public.platform_json_response(false, 'JOIN_PROFILE_DISABLED', 'Join profiles are not enabled for this entity.', jsonb_build_object('entity_code', v_entity_code));
  end if;

  select *
  into v_row
  from public.platform_extensible_join_profile
  where entity_id = v_entity.entity_id
    and join_profile_code = v_join_profile_code
    and (tenant_id is null or tenant_id = v_requested_tenant_id)
    and (v_include_inactive or profile_status = 'active')
  order by case when tenant_id = v_requested_tenant_id then 0 else 1 end, updated_at desc
  limit 1;

  if not found then
    return public.platform_json_response(false, 'JOIN_PROFILE_NOT_FOUND', 'Extensible join profile not found.', jsonb_build_object('entity_code', v_entity_code, 'join_profile_code', v_join_profile_code));
  end if;

  return public.platform_json_response(true, 'OK', 'Extensible join profile resolved.', jsonb_build_object(
    'join_profile_id', v_row.join_profile_id,
    'entity_code', v_entity.entity_code,
    'tenant_id', v_row.tenant_id,
    'join_profile_code', v_row.join_profile_code,
    'profile_status', v_row.profile_status,
    'join_contract', v_row.join_contract,
    'projection_contract', v_row.projection_contract,
    'metadata', v_row.metadata
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_get_extensible_join_profile.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;;
