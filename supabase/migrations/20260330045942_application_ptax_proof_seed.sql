do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'ptax_read_configuration_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 100,
    'binding_ref', 'platform_rm_ptax_configuration_catalog',
    'group_name', 'PTAX',
    'synopsis', 'Read PTAX configuration catalog for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('configuration_id', 'state_code', 'effective_from', 'effective_to', 'deduction_frequency', 'configuration_status', 'configuration_version', 'updated_at'),
      'filter_columns', jsonb_build_array('configuration_id', 'state_code', 'effective_from', 'effective_to', 'deduction_frequency', 'configuration_status'),
      'sort_columns', jsonb_build_array('state_code', 'effective_from', 'configuration_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_read_configuration_catalog registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'ptax_read_configuration_catalog', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_read_configuration_catalog role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'ptax_read_batch_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_ptax_batch_catalog',
    'group_name', 'PTAX',
    'synopsis', 'Read PTAX monthly batch catalog for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('batch_id', 'state_code', 'payroll_period', 'batch_status', 'processed_count', 'synced_count', 'skipped_count', 'error_count', 'updated_at'),
      'filter_columns', jsonb_build_array('batch_id', 'state_code', 'payroll_period', 'batch_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'updated_at', 'batch_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_read_batch_catalog registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'ptax_read_batch_catalog', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_read_batch_catalog role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'ptax_read_contribution_ledger',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 500,
    'binding_ref', 'platform_rm_ptax_contribution_ledger',
    'group_name', 'PTAX',
    'synopsis', 'Read PTAX monthly contribution ledger rows for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('contribution_ledger_id', 'batch_id', 'employee_id', 'employee_code', 'payroll_period', 'state_code', 'taxable_wages', 'deduction_amount', 'sync_status'),
      'filter_columns', jsonb_build_array('contribution_ledger_id', 'batch_id', 'employee_id', 'employee_code', 'payroll_period', 'state_code', 'sync_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'employee_code', 'contribution_ledger_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_read_contribution_ledger registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'ptax_read_contribution_ledger', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_read_contribution_ledger role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'ptax_read_arrear_queue',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_ptax_arrear_queue',
    'group_name', 'PTAX',
    'synopsis', 'Read PTAX arrear queue and recomputation status for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('arrear_case_id', 'employee_id', 'employee_code', 'state_code', 'from_period', 'to_period', 'arrear_status', 'target_payroll_period', 'total_delta', 'updated_at'),
      'filter_columns', jsonb_build_array('arrear_case_id', 'employee_id', 'employee_code', 'state_code', 'from_period', 'to_period', 'arrear_status', 'target_payroll_period'),
      'sort_columns', jsonb_build_array('updated_at', 'employee_code', 'arrear_case_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_read_arrear_queue registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'ptax_read_arrear_queue', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_read_arrear_queue role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'ptax_action_manage_configuration',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_upsert_ptax_configuration',
    'group_name', 'PTAX',
    'synopsis', 'Create or update a PTAX state configuration window',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('state_code', 'effective_from', 'slabs'),
      'allowed_keys', jsonb_build_array('state_code', 'effective_from', 'effective_to', 'slabs', 'deduction_frequency', 'frequency_months', 'configuration_status', 'configuration_version', 'statutory_reference', 'version_notes', 'config_metadata', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_manage_configuration registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'ptax_action_manage_configuration', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_manage_configuration role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'ptax_action_manage_employee_state_profile',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_upsert_ptax_employee_state_profile',
    'group_name', 'PTAX',
    'synopsis', 'Create or update the clean PTAX employee-state profile used for monthly and arrear computation',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('employee_id', 'state_code', 'effective_from'),
      'allowed_keys', jsonb_build_array('employee_id', 'state_code', 'resident_state_code', 'work_state_code', 'source_kind', 'effective_from', 'effective_to', 'profile_status', 'notes', 'profile_metadata', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_manage_employee_state_profile registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'ptax_action_manage_employee_state_profile', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_manage_employee_state_profile role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'ptax_action_manage_wage_component_mapping',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_upsert_ptax_wage_component_mapping',
    'group_name', 'PTAX',
    'synopsis', 'Create or update PTAX wage-component eligibility mapping for a state',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('state_code', 'component_code', 'effective_from'),
      'allowed_keys', jsonb_build_array('state_code', 'component_code', 'is_ptax_eligible', 'effective_from', 'effective_to', 'mapping_metadata', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_manage_wage_component_mapping registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'ptax_action_manage_wage_component_mapping', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_manage_wage_component_mapping role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'ptax_action_request_batch',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_request_ptax_batch',
    'group_name', 'PTAX',
    'synopsis', 'Request a PTAX monthly computation batch on the shared async spine',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('state_code', 'payroll_period'),
      'allowed_keys', jsonb_build_array('state_code', 'payroll_period', 'employee_ids', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_request_batch registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'ptax_action_request_batch', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_request_batch role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'ptax_action_request_retry_batch',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_request_ptax_retry_batch',
    'group_name', 'PTAX',
    'synopsis', 'Reset a failed PTAX monthly batch for retry on the shared async spine',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('batch_id'),
      'allowed_keys', jsonb_build_array('batch_id', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_request_retry_batch registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'ptax_action_request_retry_batch', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_request_retry_batch role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'ptax_action_record_arrear_case',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_record_ptax_arrear_case',
    'group_name', 'PTAX',
    'synopsis', 'Record a PTAX arrear case for later review and month-level recomputation',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('employee_id', 'state_code', 'from_period', 'to_period'),
      'allowed_keys', jsonb_build_array('employee_id', 'state_code', 'from_period', 'to_period', 'revised_state_code', 'override_amount', 'arrear_status', 'review_notes', 'target_payroll_period', 'case_metadata', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_record_arrear_case registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'ptax_action_record_arrear_case', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_record_arrear_case role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'ptax_action_review_arrear',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_review_ptax_arrear',
    'group_name', 'PTAX',
    'synopsis', 'Approve, reject, or cancel a PTAX arrear case before worker-side settlement',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('arrear_case_id', 'action'),
      'allowed_keys', jsonb_build_array('arrear_case_id', 'action', 'override_amount', 'review_notes', 'target_payroll_period', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_review_arrear registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'ptax_action_review_arrear', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ptax_action_review_arrear role assignment failed: %', v_result::text; end if;
end;
$$;;
