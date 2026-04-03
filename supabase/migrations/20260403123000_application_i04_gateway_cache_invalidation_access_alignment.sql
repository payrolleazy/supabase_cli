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
  if v_entity_code is null then
    return public.platform_json_response(false, 'ENTITY_CODE_REQUIRED', 'entity_code is required.', '{}'::jsonb);
  end if;

  if not public.platform_is_internal_caller() and v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_CONTEXT_REQUIRED', 'tenant_id is required for non-internal schema-cache invalidation.', jsonb_build_object('entity_code', v_entity_code));
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