do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'wcm_read_resignation_request_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_wcm_resignation_request_catalog',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'request_id', 'tenant_id', 'employee_id', 'position_id', 'request_status',
        'resignation_date', 'tentative_leaving_date', 'approved_last_working_day',
        'waive_notice_shortfall', 'separation_reason', 'comments',
        'lifecycle_runtime_status', 'last_event_id', 'last_decision_code',
        'last_action_code', 'last_runtime_message', 'approved_by_actor_user_id',
        'approved_at', 'withdrawn_by_actor_user_id', 'withdrawn_at',
        'created_at', 'updated_at', 'request_metadata'
      ),
      'filter_columns', jsonb_build_array(
        'request_id', 'employee_id', 'position_id', 'request_status', 'lifecycle_runtime_status'
      ),
      'sort_columns', jsonb_build_array('created_at', 'updated_at', 'resignation_date'),
      'tenant_column', 'tenant_id'
    ),
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'WCM Core',
    'synopsis', 'Read WCM resignation request catalog',
    'metadata', '{}'::jsonb
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_read_resignation_request_catalog alignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'wcm_read_lifecycle_rollback_audit',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_wcm_lifecycle_rollback_audit',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'audit_id', 'tenant_id', 'request_id', 'employee_id', 'position_id',
        'decision_code', 'action_code', 'manual_review_required', 'actor_user_id',
        'reason', 'audit_payload', 'created_at'
      ),
      'filter_columns', jsonb_build_array(
        'audit_id', 'request_id', 'employee_id', 'position_id', 'decision_code',
        'action_code', 'manual_review_required'
      ),
      'sort_columns', jsonb_build_array('created_at', 'audit_id'),
      'tenant_column', 'tenant_id'
    ),
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'WCM Core',
    'synopsis', 'Read WCM lifecycle rollback audit',
    'metadata', '{}'::jsonb
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_read_lifecycle_rollback_audit alignment failed: %', v_result;
  end if;
end
$$;
