do $do$
declare
  v_operation jsonb;
  v_role jsonb;
  v_result jsonb;
begin
  for v_operation in
    select *
    from jsonb_array_elements(
      $json$
      [
        {
          "operation_code": "hierarchy_action_get_manager_resolution",
          "operation_mode": "action",
          "dispatch_kind": "function_action",
          "operation_status": "active",
          "route_policy": "tenant_required",
          "tenant_requirement": "required",
          "idempotency_policy": "required",
          "rate_limit_policy": "default",
          "max_limit_per_request": null,
          "binding_ref": "platform_get_hierarchy_manager_resolution",
          "dispatch_config": {},
          "static_params": {},
          "request_contract": {
            "allowed_keys": ["position_id", "employee_id"]
          },
          "response_contract": {},
          "group_name": "Hierarchy",
          "synopsis": "Resolve manager context from hierarchy position truth",
          "metadata": {},
          "roles": [
            {
              "role_code": "tenant_owner_admin",
              "metadata": {}
            }
          ]
        },
        {
          "operation_code": "hierarchy_action_get_operational_occupant",
          "operation_mode": "action",
          "dispatch_kind": "function_action",
          "operation_status": "active",
          "route_policy": "tenant_required",
          "tenant_requirement": "required",
          "idempotency_policy": "required",
          "rate_limit_policy": "default",
          "max_limit_per_request": null,
          "binding_ref": "platform_get_hierarchy_operational_occupant",
          "dispatch_config": {},
          "static_params": {},
          "request_contract": {
            "allowed_keys": ["position_id"],
            "required_keys": ["position_id"]
          },
          "response_contract": {},
          "group_name": "Hierarchy",
          "synopsis": "Resolve the operational occupant for a position",
          "metadata": {},
          "roles": [
            {
              "role_code": "tenant_owner_admin",
              "metadata": {}
            }
          ]
        },
        {
          "operation_code": "hierarchy_action_register_position",
          "operation_mode": "action",
          "dispatch_kind": "function_action",
          "operation_status": "active",
          "route_policy": "tenant_required",
          "tenant_requirement": "required",
          "idempotency_policy": "optional",
          "rate_limit_policy": "default",
          "max_limit_per_request": null,
          "binding_ref": "platform_register_hierarchy_position",
          "dispatch_config": {},
          "static_params": {},
          "request_contract": {
            "allowed_keys": [
              "position_id",
              "position_code",
              "position_name",
              "position_group_id",
              "reporting_position_id",
              "position_status",
              "effective_start_date",
              "effective_end_date"
            ]
          },
          "response_contract": {},
          "group_name": "Hierarchy",
          "synopsis": "Create or update a hierarchy position",
          "metadata": {},
          "roles": [
            {
              "role_code": "tenant_owner_admin",
              "metadata": {}
            }
          ]
        },
        {
          "operation_code": "hierarchy_action_register_position_group",
          "operation_mode": "action",
          "dispatch_kind": "function_action",
          "operation_status": "active",
          "route_policy": "tenant_required",
          "tenant_requirement": "required",
          "idempotency_policy": "optional",
          "rate_limit_policy": "default",
          "max_limit_per_request": null,
          "binding_ref": "platform_register_hierarchy_position_group",
          "dispatch_config": {},
          "static_params": {},
          "request_contract": {
            "allowed_keys": [
              "position_group_id",
              "position_group_code",
              "position_group_name",
              "group_status",
              "description"
            ]
          },
          "response_contract": {},
          "group_name": "Hierarchy",
          "synopsis": "Create or update a hierarchy position group",
          "metadata": {},
          "roles": [
            {
              "role_code": "tenant_owner_admin",
              "metadata": {}
            }
          ]
        },
        {
          "operation_code": "hierarchy_action_upsert_position_occupancy",
          "operation_mode": "action",
          "dispatch_kind": "function_action",
          "operation_status": "active",
          "route_policy": "tenant_required",
          "tenant_requirement": "required",
          "idempotency_policy": "required",
          "rate_limit_policy": "default",
          "max_limit_per_request": null,
          "binding_ref": "platform_upsert_hierarchy_position_occupancy",
          "dispatch_config": {},
          "static_params": {},
          "request_contract": {
            "allowed_keys": [
              "occupancy_id",
              "employee_id",
              "position_id",
              "occupancy_role",
              "effective_start_date",
              "effective_end_date",
              "occupancy_status",
              "occupancy_reason",
              "event_details",
              "actor_user_id"
            ],
            "required_keys": [
              "employee_id",
              "position_id"
            ]
          },
          "response_contract": {},
          "group_name": "Hierarchy",
          "synopsis": "Create or update a hierarchy occupancy assignment",
          "metadata": {},
          "roles": [
            {
              "role_code": "tenant_owner_admin",
              "metadata": {}
            }
          ]
        },
        {
          "operation_code": "hierarchy_read_operational_occupancy",
          "operation_mode": "read",
          "dispatch_kind": "read_surface",
          "operation_status": "active",
          "route_policy": "tenant_required",
          "tenant_requirement": "required",
          "idempotency_policy": "optional",
          "rate_limit_policy": "default",
          "max_limit_per_request": 500,
          "binding_ref": "platform_rm_hierarchy_operational_occupancy",
          "dispatch_config": {
            "sort_columns": ["position_id", "employee_code", "effective_start_date"],
            "tenant_column": "tenant_id",
            "filter_columns": [
              "position_id",
              "position_code",
              "employee_id",
              "employee_code",
              "occupancy_role",
              "service_state",
              "is_operational_occupant"
            ],
            "select_columns": [
              "tenant_id",
              "position_id",
              "position_code",
              "position_name",
              "reporting_position_id",
              "employee_id",
              "employee_code",
              "actor_user_id",
              "employee_name",
              "occupancy_id",
              "occupancy_role",
              "effective_start_date",
              "effective_end_date",
              "service_state",
              "employment_status",
              "active_occupancy_count",
              "overlap_count",
              "is_operational_occupant"
            ]
          },
          "static_params": {},
          "request_contract": {},
          "response_contract": {},
          "group_name": "Hierarchy",
          "synopsis": "Read hierarchy operational occupancy",
          "metadata": {},
          "roles": [
            {
              "role_code": "tenant_owner_admin",
              "metadata": {}
            }
          ]
        },
        {
          "operation_code": "hierarchy_read_org_chart",
          "operation_mode": "read",
          "dispatch_kind": "read_surface",
          "operation_status": "active",
          "route_policy": "tenant_required",
          "tenant_requirement": "required",
          "idempotency_policy": "optional",
          "rate_limit_policy": "default",
          "max_limit_per_request": 500,
          "binding_ref": "platform_rm_hierarchy_org_chart",
          "dispatch_config": {
            "sort_columns": ["hierarchy_path", "position_code"],
            "tenant_column": "tenant_id",
            "filter_columns": [
              "position_id",
              "position_group_id",
              "position_group_code",
              "reporting_position_id",
              "position_status",
              "operational_employee_id",
              "operational_employee_code"
            ],
            "select_columns": [
              "tenant_id",
              "position_id",
              "position_code",
              "position_name",
              "position_group_id",
              "position_group_code",
              "position_group_name",
              "reporting_position_id",
              "hierarchy_path",
              "hierarchy_level",
              "position_status",
              "active_occupancy_count",
              "direct_report_count",
              "operational_employee_id",
              "operational_employee_code",
              "operational_actor_user_id",
              "operational_employee_name",
              "operational_occupancy_role",
              "overlap_count"
            ]
          },
          "static_params": {},
          "request_contract": {},
          "response_contract": {},
          "group_name": "Hierarchy",
          "synopsis": "Read hierarchy org chart",
          "metadata": {},
          "roles": [
            {
              "role_code": "tenant_owner_admin",
              "metadata": {}
            }
          ]
        },
        {
          "operation_code": "hierarchy_read_position_catalog",
          "operation_mode": "read",
          "dispatch_kind": "read_surface",
          "operation_status": "active",
          "route_policy": "tenant_required",
          "tenant_requirement": "required",
          "idempotency_policy": "optional",
          "rate_limit_policy": "default",
          "max_limit_per_request": 500,
          "binding_ref": "platform_rm_hierarchy_position_catalog",
          "dispatch_config": {
            "sort_columns": ["hierarchy_path", "position_code", "hierarchy_level"],
            "tenant_column": "tenant_id",
            "filter_columns": [
              "position_id",
              "position_code",
              "position_group_id",
              "position_group_code",
              "reporting_position_id",
              "position_status"
            ],
            "select_columns": [
              "tenant_id",
              "position_id",
              "position_code",
              "position_name",
              "position_group_id",
              "position_group_code",
              "position_group_name",
              "reporting_position_id",
              "hierarchy_path",
              "hierarchy_level",
              "position_status",
              "effective_start_date",
              "effective_end_date",
              "active_occupancy_count",
              "direct_report_count"
            ]
          },
          "static_params": {},
          "request_contract": {},
          "response_contract": {},
          "group_name": "Hierarchy",
          "synopsis": "Read hierarchy position catalog",
          "metadata": {},
          "roles": [
            {
              "role_code": "tenant_owner_admin",
              "metadata": {}
            }
          ]
        },
        {
          "operation_code": "hierarchy_read_position_group_catalog",
          "operation_mode": "read",
          "dispatch_kind": "read_surface",
          "operation_status": "active",
          "route_policy": "tenant_required",
          "tenant_requirement": "required",
          "idempotency_policy": "optional",
          "rate_limit_policy": "default",
          "max_limit_per_request": 250,
          "binding_ref": "platform_rm_hierarchy_position_group_catalog",
          "dispatch_config": {
            "sort_columns": ["position_group_code", "updated_at"],
            "tenant_column": "tenant_id",
            "filter_columns": [
              "position_group_id",
              "position_group_code",
              "group_status"
            ],
            "select_columns": [
              "tenant_id",
              "position_group_id",
              "position_group_code",
              "position_group_name",
              "group_status",
              "description",
              "total_position_count",
              "active_position_count",
              "created_at",
              "updated_at"
            ]
          },
          "static_params": {},
          "request_contract": {},
          "response_contract": {},
          "group_name": "Hierarchy",
          "synopsis": "Read hierarchy position-group catalog",
          "metadata": {},
          "roles": [
            {
              "role_code": "tenant_owner_admin",
              "metadata": {}
            }
          ]
        },
        {
          "operation_code": "hierarchy_read_team_scope",
          "operation_mode": "read",
          "dispatch_kind": "read_surface",
          "operation_status": "active",
          "route_policy": "tenant_required",
          "tenant_requirement": "required",
          "idempotency_policy": "optional",
          "rate_limit_policy": "default",
          "max_limit_per_request": 500,
          "binding_ref": "platform_rm_hierarchy_team_scope",
          "dispatch_config": {
            "sort_columns": ["manager_employee_code", "team_member_employee_code"],
            "tenant_column": "tenant_id",
            "filter_columns": [
              "manager_position_id",
              "manager_employee_id",
              "manager_actor_user_id",
              "team_member_position_id",
              "team_member_employee_id",
              "team_member_actor_user_id"
            ],
            "select_columns": [
              "tenant_id",
              "manager_position_id",
              "manager_employee_id",
              "manager_actor_user_id",
              "manager_employee_code",
              "manager_employee_name",
              "team_member_position_id",
              "team_member_position_code",
              "team_member_employee_id",
              "team_member_actor_user_id",
              "team_member_employee_code",
              "team_member_employee_name"
            ]
          },
          "static_params": {},
          "request_contract": {},
          "response_contract": {},
          "group_name": "Hierarchy",
          "synopsis": "Read hierarchy manager team scope",
          "metadata": {},
          "roles": [
            {
              "role_code": "tenant_owner_admin",
              "metadata": {}
            }
          ]
        }
      ]
      $json$::jsonb
    )
  loop
    v_result := public.platform_register_gateway_operation(v_operation - 'roles');
    if coalesce((v_result->>'success')::boolean, false) is not true then
      raise exception 'HIERARCHY replay-alignment registration failed for %: %', v_operation->>'operation_code', v_result;
    end if;

    for v_role in
      select *
      from jsonb_array_elements(coalesce(v_operation->'roles', '[]'::jsonb))
    loop
      v_result := public.platform_assign_gateway_operation_role(
        jsonb_build_object(
          'operation_code', v_operation->>'operation_code',
          'role_code', v_role->>'role_code',
          'metadata', coalesce(v_role->'metadata', '{}'::jsonb)
        )
      );
      if coalesce((v_result->>'success')::boolean, false) is not true then
        raise exception 'HIERARCHY replay-alignment role assignment failed for %/%: %', v_operation->>'operation_code', v_role->>'role_code', v_result;
      end if;
    end loop;
  end loop;
end;
$do$;

alter view public.platform_rm_hierarchy_position_group_catalog set (security_invoker = true);
alter view public.platform_rm_hierarchy_position_catalog set (security_invoker = true);
alter view public.platform_rm_hierarchy_org_chart set (security_invoker = true);
alter view public.platform_rm_hierarchy_operational_occupancy set (security_invoker = true);
alter view public.platform_rm_hierarchy_team_scope set (security_invoker = true);
alter view public.platform_rm_hierarchy_org_chart_cached set (security_invoker = true);
alter view public.platform_rm_hierarchy_position_history set (security_invoker = true);
alter view public.platform_rm_hierarchy_metrics_summary set (security_invoker = true);
alter view public.platform_rm_hierarchy_health_status set (security_invoker = true);