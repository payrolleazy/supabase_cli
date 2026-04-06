do $do$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'hierarchy_read_cached_org_chart',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'max_limit_per_request', 1000,
    'binding_ref', 'platform_rm_hierarchy_org_chart_cached',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'tenant_id', 'position_id', 'position_code', 'position_name', 'position_group_id',
        'position_group_code', 'position_group_name', 'reporting_position_id', 'hierarchy_path',
        'hierarchy_level', 'position_status', 'active_occupancy_count', 'direct_report_count',
        'operational_employee_id', 'operational_employee_code', 'operational_actor_user_id',
        'operational_employee_name', 'operational_occupancy_role', 'overlap_count'
      ),
      'filter_columns', jsonb_build_array(
        'position_id', 'position_code', 'position_group_id', 'reporting_position_id',
        'position_status', 'operational_employee_id', 'operational_employee_code',
        'operational_actor_user_id', 'operational_occupancy_role'
      ),
      'sort_columns', jsonb_build_array('hierarchy_path', 'position_code', 'position_name'),
      'tenant_column', 'tenant_id'
    ),
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'Hierarchy',
    'synopsis', 'Read cached hierarchy org chart',
    'metadata', jsonb_build_object('module_code', 'HIERARCHY', 'scope', 'runtime_support')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_read_cached_org_chart registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'hierarchy_read_cached_org_chart', 'role_code', 'tenant_owner_admin', 'metadata', '{}'::jsonb));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_read_cached_org_chart role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'hierarchy_read_position_history',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'max_limit_per_request', 500,
    'binding_ref', 'platform_rm_hierarchy_position_history',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'tenant_id', 'occupancy_history_id', 'occupancy_id', 'position_id', 'position_code',
        'position_name', 'employee_id', 'employee_code', 'employee_name', 'actor_user_id',
        'occupancy_role', 'event_type', 'effective_start_date', 'effective_end_date',
        'event_reason', 'event_details', 'created_at'
      ),
      'filter_columns', jsonb_build_array(
        'occupancy_history_id', 'occupancy_id', 'position_id', 'employee_id', 'event_type', 'occupancy_role'
      ),
      'sort_columns', jsonb_build_array('created_at', 'occupancy_history_id'),
      'tenant_column', 'tenant_id'
    ),
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'Hierarchy',
    'synopsis', 'Read hierarchy position history',
    'metadata', jsonb_build_object('module_code', 'HIERARCHY', 'scope', 'runtime_support')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_read_position_history registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'hierarchy_read_position_history', 'role_code', 'tenant_owner_admin', 'metadata', '{}'::jsonb));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_read_position_history role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'hierarchy_read_metrics_summary',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'max_limit_per_request', 25,
    'binding_ref', 'platform_rm_hierarchy_metrics_summary',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'tenant_id', 'total_position_count', 'active_position_count', 'occupied_position_count',
        'vacant_position_count', 'overlap_position_count', 'root_position_count', 'max_hierarchy_level',
        'last_cache_refresh_at', 'last_health_status', 'last_health_check_at'
      ),
      'filter_columns', '[]'::jsonb,
      'sort_columns', '[]'::jsonb,
      'tenant_column', 'tenant_id'
    ),
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'Hierarchy',
    'synopsis', 'Read hierarchy metrics summary',
    'metadata', jsonb_build_object('module_code', 'HIERARCHY', 'scope', 'runtime_support')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_read_metrics_summary registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'hierarchy_read_metrics_summary', 'role_code', 'tenant_owner_admin', 'metadata', '{}'::jsonb));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_read_metrics_summary role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'hierarchy_read_health_status',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'max_limit_per_request', 25,
    'binding_ref', 'platform_rm_hierarchy_health_status',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'tenant_id', 'health_status', 'issue_count', 'checked_at',
        'last_cache_refresh_at', 'last_maintenance_at', 'last_self_test_at', 'details'
      ),
      'filter_columns', jsonb_build_array('health_status', 'issue_count'),
      'sort_columns', jsonb_build_array('checked_at'),
      'tenant_column', 'tenant_id'
    ),
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'Hierarchy',
    'synopsis', 'Read hierarchy health status',
    'metadata', jsonb_build_object('module_code', 'HIERARCHY', 'scope', 'runtime_support')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_read_health_status registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'hierarchy_read_health_status', 'role_code', 'tenant_owner_admin', 'metadata', '{}'::jsonb));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_read_health_status role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'hierarchy_action_search_positions',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'binding_ref', 'platform_search_hierarchy_positions',
    'dispatch_config', '{}'::jsonb,
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'Hierarchy',
    'synopsis', 'Search hierarchy positions',
    'metadata', jsonb_build_object('module_code', 'HIERARCHY', 'scope', 'runtime_support')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_action_search_positions registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'hierarchy_action_search_positions', 'role_code', 'tenant_owner_admin', 'metadata', '{}'::jsonb));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_action_search_positions role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'hierarchy_action_health_check',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'binding_ref', 'platform_hierarchy_health_check',
    'dispatch_config', '{}'::jsonb,
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'Hierarchy',
    'synopsis', 'Run hierarchy health check',
    'metadata', jsonb_build_object('module_code', 'HIERARCHY', 'scope', 'runtime_support')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_action_health_check registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'hierarchy_action_health_check', 'role_code', 'tenant_owner_admin', 'metadata', '{}'::jsonb));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_action_health_check role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'hierarchy_action_self_test',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'binding_ref', 'platform_hierarchy_self_test',
    'dispatch_config', '{}'::jsonb,
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'Hierarchy',
    'synopsis', 'Run hierarchy self-test',
    'metadata', jsonb_build_object('module_code', 'HIERARCHY', 'scope', 'runtime_support')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_action_self_test registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'hierarchy_action_self_test', 'role_code', 'tenant_owner_admin', 'metadata', '{}'::jsonb));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'hierarchy_action_self_test role assignment failed: %', v_result;
  end if;
end;
$do$;

do $do$
declare
  v_command text := 'select public.platform_hierarchy_run_maintenance_scheduler();';
begin
  if exists (select 1 from cron.job where jobname = 'hierarchy-maintenance') then
    update cron.job
    set schedule = '*/30 * * * *',
        command = v_command,
        active = true
    where jobname = 'hierarchy-maintenance';
  else
    perform cron.schedule('hierarchy-maintenance', '*/30 * * * *', v_command);
  end if;
end;
$do$;
