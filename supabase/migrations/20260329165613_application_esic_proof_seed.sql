do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_read_configuration_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 100,
    'binding_ref', 'platform_rm_esic_configuration_catalog',
    'group_name', 'ESIC',
    'synopsis', 'Read ESIC configuration catalog for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('configuration_id', 'state_code', 'effective_from', 'effective_to', 'wage_ceiling', 'employee_contribution_rate', 'employer_contribution_rate', 'configuration_status', 'updated_at'),
      'filter_columns', jsonb_build_array('configuration_id', 'state_code', 'effective_from', 'effective_to', 'configuration_status'),
      'sort_columns', jsonb_build_array('state_code', 'effective_from', 'configuration_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_configuration_catalog registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_read_configuration_catalog', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_configuration_catalog role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_read_establishment_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 150,
    'binding_ref', 'platform_rm_esic_establishment_catalog',
    'group_name', 'ESIC',
    'synopsis', 'Read ESIC establishment catalog for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('establishment_id', 'establishment_code', 'establishment_name', 'registration_code', 'state_code', 'establishment_status', 'coverage_start_date', 'updated_at'),
      'filter_columns', jsonb_build_array('establishment_id', 'establishment_code', 'establishment_name', 'registration_code', 'state_code', 'establishment_status'),
      'sort_columns', jsonb_build_array('establishment_code', 'establishment_name', 'establishment_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_establishment_catalog registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_read_establishment_catalog', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_establishment_catalog role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_read_registration_status',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_esic_registration_status',
    'group_name', 'ESIC',
    'synopsis', 'Read ESIC employee registration status for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('registration_id', 'employee_id', 'employee_code', 'establishment_id', 'establishment_code', 'ip_number', 'registration_status', 'registration_date', 'updated_at'),
      'filter_columns', jsonb_build_array('registration_id', 'employee_id', 'employee_code', 'establishment_id', 'establishment_code', 'ip_number', 'registration_status'),
      'sort_columns', jsonb_build_array('registration_date', 'employee_code', 'registration_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_registration_status registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_read_registration_status', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_registration_status role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_read_benefit_period_status',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_esic_benefit_period_status',
    'group_name', 'ESIC',
    'synopsis', 'Read ESIC benefit-period status for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('benefit_period_id', 'employee_id', 'employee_code', 'contribution_period_start', 'contribution_period_end', 'benefit_period_start', 'benefit_period_end', 'total_days_worked', 'total_wages_paid', 'is_eligible', 'updated_at'),
      'filter_columns', jsonb_build_array('benefit_period_id', 'employee_id', 'employee_code', 'contribution_period_start', 'benefit_period_start', 'is_eligible'),
      'sort_columns', jsonb_build_array('contribution_period_start', 'employee_code', 'benefit_period_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_benefit_period_status registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_read_benefit_period_status', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_benefit_period_status role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_read_batch_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_esic_batch_catalog',
    'group_name', 'ESIC',
    'synopsis', 'Read ESIC monthly batch catalog for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('batch_id', 'establishment_id', 'establishment_code', 'payroll_period', 'return_period', 'batch_status', 'worker_job_id', 'updated_at'),
      'filter_columns', jsonb_build_array('batch_id', 'establishment_id', 'establishment_code', 'payroll_period', 'return_period', 'batch_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'batch_id', 'updated_at')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_batch_catalog registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_read_batch_catalog', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_batch_catalog role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_read_challan_run_status',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 200,
    'binding_ref', 'platform_rm_esic_challan_run_status',
    'group_name', 'ESIC',
    'synopsis', 'Read ESIC challan generation and reconciliation status for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('challan_run_id', 'batch_id', 'payroll_period', 'return_period', 'run_status', 'reconciliation_status', 'total_contribution', 'payment_amount', 'discrepancy_amount', 'updated_at'),
      'filter_columns', jsonb_build_array('challan_run_id', 'batch_id', 'payroll_period', 'return_period', 'run_status', 'reconciliation_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'updated_at', 'challan_run_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_challan_run_status registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_read_challan_run_status', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_challan_run_status role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_read_contribution_ledger',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 500,
    'binding_ref', 'platform_rm_esic_contribution_ledger',
    'group_name', 'ESIC',
    'synopsis', 'Read ESIC contribution ledger rows for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('contribution_ledger_id', 'batch_id', 'employee_id', 'employee_code', 'payroll_period', 'eligible_wages', 'employee_contribution', 'employer_contribution', 'total_contribution', 'sync_status'),
      'filter_columns', jsonb_build_array('contribution_ledger_id', 'batch_id', 'employee_id', 'employee_code', 'payroll_period', 'sync_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'employee_code', 'contribution_ledger_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_contribution_ledger registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_read_contribution_ledger', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_read_contribution_ledger role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_action_manage_configuration',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_upsert_esic_configuration',
    'group_name', 'ESIC',
    'synopsis', 'Create or update an ESIC configuration window',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('state_code'),
      'allowed_keys', jsonb_build_array('state_code', 'effective_from', 'effective_to', 'wage_ceiling', 'employee_contribution_rate', 'employer_contribution_rate', 'configuration_status', 'statutory_reference', 'version_notes', 'config_metadata', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_manage_configuration registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_action_manage_configuration', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_manage_configuration role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_action_manage_establishment',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_register_esic_establishment',
    'group_name', 'ESIC',
    'synopsis', 'Create or update an ESIC establishment profile',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('establishment_code', 'establishment_name', 'registration_code', 'state_code'),
      'allowed_keys', jsonb_build_array('establishment_code', 'establishment_name', 'registration_code', 'state_code', 'address_payload', 'contact_person', 'contact_email', 'contact_phone', 'registration_date', 'coverage_start_date', 'establishment_status', 'establishment_metadata', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_manage_establishment registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_action_manage_establishment', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_manage_establishment role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_action_manage_employee_registration',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_register_esic_employee_registration',
    'group_name', 'ESIC',
    'synopsis', 'Create or update an ESIC employee registration',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('employee_id', 'establishment_id'),
      'allowed_keys', jsonb_build_array('employee_id', 'establishment_id', 'ip_number', 'registration_date', 'effective_from', 'effective_to', 'exit_date', 'wage_basis_override', 'registration_status', 'exemption_reason', 'nominee_details', 'family_details', 'registration_metadata', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_manage_employee_registration registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_action_manage_employee_registration', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_manage_employee_registration role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_action_manage_wage_component_mapping',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_upsert_esic_wage_component_mapping',
    'group_name', 'ESIC',
    'synopsis', 'Create or update an ESIC wage-component mapping',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('component_code'),
      'allowed_keys', jsonb_build_array('component_code', 'is_esic_eligible', 'component_category', 'inclusion_reason', 'effective_from', 'effective_to', 'mapping_metadata', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_manage_wage_component_mapping registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_action_manage_wage_component_mapping', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_manage_wage_component_mapping role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_action_request_batch',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_request_esic_batch',
    'group_name', 'ESIC',
    'synopsis', 'Request an ESIC monthly computation batch on the shared async spine',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('establishment_id'),
      'allowed_keys', jsonb_build_array('establishment_id', 'payroll_period', 'source', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_request_batch registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_action_request_batch', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_request_batch role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_action_request_challan_run',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_request_esic_challan_run',
    'group_name', 'ESIC',
    'synopsis', 'Request ESIC challan generation for a synced batch',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('batch_id'),
      'allowed_keys', jsonb_build_array('batch_id', 'source', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_request_challan_run registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_action_request_challan_run', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_request_challan_run role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'esic_action_reconcile_payment',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_reconcile_esic_payment',
    'group_name', 'ESIC',
    'synopsis', 'Reconcile an ESIC challan payment against the generated liability',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('challan_run_id', 'payment_amount'),
      'allowed_keys', jsonb_build_array('challan_run_id', 'payment_amount', 'payment_date', 'payment_reference', 'submission_reference', 'payment_proof_document_id', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_reconcile_payment registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'esic_action_reconcile_payment', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'esic_action_reconcile_payment role assignment failed: %', v_result::text; end if;
end;
$$;;
