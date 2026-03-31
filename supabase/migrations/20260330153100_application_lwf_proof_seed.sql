
do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'lwf_read_configuration_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 100,
    'binding_ref', 'platform_rm_lwf_configuration_catalog',
    'group_name', 'LWF',
    'synopsis', 'Read LWF configuration catalog for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('configuration_id', 'state_code', 'effective_from', 'effective_to', 'deduction_frequency', 'configuration_status', 'configuration_version', 'updated_at'),
      'filter_columns', jsonb_build_array('configuration_id', 'state_code', 'effective_from', 'effective_to', 'deduction_frequency', 'configuration_status'),
      'sort_columns', jsonb_build_array('state_code', 'effective_from', 'configuration_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_read_configuration_catalog registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'lwf_read_configuration_catalog', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_read_configuration_catalog role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'lwf_read_batch_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_lwf_batch_catalog',
    'group_name', 'LWF',
    'synopsis', 'Read LWF period batch catalog for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('batch_id', 'state_code', 'payroll_period', 'batch_source', 'batch_status', 'requested_count', 'processed_count', 'synced_count', 'error_count', 'updated_at'),
      'filter_columns', jsonb_build_array('batch_id', 'state_code', 'payroll_period', 'batch_source', 'batch_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'updated_at', 'batch_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_read_batch_catalog registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'lwf_read_batch_catalog', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_read_batch_catalog role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'lwf_read_contribution_ledger',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 500,
    'binding_ref', 'platform_rm_lwf_contribution_ledger',
    'group_name', 'LWF',
    'synopsis', 'Read LWF contribution ledger rows for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('contribution_ledger_id', 'batch_id', 'employee_id', 'employee_code', 'payroll_period', 'state_code', 'eligible_wages', 'final_employee_contribution', 'final_employer_contribution', 'override_status', 'sync_status'),
      'filter_columns', jsonb_build_array('contribution_ledger_id', 'batch_id', 'employee_id', 'employee_code', 'payroll_period', 'state_code', 'override_status', 'sync_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'employee_code', 'contribution_ledger_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_read_contribution_ledger registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'lwf_read_contribution_ledger', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_read_contribution_ledger role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'lwf_read_dead_letter_queue',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_lwf_dead_letter_queue',
    'group_name', 'LWF',
    'synopsis', 'Read LWF dead-letter queue for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('dead_letter_id', 'batch_id', 'employee_id', 'employee_code', 'error_code', 'resolution_status', 'created_at'),
      'filter_columns', jsonb_build_array('dead_letter_id', 'batch_id', 'employee_id', 'employee_code', 'error_code', 'resolution_status'),
      'sort_columns', jsonb_build_array('created_at', 'dead_letter_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_read_dead_letter_queue registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'lwf_read_dead_letter_queue', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_read_dead_letter_queue role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'lwf_read_compliance_summary',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_lwf_compliance_summary',
    'group_name', 'LWF',
    'synopsis', 'Read LWF compliance summary read model for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('summary_id', 'state_code', 'payroll_period', 'total_employees', 'overridden_count', 'synced_count', 'total_eligible_wages', 'total_employee_contribution', 'total_employer_contribution', 'total_liability', 'refreshed_at'),
      'filter_columns', jsonb_build_array('summary_id', 'state_code', 'payroll_period'),
      'sort_columns', jsonb_build_array('payroll_period', 'state_code', 'summary_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_read_compliance_summary registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'lwf_read_compliance_summary', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_read_compliance_summary role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'lwf_action_manage_configuration',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_upsert_lwf_configuration',
    'group_name', 'LWF',
    'synopsis', 'Create or update an LWF state configuration window',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('state_code', 'effective_from', 'contribution_rules'),
      'allowed_keys', jsonb_build_array('state_code', 'effective_from', 'effective_to', 'deduction_frequency', 'deduction_months', 'contribution_rules', 'configuration_status', 'configuration_version', 'statutory_reference', 'configuration_metadata', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_manage_configuration registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'lwf_action_manage_configuration', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_manage_configuration role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'lwf_action_manage_wage_component_mapping',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_upsert_lwf_wage_component_mapping',
    'group_name', 'LWF',
    'synopsis', 'Create or update LWF wage-component eligibility mapping for a state',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('state_code', 'component_code', 'effective_from'),
      'allowed_keys', jsonb_build_array('state_code', 'component_code', 'is_lwf_eligible', 'effective_from', 'effective_to', 'mapping_metadata', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_manage_wage_component_mapping registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'lwf_action_manage_wage_component_mapping', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_manage_wage_component_mapping role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'lwf_action_request_batch',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_request_lwf_batch',
    'group_name', 'LWF',
    'synopsis', 'Request an LWF period batch on the shared async spine',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('state_code', 'payroll_period'),
      'allowed_keys', jsonb_build_array('state_code', 'payroll_period', 'batch_source', 'source_batch_id', 'source_batch_ref', 'requested_employee_ids', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_request_batch registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'lwf_action_request_batch', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_request_batch role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'lwf_action_schedule_from_payroll',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_schedule_lwf_from_payroll',
    'group_name', 'LWF',
    'synopsis', 'Schedule state-aware LWF batches from a processed payroll batch',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('source_batch_id'),
      'allowed_keys', jsonb_build_array('source_batch_id', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_schedule_from_payroll registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'lwf_action_schedule_from_payroll', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_schedule_from_payroll role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'lwf_action_request_retry_batch',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_request_lwf_retry_batch',
    'group_name', 'LWF',
    'synopsis', 'Reset a failed or cancelled LWF batch for retry on the shared async spine',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('batch_id'),
      'allowed_keys', jsonb_build_array('batch_id', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_request_retry_batch registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'lwf_action_request_retry_batch', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_request_retry_batch role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'lwf_action_cancel_batch',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_cancel_lwf_batch',
    'group_name', 'LWF',
    'synopsis', 'Cancel a pending or failed LWF batch',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('batch_id'),
      'allowed_keys', jsonb_build_array('batch_id', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_cancel_batch registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'lwf_action_cancel_batch', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_cancel_batch role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'lwf_action_apply_override',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_apply_lwf_override',
    'group_name', 'LWF',
    'synopsis', 'Apply a manual override to a synced LWF ledger row and resync payroll input',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('contribution_ledger_id', 'final_employee_contribution', 'final_employer_contribution'),
      'allowed_keys', jsonb_build_array('contribution_ledger_id', 'final_employee_contribution', 'final_employer_contribution', 'override_reason', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_apply_override registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'lwf_action_apply_override', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_apply_override role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'lwf_action_remove_override',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_remove_lwf_override',
    'group_name', 'LWF',
    'synopsis', 'Remove a manual LWF override and restore system contributions',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('contribution_ledger_id'),
      'allowed_keys', jsonb_build_array('contribution_ledger_id', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_remove_override registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'lwf_action_remove_override', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'lwf_action_remove_override role assignment failed: %', v_result::text; end if;
end;
$$;

;
