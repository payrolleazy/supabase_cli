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

  v_attributes := coalesce(v_schema_result->'details'->'attributes', '[]'::jsonb);

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
      select jsonb_object_keys(v_payload)
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
$$;;
