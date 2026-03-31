do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'rcm_read_requisition_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_rcm_requisition_catalog',
    'group_name', 'Recruitment & Conversion',
    'synopsis', 'Read recruitment requisition catalog',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'tenant_id', 'requisition_id', 'requisition_code', 'requisition_title', 'position_id',
        'position_code', 'position_name', 'requisition_status', 'openings_count', 'filled_count',
        'open_application_count', 'target_start_date', 'priority_code', 'created_at', 'updated_at'
      ),
      'filter_columns', jsonb_build_array(
        'requisition_id', 'requisition_code', 'position_id', 'position_code',
        'requisition_status', 'priority_code'
      ),
      'sort_columns', jsonb_build_array('requisition_code', 'updated_at'),
      'tenant_column', 'tenant_id'
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_read_requisition_catalog registration failed: %', v_result::text;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'rcm_read_requisition_catalog',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_read_requisition_catalog role assignment failed: %', v_result::text;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'rcm_read_candidate_pipeline',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 500,
    'binding_ref', 'platform_rm_rcm_candidate_pipeline',
    'group_name', 'Recruitment & Conversion',
    'synopsis', 'Read recruitment candidate pipeline',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'tenant_id', 'application_id', 'requisition_id', 'requisition_code', 'candidate_id',
        'candidate_code', 'candidate_name', 'primary_email', 'current_stage_code',
        'application_status', 'target_position_id', 'target_position_code', 'conversion_case_id',
        'conversion_status', 'wcm_employee_id', 'employee_code', 'applied_on', 'converted_at',
        'updated_at'
      ),
      'filter_columns', jsonb_build_array(
        'application_id', 'requisition_id', 'requisition_code', 'candidate_id',
        'candidate_code', 'current_stage_code', 'application_status', 'conversion_status',
        'wcm_employee_id'
      ),
      'sort_columns', jsonb_build_array('updated_at', 'candidate_code', 'requisition_code'),
      'tenant_column', 'tenant_id'
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_read_candidate_pipeline registration failed: %', v_result::text;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'rcm_read_candidate_pipeline',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_read_candidate_pipeline role assignment failed: %', v_result::text;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'rcm_read_conversion_queue',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_rcm_conversion_queue',
    'group_name', 'Recruitment & Conversion',
    'synopsis', 'Read recruitment conversion queue',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'tenant_id', 'conversion_case_id', 'application_id', 'requisition_id', 'requisition_code',
        'candidate_id', 'candidate_code', 'candidate_name', 'target_position_id',
        'target_position_code', 'conversion_status', 'prepared_at', 'converted_at',
        'wcm_employee_id', 'employee_code', 'current_stage_code', 'application_status'
      ),
      'filter_columns', jsonb_build_array(
        'conversion_case_id', 'application_id', 'requisition_id', 'candidate_id',
        'candidate_code', 'target_position_id', 'conversion_status', 'wcm_employee_id'
      ),
      'sort_columns', jsonb_build_array('prepared_at', 'candidate_code', 'requisition_code'),
      'tenant_column', 'tenant_id'
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_read_conversion_queue registration failed: %', v_result::text;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'rcm_read_conversion_queue',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_read_conversion_queue role assignment failed: %', v_result::text;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'rcm_action_register_requisition',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_register_rcm_requisition',
    'group_name', 'Recruitment & Conversion',
    'synopsis', 'Create or update a recruitment requisition',
    'request_contract', jsonb_build_object(
      'allowed_keys', jsonb_build_array(
        'requisition_id', 'requisition_code', 'requisition_title', 'position_id',
        'requisition_status', 'openings_count', 'priority_code', 'target_start_date',
        'description'
      )
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_action_register_requisition registration failed: %', v_result::text;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'rcm_action_register_requisition',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_action_register_requisition role assignment failed: %', v_result::text;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'rcm_action_register_candidate',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_register_rcm_candidate',
    'group_name', 'Recruitment & Conversion',
    'synopsis', 'Create or update a recruitment candidate',
    'request_contract', jsonb_build_object(
      'allowed_keys', jsonb_build_array(
        'candidate_id', 'candidate_code', 'first_name', 'middle_name', 'last_name',
        'primary_email', 'primary_phone', 'source_code', 'candidate_status'
      )
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_action_register_candidate registration failed: %', v_result::text;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'rcm_action_register_candidate',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_action_register_candidate role assignment failed: %', v_result::text;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'rcm_action_register_job_application',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'binding_ref', 'platform_register_rcm_job_application',
    'group_name', 'Recruitment & Conversion',
    'synopsis', 'Create or update a recruitment job application',
    'request_contract', jsonb_build_object(
      'allowed_keys', jsonb_build_array(
        'application_id', 'requisition_id', 'candidate_id', 'current_stage_code',
        'application_status', 'applied_on', 'application_metadata', 'actor_user_id'
      )
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_action_register_job_application registration failed: %', v_result::text;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'rcm_action_register_job_application',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_action_register_job_application role assignment failed: %', v_result::text;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'rcm_action_transition_application_stage',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'required',
    'binding_ref', 'platform_transition_rcm_application_stage',
    'group_name', 'Recruitment & Conversion',
    'synopsis', 'Transition a recruitment application stage',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('application_id', 'new_stage_code'),
      'allowed_keys', jsonb_build_array(
        'application_id', 'new_stage_code', 'stage_outcome', 'event_reason',
        'event_details', 'actor_user_id'
      )
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_action_transition_application_stage registration failed: %', v_result::text;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'rcm_action_transition_application_stage',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_action_transition_application_stage role assignment failed: %', v_result::text;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'rcm_action_prepare_conversion_contract',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'required',
    'binding_ref', 'platform_prepare_rcm_conversion_contract',
    'group_name', 'Recruitment & Conversion',
    'synopsis', 'Prepare the authoritative recruitment conversion contract',
    'request_contract', jsonb_build_object(
      'required_keys', jsonb_build_array('application_id'),
      'allowed_keys', jsonb_build_array(
        'application_id', 'conversion_case_id', 'target_position_id',
        'conversion_notes', 'actor_user_id'
      )
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_action_prepare_conversion_contract registration failed: %', v_result::text;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'rcm_action_prepare_conversion_contract',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_action_prepare_conversion_contract role assignment failed: %', v_result::text;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'rcm_action_execute_conversion',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'required',
    'binding_ref', 'platform_execute_rcm_conversion',
    'group_name', 'Recruitment & Conversion',
    'synopsis', 'Execute authoritative recruitment conversion into WCM employee truth',
    'request_contract', jsonb_build_object(
      'allowed_keys', jsonb_build_array(
        'conversion_case_id', 'application_id', 'employee_code', 'employee_actor_user_id',
        'joining_date', 'service_state', 'employment_status', 'conversion_notes',
        'actor_user_id'
      )
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_action_execute_conversion registration failed: %', v_result::text;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'rcm_action_execute_conversion',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'rcm_action_execute_conversion role assignment failed: %', v_result::text;
  end if;
end $$;;
