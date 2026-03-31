create or replace function public.platform_get_extensible_template_descriptor(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_schema_result jsonb;
  v_columns jsonb;
begin
  v_schema_result := public.platform_get_extensible_attribute_schema(p_params || jsonb_build_object('include_inactive', false));

  if not coalesce((v_schema_result->>'success')::boolean, false) then
    return v_schema_result;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'column_code', attr->>'attribute_code',
        'label', attr->>'ui_label',
        'data_type', attr->>'data_type',
        'required', coalesce((attr->>'is_required')::boolean, false),
        'default_value', attr->'default_value'
      )
      order by coalesce((attr->>'sort_order')::integer, 100), attr->>'attribute_code'
    ),
    '[]'::jsonb
  )
  into v_columns
  from jsonb_array_elements(coalesce(v_schema_result->'data'->'attributes', '[]'::jsonb)) attr;

  return public.platform_json_response(true, 'OK', 'Extensible template descriptor resolved.', jsonb_build_object(
    'entity_code', v_schema_result->'data'->>'entity_code',
    'tenant_id', v_schema_result->'data'->>'tenant_id',
    'target_relation_schema', v_schema_result->'data'->>'target_relation_schema',
    'target_relation_name', v_schema_result->'data'->>'target_relation_name',
    'columns', v_columns
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_get_extensible_template_descriptor.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;

create or replace function public.platform_invalidate_extensible_schema_cache(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entity_code text := lower(nullif(btrim(p_params->>'entity_code'), ''));
  v_tenant_id uuid := public.platform_try_uuid(p_params->>'tenant_id');
  v_entity_id uuid;
  v_deleted_count integer := 0;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Schema-cache invalidation is restricted to internal callers.', '{}'::jsonb);
  end if;

  if v_entity_code is null then
    return public.platform_json_response(false, 'ENTITY_CODE_REQUIRED', 'entity_code is required.', '{}'::jsonb);
  end if;

  select entity_id
  into v_entity_id
  from public.platform_extensible_entity_registry
  where entity_code = v_entity_code;

  if not found then
    return public.platform_json_response(false, 'ENTITY_NOT_FOUND', 'Extensible entity not found.', jsonb_build_object('entity_code', v_entity_code));
  end if;

  if v_tenant_id is null then
    delete from public.platform_extensible_schema_cache
    where entity_id = v_entity_id;
  else
    delete from public.platform_extensible_schema_cache
    where entity_id = v_entity_id
      and (tenant_id = v_tenant_id or tenant_id is null);
  end if;

  get diagnostics v_deleted_count = row_count;

  return public.platform_json_response(true, 'OK', 'Extensible schema cache invalidated.', jsonb_build_object(
    'entity_code', v_entity_code,
    'tenant_id', v_tenant_id,
    'deleted_count', v_deleted_count
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_invalidate_extensible_schema_cache.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;

revoke all on public.platform_extensible_entity_registry from public, anon, authenticated;
revoke all on public.platform_extensible_attribute_schema from public, anon, authenticated;
revoke all on public.platform_extensible_join_profile from public, anon, authenticated;
revoke all on public.platform_extensible_schema_cache from public, anon, authenticated;
revoke all on public.platform_rm_extensible_entity_catalog from public, anon, authenticated;
revoke all on public.platform_rm_extensible_attribute_catalog from public, anon, authenticated;

grant all on public.platform_extensible_entity_registry to service_role;
grant all on public.platform_extensible_attribute_schema to service_role;
grant all on public.platform_extensible_join_profile to service_role;
grant all on public.platform_extensible_schema_cache to service_role;
grant select on public.platform_rm_extensible_entity_catalog to service_role;
grant select on public.platform_rm_extensible_attribute_catalog to service_role;

revoke all on function public.platform_validate_extensible_attribute_value(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_extensible_entity(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_extensible_attribute_schema(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_extensible_attribute_schema(jsonb) from public, anon, authenticated;
revoke all on function public.platform_validate_extensible_payload(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_extensible_join_profile(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_extensible_join_profile(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_extensible_template_descriptor(jsonb) from public, anon, authenticated;
revoke all on function public.platform_invalidate_extensible_schema_cache(jsonb) from public, anon, authenticated;

grant execute on function public.platform_validate_extensible_attribute_value(jsonb, jsonb) to service_role;
grant execute on function public.platform_register_extensible_entity(jsonb) to service_role;
grant execute on function public.platform_upsert_extensible_attribute_schema(jsonb) to service_role;
grant execute on function public.platform_register_extensible_join_profile(jsonb) to service_role;
grant execute on function public.platform_invalidate_extensible_schema_cache(jsonb) to service_role;
grant execute on function public.platform_get_extensible_attribute_schema(jsonb) to service_role;
grant execute on function public.platform_validate_extensible_payload(jsonb) to service_role;
grant execute on function public.platform_get_extensible_join_profile(jsonb) to service_role;
grant execute on function public.platform_get_extensible_template_descriptor(jsonb) to service_role;;
