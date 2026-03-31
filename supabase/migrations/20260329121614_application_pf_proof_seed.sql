do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'pf_read_establishment_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 100,
    'binding_ref', 'platform_rm_pf_establishment_catalog',
    'group_name', 'PF',
    'synopsis', 'Read PF establishment catalog for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('establishment_id', 'establishment_code', 'establishment_name', 'pf_office_code', 'establishment_status', 'active_enrollment_count'),
      'filter_columns', jsonb_build_array('establishment_id', 'establishment_code', 'establishment_name', 'pf_office_code', 'establishment_status'),
      'sort_columns', jsonb_build_array('establishment_code', 'establishment_name', 'establishment_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_read_establishment_catalog registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'pf_read_establishment_catalog', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_read_establishment_catalog role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'pf_read_enrollment_status',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_pf_enrollment_status',
    'group_name', 'PF',
    'synopsis', 'Read PF employee enrollment status for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('enrollment_id', 'employee_id', 'employee_code', 'establishment_id', 'enrollment_status', 'uan', 'pf_member_id', 'effective_from', 'effective_to'),
      'filter_columns', jsonb_build_array('enrollment_id', 'employee_id', 'employee_code', 'establishment_id', 'enrollment_status', 'uan', 'pf_member_id'),
      'sort_columns', jsonb_build_array('employee_code', 'effective_from', 'enrollment_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_read_enrollment_status registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'pf_read_enrollment_status', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_read_enrollment_status role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'pf_read_batch_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_pf_batch_catalog',
    'group_name', 'PF',
    'synopsis', 'Read PF monthly batch catalog for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('batch_id', 'establishment_id', 'payroll_period', 'batch_status', 'processed_count', 'anomaly_count', 'skipped_count', 'created_at', 'updated_at'),
      'filter_columns', jsonb_build_array('batch_id', 'establishment_id', 'payroll_period', 'batch_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'updated_at', 'batch_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_read_batch_catalog registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'pf_read_batch_catalog', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_read_batch_catalog role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'pf_read_anomaly_queue',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_pf_anomaly_queue',
    'group_name', 'PF',
    'synopsis', 'Read PF anomaly queue for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('anomaly_id', 'batch_id', 'employee_id', 'employee_code', 'anomaly_code', 'severity', 'anomaly_status', 'anomaly_message', 'created_at'),
      'filter_columns', jsonb_build_array('anomaly_id', 'batch_id', 'employee_id', 'employee_code', 'anomaly_code', 'severity', 'anomaly_status'),
      'sort_columns', jsonb_build_array('created_at', 'severity', 'anomaly_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_read_anomaly_queue registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'pf_read_anomaly_queue', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_read_anomaly_queue role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'pf_read_ecr_run_status',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 200,
    'binding_ref', 'platform_rm_pf_ecr_run_status',
    'group_name', 'PF',
    'synopsis', 'Read PF ECR generation status for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('ecr_run_id', 'batch_id', 'establishment_id', 'payroll_period', 'run_status', 'row_count', 'template_document_id', 'generated_document_id', 'updated_at'),
      'filter_columns', jsonb_build_array('ecr_run_id', 'batch_id', 'establishment_id', 'payroll_period', 'run_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'updated_at', 'ecr_run_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_read_ecr_run_status registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'pf_read_ecr_run_status', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_read_ecr_run_status role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'pf_read_contribution_ledger',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 500,
    'binding_ref', 'platform_rm_pf_contribution_ledger',
    'group_name', 'PF',
    'synopsis', 'Read PF contribution ledger rows for tenant statutory administrators',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array('contribution_ledger_id', 'batch_id', 'employee_id', 'employee_code', 'payroll_period', 'employee_share', 'employer_share', 'eps_share', 'epf_share', 'sync_status'),
      'filter_columns', jsonb_build_array('contribution_ledger_id', 'batch_id', 'employee_id', 'employee_code', 'payroll_period', 'sync_status'),
      'sort_columns', jsonb_build_array('payroll_period', 'employee_code', 'contribution_ledger_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_read_contribution_ledger registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'pf_read_contribution_ledger', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_read_contribution_ledger role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'pf_action_manage_establishment',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_register_pf_establishment',
    'group_name', 'PF',
    'synopsis', 'Create or update a PF establishment configuration',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('establishment_code', 'establishment_name', 'pf_office_code'),
      'allowed_keys', jsonb_build_array('establishment_code', 'establishment_name', 'legal_entity_name', 'pf_office_code', 'employer_pf_rate', 'employee_pf_rate', 'eps_rate', 'epf_rate', 'admin_charge_rate', 'edli_rate', 'wage_ceiling', 'calc_policy', 'establishment_status')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_action_manage_establishment registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'pf_action_manage_establishment', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_action_manage_establishment role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'pf_action_manage_employee_enrollment',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_register_pf_employee_enrollment',
    'group_name', 'PF',
    'synopsis', 'Create or update a PF employee enrollment',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('employee_id', 'establishment_id'),
      'allowed_keys', jsonb_build_array('employee_id', 'establishment_id', 'uan', 'pf_member_id', 'payroll_area_id', 'wage_basis_override', 'voluntary_pf_rate', 'eps_eligible', 'enrollment_status', 'effective_from', 'effective_to', 'exit_reason', 'enrollment_metadata')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_action_manage_employee_enrollment registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'pf_action_manage_employee_enrollment', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_action_manage_employee_enrollment role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'pf_action_record_arrear_case',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_record_pf_arrear_case',
    'group_name', 'PF',
    'synopsis', 'Record a PF arrear case for later monthly settlement',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('employee_id', 'establishment_id', 'effective_period', 'wage_delta'),
      'allowed_keys', jsonb_build_array('employee_id', 'establishment_id', 'effective_period', 'wage_delta', 'employee_share_delta', 'employer_share_delta', 'arrear_status', 'review_notes', 'reviewed_by_actor_user_id', 'arrear_metadata')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_action_record_arrear_case registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'pf_action_record_arrear_case', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_action_record_arrear_case role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'pf_action_request_batch',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_request_pf_batch',
    'group_name', 'PF',
    'synopsis', 'Request a monthly PF batch on the shared async spine',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('establishment_id', 'payroll_period'),
      'allowed_keys', jsonb_build_array('establishment_id', 'payroll_period', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_action_request_batch registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'pf_action_request_batch', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_action_request_batch role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'pf_action_review_anomaly',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_review_pf_anomaly',
    'group_name', 'PF',
    'synopsis', 'Resolve, ignore, or reopen a PF anomaly',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('anomaly_id', 'action'),
      'allowed_keys', jsonb_build_array('anomaly_id', 'action', 'resolution_notes')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_action_review_anomaly registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'pf_action_review_anomaly', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_action_review_anomaly role assignment failed: %', v_result::text; end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'pf_action_request_ecr_run',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_request_pf_ecr_run',
    'group_name', 'PF',
    'synopsis', 'Request PF ECR generation for a processed monthly batch',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('batch_id'),
      'allowed_keys', jsonb_build_array('batch_id', 'template_document_id', 'actor_user_id')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_action_request_ecr_run registration failed: %', v_result::text; end if;
  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'pf_action_request_ecr_run', 'role_code', 'tenant_owner_admin'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'pf_action_request_ecr_run role assignment failed: %', v_result::text; end if;
end;
$$;;
