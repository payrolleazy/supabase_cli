create or replace function public.platform_register_extensible_entity(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entity_code text := lower(nullif(btrim(p_params->>'entity_code'), ''));
  v_entity_label text := nullif(btrim(p_params->>'entity_label'), '');
  v_owner_module_code text := lower(nullif(btrim(p_params->>'owner_module_code'), ''));
  v_target_relation_schema text := lower(coalesce(nullif(btrim(p_params->>'target_relation_schema'), ''), 'public'));
  v_target_relation_name text := lower(nullif(btrim(p_params->>'target_relation_name'), ''));
  v_primary_key_column text := lower(coalesce(nullif(btrim(p_params->>'primary_key_column'), ''), 'id'));
  v_tenant_scope text := lower(coalesce(nullif(btrim(p_params->>'tenant_scope'), ''), 'tenant'));
  v_allow_tenant_override boolean := coalesce((p_params->>'allow_tenant_override')::boolean, true);
  v_join_profile_enabled boolean := coalesce((p_params->>'join_profile_enabled')::boolean, false);
  v_entity_status text := lower(coalesce(nullif(btrim(p_params->>'entity_status'), ''), 'active'));
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_row public.platform_extensible_entity_registry%rowtype;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Entity registration is restricted to internal callers.', '{}'::jsonb);
  end if;

  if v_entity_code is null then
    return public.platform_json_response(false, 'ENTITY_CODE_REQUIRED', 'entity_code is required.', '{}'::jsonb);
  end if;
  if v_entity_label is null then
    return public.platform_json_response(false, 'ENTITY_LABEL_REQUIRED', 'entity_label is required.', '{}'::jsonb);
  end if;
  if v_owner_module_code is null then
    return public.platform_json_response(false, 'OWNER_MODULE_CODE_REQUIRED', 'owner_module_code is required.', '{}'::jsonb);
  end if;
  if v_target_relation_name is null then
    return public.platform_json_response(false, 'TARGET_RELATION_NAME_REQUIRED', 'target_relation_name is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'METADATA_INVALID', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  insert into public.platform_extensible_entity_registry (
    entity_code,
    entity_label,
    owner_module_code,
    target_relation_schema,
    target_relation_name,
    primary_key_column,
    tenant_scope,
    allow_tenant_override,
    join_profile_enabled,
    entity_status,
    metadata,
    created_by
  )
  values (
    v_entity_code,
    v_entity_label,
    v_owner_module_code,
    v_target_relation_schema,
    v_target_relation_name,
    v_primary_key_column,
    v_tenant_scope,
    v_allow_tenant_override,
    v_join_profile_enabled,
    v_entity_status,
    v_metadata,
    v_actor_user_id
  )
  on conflict (entity_code) do update
  set entity_label = excluded.entity_label,
      owner_module_code = excluded.owner_module_code,
      target_relation_schema = excluded.target_relation_schema,
      target_relation_name = excluded.target_relation_name,
      primary_key_column = excluded.primary_key_column,
      tenant_scope = excluded.tenant_scope,
      allow_tenant_override = excluded.allow_tenant_override,
      join_profile_enabled = excluded.join_profile_enabled,
      entity_status = excluded.entity_status,
      metadata = excluded.metadata,
      updated_at = timezone('utc', now())
  returning * into v_row;

  delete from public.platform_extensible_schema_cache
  where entity_id = v_row.entity_id;

  return public.platform_json_response(true, 'OK', 'Extensible entity registered.', jsonb_build_object(
    'entity_id', v_row.entity_id,
    'entity_code', v_row.entity_code,
    'entity_label', v_row.entity_label,
    'owner_module_code', v_row.owner_module_code,
    'tenant_scope', v_row.tenant_scope,
    'allow_tenant_override', v_row.allow_tenant_override,
    'join_profile_enabled', v_row.join_profile_enabled,
    'entity_status', v_row.entity_status
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_extensible_entity.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;;
