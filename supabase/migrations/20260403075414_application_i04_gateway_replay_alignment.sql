alter view public.platform_rm_extensible_entity_catalog set (security_invoker = true);
alter view public.platform_rm_extensible_attribute_catalog set (security_invoker = true);
alter view public.platform_rm_extensible_runtime_overview set (security_invoker = true);
alter view public.platform_rm_extensible_maintenance_status set (security_invoker = true);

select public.platform_register_gateway_operation(jsonb_build_object(
  'operation_code', 'i04_proof_action_get_join_profile',
  'operation_mode', 'action',
  'dispatch_kind', 'function_action',
  'operation_status', 'active',
  'route_policy', 'tenant_required',
  'tenant_requirement', 'required',
  'idempotency_policy', 'required',
  'rate_limit_policy', 'default',
  'binding_ref', 'platform_get_extensible_join_profile',
  'dispatch_config', '{}'::jsonb,
  'static_params', '{}'::jsonb,
  'request_contract', '{"allowed_keys":["entity_code","join_profile_code","include_inactive"],"required_keys":["entity_code","join_profile_code"]}'::jsonb,
  'response_contract', '{}'::jsonb,
  'group_name', 'I04 Proof',
  'synopsis', 'Resolve extensible join profile',
  'metadata', '{}'::jsonb
));

select public.platform_register_gateway_operation(jsonb_build_object(
  'operation_code', 'i04_proof_action_get_schema',
  'operation_mode', 'action',
  'dispatch_kind', 'function_action',
  'operation_status', 'active',
  'route_policy', 'tenant_required',
  'tenant_requirement', 'required',
  'idempotency_policy', 'required',
  'rate_limit_policy', 'default',
  'binding_ref', 'platform_get_extensible_attribute_schema',
  'dispatch_config', '{}'::jsonb,
  'static_params', '{}'::jsonb,
  'request_contract', '{"allowed_keys":["entity_code","include_inactive","use_cache","cache_ttl_seconds"],"required_keys":["entity_code"]}'::jsonb,
  'response_contract', '{}'::jsonb,
  'group_name', 'I04 Proof',
  'synopsis', 'Resolve extensible schema descriptor',
  'metadata', '{}'::jsonb
));

select public.platform_register_gateway_operation(jsonb_build_object(
  'operation_code', 'i04_proof_action_get_template_descriptor',
  'operation_mode', 'action',
  'dispatch_kind', 'function_action',
  'operation_status', 'active',
  'route_policy', 'tenant_required',
  'tenant_requirement', 'required',
  'idempotency_policy', 'required',
  'rate_limit_policy', 'default',
  'binding_ref', 'platform_get_extensible_template_descriptor',
  'dispatch_config', '{}'::jsonb,
  'static_params', '{}'::jsonb,
  'request_contract', '{"allowed_keys":["entity_code","use_cache"],"required_keys":["entity_code"]}'::jsonb,
  'response_contract', '{}'::jsonb,
  'group_name', 'I04 Proof',
  'synopsis', 'Resolve extensible template descriptor',
  'metadata', '{}'::jsonb
));

select public.platform_register_gateway_operation(jsonb_build_object(
  'operation_code', 'i04_proof_action_invalidate_schema_cache',
  'operation_mode', 'action',
  'dispatch_kind', 'function_action',
  'operation_status', 'active',
  'route_policy', 'tenant_required',
  'tenant_requirement', 'required',
  'idempotency_policy', 'required',
  'rate_limit_policy', 'default',
  'binding_ref', 'platform_invalidate_extensible_schema_cache',
  'dispatch_config', '{}'::jsonb,
  'static_params', '{}'::jsonb,
  'request_contract', '{"allowed_keys":["entity_code"],"required_keys":["entity_code"]}'::jsonb,
  'response_contract', '{}'::jsonb,
  'group_name', 'I04 Proof',
  'synopsis', 'Invalidate extensible schema cache',
  'metadata', '{}'::jsonb
));

select public.platform_register_gateway_operation(jsonb_build_object(
  'operation_code', 'i04_proof_action_validate_payload',
  'operation_mode', 'action',
  'dispatch_kind', 'function_action',
  'operation_status', 'active',
  'route_policy', 'tenant_required',
  'tenant_requirement', 'required',
  'idempotency_policy', 'required',
  'rate_limit_policy', 'default',
  'binding_ref', 'platform_validate_extensible_payload',
  'dispatch_config', '{}'::jsonb,
  'static_params', '{}'::jsonb,
  'request_contract', '{"allowed_keys":["entity_code","payload","allow_unknown_attributes"],"required_keys":["entity_code","payload"]}'::jsonb,
  'response_contract', '{}'::jsonb,
  'group_name', 'I04 Proof',
  'synopsis', 'Validate extensible payload',
  'metadata', '{}'::jsonb
));

select public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'i04_proof_action_get_join_profile', 'role_code', 'i01_portal_user', 'metadata', '{}'::jsonb));
select public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'i04_proof_action_get_join_profile', 'role_code', 'tenant_owner_admin', 'metadata', '{}'::jsonb));
select public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'i04_proof_action_get_schema', 'role_code', 'i01_portal_user', 'metadata', '{}'::jsonb));
select public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'i04_proof_action_get_schema', 'role_code', 'tenant_owner_admin', 'metadata', '{}'::jsonb));
select public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'i04_proof_action_get_template_descriptor', 'role_code', 'i01_portal_user', 'metadata', '{}'::jsonb));
select public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'i04_proof_action_get_template_descriptor', 'role_code', 'tenant_owner_admin', 'metadata', '{}'::jsonb));
select public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'i04_proof_action_invalidate_schema_cache', 'role_code', 'tenant_owner_admin', 'metadata', '{}'::jsonb));
select public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'i04_proof_action_validate_payload', 'role_code', 'i01_portal_user', 'metadata', '{}'::jsonb));
select public.platform_assign_gateway_operation_role(jsonb_build_object('operation_code', 'i04_proof_action_validate_payload', 'role_code', 'tenant_owner_admin', 'metadata', '{}'::jsonb));
