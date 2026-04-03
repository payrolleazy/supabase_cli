do $$
declare
  v_i04_entity_id uuid;
  v_i06_entity_id uuid;
begin
  insert into public.platform_extensible_entity_registry (
    entity_id,
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
    metadata
  ) values (
    '5cbf3d25-1f9a-47bd-8fad-6989a13a4ef7',
    'i04_proof_employee_extension',
    'I04 Proof Employee Extension',
    'i04_proof',
    'public',
    'i04_proof_entity',
    'entity_id',
    'tenant',
    true,
    true,
    'active',
    '{"purpose":"persistent_proof_seed"}'::jsonb
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
        metadata = excluded.metadata
  returning entity_id into v_i04_entity_id;

  insert into public.platform_extensible_entity_registry (
    entity_id,
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
    metadata
  ) values (
    'be0c5dde-5756-4b04-98cb-e8a48fea8152',
    'i06_proof_employee_extension',
    'I06 Proof Employee Extension',
    'i06_proof',
    'public',
    'i06_proof_entity',
    'entity_id',
    'tenant',
    true,
    true,
    'active',
    '{"purpose":"persistent_proof_seed"}'::jsonb
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
        metadata = excluded.metadata
  returning entity_id into v_i06_entity_id;

  insert into public.platform_extensible_attribute_schema (
    attribute_schema_id,
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
    metadata
  ) values
    (
      '2d6b0407-9612-4b6e-88ba-c1cb060be3ae',
      v_i04_entity_id,
      null,
      'custom_code',
      'Custom Code',
      'text',
      true,
      null,
      '{"max_length":20,"min_length":3}'::jsonb,
      10,
      'active',
      '{}'::jsonb
    ),
    (
      'ecf090c2-61a1-4a8f-9488-8475e932c6a9',
      v_i04_entity_id,
      null,
      'probation_days',
      'Probation Days',
      'integer',
      false,
      to_jsonb(90::int),
      '{"max":365,"min":0}'::jsonb,
      20,
      'active',
      '{}'::jsonb
    ),
    (
      'ad2d318d-2007-4c47-89ef-e60e702f31b0',
      v_i06_entity_id,
      null,
      'employee_code',
      'Employee Code',
      'text',
      true,
      null,
      '{"pattern":"^[A-Z0-9-]+$"}'::jsonb,
      10,
      'active',
      '{}'::jsonb
    ),
    (
      '37fdb6e6-f96e-4282-a1d4-8f0276d7bb9e',
      v_i06_entity_id,
      null,
      'full_name',
      'Full Name',
      'text',
      true,
      null,
      '{"min_length":3}'::jsonb,
      20,
      'active',
      '{}'::jsonb
    ),
    (
      '425af86c-e4dc-4e1f-824a-9ec94b2a09f7',
      v_i06_entity_id,
      null,
      'salary',
      'Salary',
      'numeric',
      false,
      null,
      '{"min":0}'::jsonb,
      30,
      'active',
      '{}'::jsonb
    ),
    (
      '1e58e6c7-ef3b-4851-aed6-f9f2a2516674',
      v_i06_entity_id,
      null,
      'start_date',
      'Start Date',
      'date',
      true,
      null,
      '{}'::jsonb,
      40,
      'active',
      '{}'::jsonb
    )
  on conflict (entity_id, scope_tenant_key, attribute_code) do update
    set ui_label = excluded.ui_label,
        data_type = excluded.data_type,
        is_required = excluded.is_required,
        default_value = excluded.default_value,
        validation_rules = excluded.validation_rules,
        sort_order = excluded.sort_order,
        attribute_status = excluded.attribute_status,
        metadata = excluded.metadata,
        tenant_id = excluded.tenant_id;

  insert into public.platform_extensible_join_profile (
    join_profile_id,
    entity_id,
    tenant_id,
    join_profile_code,
    profile_status,
    join_contract,
    projection_contract,
    metadata
  ) values
    (
      '6f905e34-5aef-4dc8-ae90-4519563e6382',
      v_i04_entity_id,
      null,
      'default_read_profile',
      'active',
      '{"joins":[],"base_relation":{"name":"wcm_employee","schema":"tenant"}}'::jsonb,
      '{"base_columns":["employee_id","employee_code"],"dynamic_attributes":["custom_code","probation_days"]}'::jsonb,
      '{}'::jsonb
    ),
    (
      'bf09d38d-5d21-499f-ae57-0b4253e8b115',
      v_i06_entity_id,
      null,
      'default_projection',
      'active',
      '{"joins":[],"base_relation":{"name":"wcm_employee","schema":"tenant"}}'::jsonb,
      '{"base_columns":["employee_id","employee_code"],"dynamic_attributes":["employee_code","full_name","salary","start_date"]}'::jsonb,
      '{}'::jsonb
    )
  on conflict (entity_id, scope_tenant_key, join_profile_code) do update
    set profile_status = excluded.profile_status,
        join_contract = excluded.join_contract,
        projection_contract = excluded.projection_contract,
        metadata = excluded.metadata,
        tenant_id = excluded.tenant_id;
end
$$;
