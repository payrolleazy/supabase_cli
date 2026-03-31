do $$
declare
  v_result jsonb;
  v_can_assign_roles boolean := to_regclass('public.platform_access_role') is not null;
begin
  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'i03_proof_read_actor_access',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'max_limit_per_request', 25,
    'binding_ref', 'platform_rm_actor_access_overview',
    'group_name', 'I03 Proof',
    'synopsis', 'Read actor access overview',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('actor_user_id', 'tenant_id', 'tenant_code', 'profile_status', 'active_role_codes'),
      'filter_columns', jsonb_build_array('actor_user_id'),
      'sort_columns', jsonb_build_array('tenant_code'),
      'tenant_column', 'tenant_id',
      'actor_column', 'actor_user_id'
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) = false then
    raise exception 'Read operation registration failed: %', v_result::text;
  end if;

  if v_can_assign_roles and exists (select 1 from public.platform_access_role where role_code = 'i01_portal_user') then
    v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
      'operation_code', 'i03_proof_read_actor_access',
      'role_code', 'i01_portal_user'
    ));
    if coalesce((v_result->>'success')::boolean, false) = false then
      raise exception 'Read operation role assignment failed: %', v_result::text;
    end if;
  end if;

  if v_can_assign_roles and exists (select 1 from public.platform_access_role where role_code = 'tenant_owner_admin') then
    v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
      'operation_code', 'i03_proof_read_actor_access',
      'role_code', 'tenant_owner_admin'
    ));
    if coalesce((v_result->>'success')::boolean, false) = false then
      raise exception 'Read owner role assignment failed: %', v_result::text;
    end if;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'i03_proof_action_actor_access_context',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'idempotency_policy', 'required',
    'binding_ref', 'platform_get_actor_access_context',
    'group_name', 'I03 Proof',
    'synopsis', 'Get actor access context',
    'request_contract', jsonb_build_object('allowed_keys', jsonb_build_array('actor_user_id'))
  ));
  if coalesce((v_result->>'success')::boolean, false) = false then
    raise exception 'Action operation registration failed: %', v_result::text;
  end if;

  if v_can_assign_roles and exists (select 1 from public.platform_access_role where role_code = 'i01_portal_user') then
    v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
      'operation_code', 'i03_proof_action_actor_access_context',
      'role_code', 'i01_portal_user'
    ));
    if coalesce((v_result->>'success')::boolean, false) = false then
      raise exception 'Action operation role assignment failed: %', v_result::text;
    end if;
  end if;

  if v_can_assign_roles and exists (select 1 from public.platform_access_role where role_code = 'tenant_owner_admin') then
    v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
      'operation_code', 'i03_proof_action_actor_access_context',
      'role_code', 'tenant_owner_admin'
    ));
    if coalesce((v_result->>'success')::boolean, false) = false then
      raise exception 'Action owner role assignment failed: %', v_result::text;
    end if;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'i03_proof_mutate_operation_metadata',
    'operation_mode', 'mutate',
    'dispatch_kind', 'mutation_adapter',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'idempotency_policy', 'required',
    'binding_ref', 'platform_update_gateway_operation_metadata',
    'group_name', 'I03 Proof',
    'synopsis', 'Mutate gateway operation metadata',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('target_operation_code', 'metadata_patch'),
      'allowed_keys', jsonb_build_array('target_operation_code', 'metadata_patch')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) = false then
    raise exception 'Mutation operation registration failed: %', v_result::text;
  end if;

  if v_can_assign_roles and exists (select 1 from public.platform_access_role where role_code = 'tenant_owner_admin') then
    v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
      'operation_code', 'i03_proof_mutate_operation_metadata',
      'role_code', 'tenant_owner_admin'
    ));
    if coalesce((v_result->>'success')::boolean, false) = false then
      raise exception 'Mutation operation role assignment failed: %', v_result::text;
    end if;
  end if;
end $$;
