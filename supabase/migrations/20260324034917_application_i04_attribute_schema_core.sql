create or replace function public.platform_upsert_extensible_attribute_schema(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entity_code text := lower(nullif(btrim(p_params->>'entity_code'), ''));
  v_tenant_id uuid := public.platform_try_uuid(p_params->>'tenant_id');
  v_attribute_code text := lower(nullif(btrim(p_params->>'attribute_code'), ''));
  v_ui_label text := nullif(btrim(p_params->>'ui_label'), '');
  v_data_type text := lower(nullif(btrim(p_params->>'data_type'), ''));
  v_is_required boolean := coalesce((p_params->>'is_required')::boolean, false);
  v_default_value jsonb := p_params->'default_value';
  v_validation_rules jsonb := coalesce(p_params->'validation_rules', '{}'::jsonb);
  v_sort_order integer := coalesce((p_params->>'sort_order')::integer, 100);
  v_attribute_status text := lower(coalesce(nullif(btrim(p_params->>'attribute_status'), ''), 'active'));
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_entity public.platform_extensible_entity_registry%rowtype;
  v_row public.platform_extensible_attribute_schema%rowtype;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Attribute-schema writes are restricted to internal callers.', '{}'::jsonb);
  end if;

  if v_entity_code is null then
    return public.platform_json_response(false, 'ENTITY_CODE_REQUIRED', 'entity_code is required.', '{}'::jsonb);
  end if;
  if v_attribute_code is null then
    return public.platform_json_response(false, 'ATTRIBUTE_CODE_REQUIRED', 'attribute_code is required.', '{}'::jsonb);
  end if;
  if v_ui_label is null then
    return public.platform_json_response(false, 'UI_LABEL_REQUIRED', 'ui_label is required.', '{}'::jsonb);
  end if;
  if v_data_type is null then
    return public.platform_json_response(false, 'DATA_TYPE_REQUIRED', 'data_type is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_validation_rules) <> 'object' then
    return public.platform_json_response(false, 'VALIDATION_RULES_INVALID', 'validation_rules must be a JSON object.', '{}'::jsonb);
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

  if v_tenant_id is not null and not v_entity.allow_tenant_override then
    return public.platform_json_response(false, 'TENANT_OVERRIDE_NOT_ALLOWED', 'This entity does not allow tenant-specific schema overrides.', jsonb_build_object('entity_code', v_entity_code));
  end if;

  insert into public.platform_extensible_attribute_schema (
    entity_id,
    tenant_id,
    attribute_code,
    ui_label,
    data_type,
    is_required,
    default_value,
    validation_rules,
    sort_order,
    attribute_status,
    metadata,
    created_by
  )
  values (
    v_entity.entity_id,
    v_tenant_id,
    v_attribute_code,
    v_ui_label,
    v_data_type,
    v_is_required,
    v_default_value,
    v_validation_rules,
    v_sort_order,
    v_attribute_status,
    v_metadata,
    v_actor_user_id
  )
  on conflict on constraint platform_extensible_attribute_schema_entity_scope_attribute_key do update
  set ui_label = excluded.ui_label,
      data_type = excluded.data_type,
      is_required = excluded.is_required,
      default_value = excluded.default_value,
      validation_rules = excluded.validation_rules,
      sort_order = excluded.sort_order,
      attribute_status = excluded.attribute_status,
      metadata = excluded.metadata,
      updated_at = timezone('utc', now())
  returning * into v_row;

  delete from public.platform_extensible_schema_cache
  where entity_id = v_entity.entity_id;

  return public.platform_json_response(true, 'OK', 'Extensible attribute schema upserted.', jsonb_build_object(
    'attribute_schema_id', v_row.attribute_schema_id,
    'entity_code', v_entity.entity_code,
    'tenant_id', v_row.tenant_id,
    'attribute_code', v_row.attribute_code,
    'data_type', v_row.data_type,
    'attribute_status', v_row.attribute_status
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_upsert_extensible_attribute_schema.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;

create or replace function public.platform_get_extensible_attribute_schema(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entity_code text := lower(nullif(btrim(p_params->>'entity_code'), ''));
  v_requested_tenant_id uuid := coalesce(public.platform_try_uuid(p_params->>'tenant_id'), public.platform_current_tenant_id());
  v_include_inactive boolean := coalesce((p_params->>'include_inactive')::boolean, false);
  v_use_cache boolean := coalesce((p_params->>'use_cache')::boolean, true);
  v_cache_ttl_seconds integer := greatest(coalesce((p_params->>'cache_ttl_seconds')::integer, 900), 60);
  v_entity public.platform_extensible_entity_registry%rowtype;
  v_cache public.platform_extensible_schema_cache%rowtype;
  v_descriptor jsonb;
  v_attributes jsonb;
begin
  if v_entity_code is null then
    return public.platform_json_response(false, 'ENTITY_CODE_REQUIRED', 'entity_code is required.', '{}'::jsonb);
  end if;

  select *
  into v_entity
  from public.platform_extensible_entity_registry
  where entity_code = v_entity_code
    and entity_status = 'active';

  if not found then
    return public.platform_json_response(false, 'ENTITY_NOT_FOUND', 'Active extensible entity not found.', jsonb_build_object('entity_code', v_entity_code));
  end if;

  if v_entity.tenant_scope = 'tenant' and v_requested_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_CONTEXT_REQUIRED', 'tenant_id is required for tenant-scoped entities.', jsonb_build_object('entity_code', v_entity_code));
  end if;

  if v_use_cache and not v_include_inactive then
    select *
    into v_cache
    from public.platform_extensible_schema_cache
    where entity_id = v_entity.entity_id
      and scope_tenant_key = coalesce(v_requested_tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and expires_at > timezone('utc', now())
    order by updated_at desc
    limit 1;

    if found then
      return public.platform_json_response(true, 'OK', 'Extensible schema resolved from cache.', v_cache.schema_descriptor);
    end if;
  end if;

  with ranked_attributes as (
    select
      pas.attribute_schema_id,
      pas.attribute_code,
      pas.ui_label,
      pas.data_type,
      pas.is_required,
      pas.default_value,
      pas.validation_rules,
      pas.sort_order,
      pas.attribute_status,
      pas.metadata,
      pas.tenant_id,
      row_number() over (
        partition by pas.attribute_code
        order by case when pas.tenant_id = v_requested_tenant_id then 0 else 1 end, pas.updated_at desc, pas.attribute_schema_id desc
      ) as rn
    from public.platform_extensible_attribute_schema pas
    where pas.entity_id = v_entity.entity_id
      and (pas.tenant_id is null or pas.tenant_id = v_requested_tenant_id)
      and (v_include_inactive or pas.attribute_status = 'active')
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'attribute_schema_id', ra.attribute_schema_id,
        'attribute_code', ra.attribute_code,
        'ui_label', ra.ui_label,
        'data_type', ra.data_type,
        'is_required', ra.is_required,
        'default_value', ra.default_value,
        'validation_rules', ra.validation_rules,
        'sort_order', ra.sort_order,
        'attribute_status', ra.attribute_status,
        'metadata', ra.metadata,
        'tenant_id', ra.tenant_id
      )
      order by ra.sort_order, ra.attribute_code
    ),
    '[]'::jsonb
  )
  into v_attributes
  from ranked_attributes ra
  where ra.rn = 1;

  v_descriptor := jsonb_build_object(
    'entity_id', v_entity.entity_id,
    'entity_code', v_entity.entity_code,
    'entity_label', v_entity.entity_label,
    'owner_module_code', v_entity.owner_module_code,
    'target_relation_schema', v_entity.target_relation_schema,
    'target_relation_name', v_entity.target_relation_name,
    'primary_key_column', v_entity.primary_key_column,
    'tenant_scope', v_entity.tenant_scope,
    'tenant_id', v_requested_tenant_id,
    'allow_tenant_override', v_entity.allow_tenant_override,
    'join_profile_enabled', v_entity.join_profile_enabled,
    'attributes', v_attributes
  );

  if not v_include_inactive then
    insert into public.platform_extensible_schema_cache (
      entity_id,
      tenant_id,
      schema_digest,
      schema_descriptor,
      expires_at
    )
    values (
      v_entity.entity_id,
      v_requested_tenant_id,
      md5(v_descriptor::text),
      v_descriptor,
      timezone('utc', now()) + make_interval(secs => v_cache_ttl_seconds)
    )
    on conflict on constraint platform_extensible_schema_cache_entity_scope_key do update
    set schema_digest = excluded.schema_digest,
        schema_descriptor = excluded.schema_descriptor,
        expires_at = excluded.expires_at,
        updated_at = timezone('utc', now());
  end if;

  return public.platform_json_response(true, 'OK', 'Extensible schema resolved.', v_descriptor);
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_get_extensible_attribute_schema.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;;
