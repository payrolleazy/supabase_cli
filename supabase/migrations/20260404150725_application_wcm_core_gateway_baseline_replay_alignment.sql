do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'wcm_action_register_employee',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'binding_ref', 'platform_register_wcm_employee',
    'dispatch_config', '{}'::jsonb,
    'static_params', '{}'::jsonb,
    'request_contract', jsonb_build_object(
      'allowed_keys', jsonb_build_array('employee_id', 'employee_code', 'first_name', 'middle_name', 'last_name', 'official_email', 'employee_actor_user_id')
    ),
    'response_contract', '{}'::jsonb,
    'group_name', 'WCM Core',
    'synopsis', 'Create or update a WCM employee',
    'metadata', '{}'::jsonb
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_action_register_employee registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'wcm_action_register_employee',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_action_register_employee role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'wcm_action_upsert_service_state',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'required',
    'rate_limit_policy', 'default',
    'binding_ref', 'platform_upsert_wcm_service_state',
    'dispatch_config', '{}'::jsonb,
    'static_params', '{}'::jsonb,
    'request_contract', jsonb_build_object(
      'allowed_keys', jsonb_build_array('employee_id', 'joining_date', 'service_state', 'employment_status', 'confirmation_date', 'leaving_date', 'relief_date', 'separation_type', 'full_and_final_status', 'full_and_final_process_date', 'position_id', 'last_billable', 'state_notes', 'event_reason', 'source_module'),
      'required_keys', jsonb_build_array('employee_id')
    ),
    'response_contract', '{}'::jsonb,
    'group_name', 'WCM Core',
    'synopsis', 'Upsert WCM employee service state',
    'metadata', '{}'::jsonb
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_action_upsert_service_state registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'wcm_action_upsert_service_state',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_action_upsert_service_state role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'wcm_read_employee_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_wcm_employee_catalog',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('tenant_id', 'employee_id', 'employee_code', 'first_name', 'middle_name', 'last_name', 'official_email', 'actor_user_id', 'service_state', 'employment_status', 'joining_date', 'leaving_date', 'relief_date', 'full_and_final_status', 'current_billable', 'updated_at'),
      'filter_columns', jsonb_build_array('employee_id', 'employee_code', 'service_state', 'employment_status', 'current_billable'),
      'sort_columns', jsonb_build_array('employee_code', 'updated_at'),
      'tenant_column', 'tenant_id'
    ),
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'WCM Core',
    'synopsis', 'Read WCM employee catalog',
    'metadata', '{}'::jsonb
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_read_employee_catalog registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'wcm_read_employee_catalog',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_read_employee_catalog role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'wcm_read_headcount_summary',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'max_limit_per_request', 25,
    'binding_ref', 'platform_rm_wcm_headcount_summary',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('tenant_id', 'employee_count', 'active_employee_count', 'current_billable_count', 'inactive_employee_count', 'separated_employee_count'),
      'filter_columns', jsonb_build_array(),
      'sort_columns', jsonb_build_array(),
      'tenant_column', 'tenant_id'
    ),
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'WCM Core',
    'synopsis', 'Read WCM headcount summary',
    'metadata', '{}'::jsonb
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_read_headcount_summary registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'wcm_read_headcount_summary',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_read_headcount_summary role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'wcm_read_service_state_overview',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_wcm_service_state_overview',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('tenant_id', 'employee_id', 'employee_code', 'actor_user_id', 'service_state', 'employment_status', 'joining_date', 'confirmation_date', 'leaving_date', 'relief_date', 'separation_type', 'full_and_final_status', 'full_and_final_process_date', 'position_id', 'last_billable', 'current_billable', 'state_updated_at'),
      'filter_columns', jsonb_build_array('employee_id', 'employee_code', 'service_state', 'employment_status', 'current_billable'),
      'sort_columns', jsonb_build_array('employee_code', 'state_updated_at'),
      'tenant_column', 'tenant_id'
    ),
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'WCM Core',
    'synopsis', 'Read WCM service-state overview',
    'metadata', '{}'::jsonb
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_read_service_state_overview registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'wcm_read_service_state_overview',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_read_service_state_overview role assignment failed: %', v_result;
  end if;
end
$$;
