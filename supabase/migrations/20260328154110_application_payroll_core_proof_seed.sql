do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_read_area_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 25,
    'binding_ref', 'platform_rm_payroll_area_catalog',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Read payroll areas for tenant payroll administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'payroll_area_id', 'area_code', 'area_name', 'payroll_frequency',
        'currency_code', 'country_code', 'area_status', 'area_metadata',
        'created_at', 'updated_at'
      ),
      'filter_columns', jsonb_build_array('payroll_area_id', 'area_code', 'area_name', 'payroll_frequency', 'area_status', 'country_code'),
      'sort_columns', jsonb_build_array('area_code', 'updated_at', 'payroll_area_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_area_catalog registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_read_area_catalog', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_area_catalog role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_read_structure_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 100,
    'binding_ref', 'platform_rm_pay_structure_catalog',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Read pay-structure catalog for tenant payroll administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'pay_structure_id', 'payroll_area_id', 'structure_code', 'structure_name',
        'structure_status', 'active_version_no', 'component_count',
        'effective_from', 'effective_to', 'updated_at'
      ),
      'filter_columns', jsonb_build_array('pay_structure_id', 'payroll_area_id', 'structure_code', 'structure_status', 'active_version_no'),
      'sort_columns', jsonb_build_array('structure_code', 'updated_at', 'pay_structure_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_structure_catalog registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_read_structure_catalog', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_structure_catalog role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_read_employee_structure_assignment',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_employee_pay_structure_assignment',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Read employee pay-structure assignments for tenant payroll administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'employee_pay_structure_assignment_id', 'employee_id', 'employee_code',
        'employee_name', 'pay_structure_id', 'structure_code',
        'pay_structure_version_id', 'effective_from', 'effective_to',
        'assignment_status', 'updated_at'
      ),
      'filter_columns', jsonb_build_array('employee_pay_structure_assignment_id', 'employee_id', 'employee_code', 'pay_structure_id', 'structure_code', 'assignment_status'),
      'sort_columns', jsonb_build_array('effective_from', 'employee_code', 'updated_at')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_employee_structure_assignment registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_read_employee_structure_assignment', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_employee_structure_assignment role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_read_batch_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 120,
    'binding_ref', 'platform_rm_payroll_batch_catalog',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Read payroll batches for tenant payroll administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'payroll_batch_id', 'payroll_period', 'processing_type', 'batch_status',
        'total_employees', 'processed_employees', 'failed_employees',
        'gross_earnings', 'total_deductions', 'net_pay',
        'processed_at', 'finalized_at', 'last_error', 'updated_at'
      ),
      'filter_columns', jsonb_build_array('payroll_batch_id', 'payroll_period', 'processing_type', 'batch_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'updated_at', 'payroll_batch_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_batch_catalog registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_read_batch_catalog', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_batch_catalog role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_read_result_summary',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 500,
    'binding_ref', 'platform_rm_payroll_result_summary',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Read employee payroll result summaries for tenant payroll administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'payroll_batch_id', 'payroll_period', 'employee_id', 'employee_code',
        'gross_earnings', 'total_deductions', 'employer_contributions',
        'net_pay', 'batch_status', 'updated_at'
      ),
      'filter_columns', jsonb_build_array('payroll_batch_id', 'payroll_period', 'employee_id', 'employee_code', 'batch_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'employee_code', 'updated_at')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_result_summary registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_read_result_summary', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_result_summary role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_read_employee_payslip_history',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 500,
    'binding_ref', 'platform_rm_employee_payslip_history',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Read employee payslip history for tenant payroll administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'payslip_run_id', 'payslip_item_id', 'payroll_period', 'employee_id',
        'employee_code', 'item_status', 'artifact_status',
        'generated_document_id', 'completed_at', 'updated_at'
      ),
      'filter_columns', jsonb_build_array('payslip_run_id', 'payslip_item_id', 'payroll_period', 'employee_id', 'employee_code', 'item_status', 'artifact_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'employee_code', 'updated_at')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_employee_payslip_history registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_read_employee_payslip_history', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_employee_payslip_history role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_read_payslip_run_status',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 120,
    'binding_ref', 'platform_rm_payslip_run_status',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Read payslip run status for tenant payroll administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'payslip_run_id', 'payroll_batch_id', 'payroll_period', 'run_status',
        'total_items', 'completed_items', 'failed_items', 'dead_letter_items',
        'completed_at', 'updated_at'
      ),
      'filter_columns', jsonb_build_array('payslip_run_id', 'payroll_batch_id', 'payroll_period', 'run_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'updated_at', 'payslip_run_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_payslip_run_status registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_read_payslip_run_status', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_read_payslip_run_status role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_manage_area',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_register_payroll_area',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Create or update a payroll area',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('area_code', 'area_name'),
      'allowed_keys', jsonb_build_array('area_code', 'area_name', 'payroll_frequency', 'currency_code', 'country_code', 'area_status', 'area_metadata')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_manage_area registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_manage_area', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_manage_area role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_manage_component',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_register_payroll_component',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Create or update a payroll component',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('component_code', 'component_name'),
      'allowed_keys', jsonb_build_array('component_code', 'component_name', 'component_kind', 'calculation_method', 'payslip_label', 'is_taxable', 'is_proratable', 'display_order', 'component_status', 'default_rule_definition', 'component_metadata')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_manage_component registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_manage_component', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_manage_component role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_manage_component_dependency',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_register_component_dependency',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Create or update a payroll component dependency',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('component_id', 'depends_on_component_id'),
      'allowed_keys', jsonb_build_array('component_id', 'depends_on_component_id', 'dependency_kind', 'dependency_metadata')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_manage_component_dependency registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_manage_component_dependency', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_manage_component_dependency role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_manage_component_rule_template',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_register_component_rule_template',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Create or update a payroll component rule template',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('template_code', 'template_name', 'component_id'),
      'allowed_keys', jsonb_build_array('template_code', 'template_name', 'component_id', 'template_status', 'rule_definition', 'template_metadata')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_manage_component_rule_template registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_manage_component_rule_template', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_manage_component_rule_template role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_manage_pay_structure',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_register_pay_structure',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Create or update a pay structure',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('payroll_area_id', 'structure_code', 'structure_name'),
      'allowed_keys', jsonb_build_array('payroll_area_id', 'structure_code', 'structure_name', 'structure_status', 'effective_from', 'effective_to', 'structure_metadata')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_manage_pay_structure registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_manage_pay_structure', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_manage_pay_structure role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_upsert_pay_structure_component',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_upsert_pay_structure_component',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Add or update a component inside a pay structure',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('pay_structure_id', 'component_id'),
      'allowed_keys', jsonb_build_array('pay_structure_id', 'component_id', 'display_order', 'component_status', 'staged_rule_definition', 'eligibility_rule_definition')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_upsert_pay_structure_component registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_upsert_pay_structure_component', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_upsert_pay_structure_component role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_validate_pay_structure',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_validate_pay_structure',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Validate the active staged definition of a pay structure',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('pay_structure_id'),
      'allowed_keys', jsonb_build_array('pay_structure_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_validate_pay_structure registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_validate_pay_structure', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_validate_pay_structure role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_activate_pay_structure',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_activate_pay_structure',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Activate a validated pay structure and create a new active version',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('pay_structure_id'),
      'allowed_keys', jsonb_build_array('pay_structure_id', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_activate_pay_structure registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_activate_pay_structure', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_activate_pay_structure role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_assign_employee_pay_structure',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_assign_employee_pay_structure',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Assign an active pay structure to an employee',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('employee_id', 'pay_structure_id', 'effective_from'),
      'allowed_keys', jsonb_build_array('employee_id', 'pay_structure_id', 'pay_structure_version_id', 'effective_from', 'effective_to', 'override_inputs', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_assign_employee_pay_structure registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_assign_employee_pay_structure', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_assign_employee_pay_structure role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_get_employee_pay_structure_components',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_get_employee_pay_structure_components',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Resolve active pay-structure components for an employee',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('employee_id'),
      'allowed_keys', jsonb_build_array('employee_id', 'effective_on')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_get_employee_pay_structure_components registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_get_employee_pay_structure_components', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_get_employee_pay_structure_components role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_upsert_input_entry',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_upsert_payroll_input_entry',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Create or update a payroll input entry',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('employee_id', 'payroll_period', 'component_code'),
      'allowed_keys', jsonb_build_array('employee_id', 'payroll_period', 'component_code', 'input_source', 'source_record_id', 'source_batch_id', 'numeric_value', 'text_value', 'json_value', 'source_metadata', 'input_status')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_upsert_input_entry registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_upsert_input_entry', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_upsert_input_entry role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_request_batch',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_request_payroll_batch',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Queue a payroll batch for shared-async processing',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('payroll_period', 'payroll_area_id'),
      'allowed_keys', jsonb_build_array('payroll_period', 'payroll_area_id', 'processing_type', 'request_scope', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_request_batch registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_request_batch', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_request_batch role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_get_batch_status',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_get_payroll_batch_status',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Resolve detailed payroll batch status',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('payroll_batch_id'),
      'allowed_keys', jsonb_build_array('payroll_batch_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_get_batch_status registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_get_batch_status', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_get_batch_status role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_finalize_batch',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_finalize_payroll_batch',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Finalize a processed payroll batch',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('payroll_batch_id'),
      'allowed_keys', jsonb_build_array('payroll_batch_id', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_finalize_batch registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_finalize_batch', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_finalize_batch role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_request_preview',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_request_payroll_preview',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Queue a payroll preview simulation',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('employee_id', 'payroll_period'),
      'allowed_keys', jsonb_build_array('employee_id', 'payroll_period', 'pay_structure_id', 'request_payload', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_request_preview registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_request_preview', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_request_preview role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_get_preview_result',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_get_payroll_preview',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Resolve a queued or completed payroll preview result',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('preview_simulation_id'),
      'allowed_keys', jsonb_build_array('preview_simulation_id', 'employee_id', 'payroll_period')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_get_preview_result registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_get_preview_result', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_get_preview_result role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_request_payslip_run',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_request_payslip_run',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Queue a payslip-generation run for a finalized payroll batch',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('payroll_batch_id'),
      'allowed_keys', jsonb_build_array('payroll_batch_id', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_request_payslip_run registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_request_payslip_run', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_request_payslip_run role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'payroll_action_get_employee_payslip',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_get_employee_payslip',
    'group_name', 'PAYROLL_CORE',
    'synopsis', 'Resolve the latest or period-specific employee payslip payload',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('employee_id'),
      'allowed_keys', jsonb_build_array('employee_id', 'payroll_period')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_get_employee_payslip registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'payroll_action_get_employee_payslip', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'payroll_action_get_employee_payslip role assignment failed: %', v_result::text; end if;
end;
$$;;
