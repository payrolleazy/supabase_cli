do $$
declare
  v_template_version text := public.platform_ptax_module_template_version();
  v_result jsonb;
begin
  v_result := public.platform_register_template_version(jsonb_build_object(
    'template_version', v_template_version,
    'template_scope', 'module',
    'module_code', 'PTAX',
    'template_status', 'released',
    'description', 'PTAX tenant-owned professional-tax statutory engine baseline.',
    'metadata', jsonb_build_object('slice', 'PTAX', 'module_code', 'PTAX')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PTAX template version registration failed: %', v_result::text; end if;

  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PTAX','source_schema_name', 'public','source_table_name', 'wcm_ptax_configuration','target_table_name', 'wcm_ptax_configuration','clone_order', 100,'notes', jsonb_build_object('slice', 'PTAX','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PTAX configuration table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PTAX','source_schema_name', 'public','source_table_name', 'wcm_ptax_employee_state_profile','target_table_name', 'wcm_ptax_employee_state_profile','clone_order', 110,'notes', jsonb_build_object('slice', 'PTAX','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PTAX state profile table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PTAX','source_schema_name', 'public','source_table_name', 'wcm_ptax_wage_component_mapping','target_table_name', 'wcm_ptax_wage_component_mapping','clone_order', 120,'notes', jsonb_build_object('slice', 'PTAX','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PTAX wage mapping table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PTAX','source_schema_name', 'public','source_table_name', 'wcm_ptax_processing_batch','target_table_name', 'wcm_ptax_processing_batch','clone_order', 130,'notes', jsonb_build_object('slice', 'PTAX','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PTAX batch table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PTAX','source_schema_name', 'public','source_table_name', 'wcm_ptax_monthly_ledger','target_table_name', 'wcm_ptax_monthly_ledger','clone_order', 140,'notes', jsonb_build_object('slice', 'PTAX','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PTAX ledger table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PTAX','source_schema_name', 'public','source_table_name', 'wcm_ptax_arrear_case','target_table_name', 'wcm_ptax_arrear_case','clone_order', 150,'notes', jsonb_build_object('slice', 'PTAX','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PTAX arrear case table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PTAX','source_schema_name', 'public','source_table_name', 'wcm_ptax_arrear_computation','target_table_name', 'wcm_ptax_arrear_computation','clone_order', 160,'notes', jsonb_build_object('slice', 'PTAX','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PTAX arrear computation table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PTAX','source_schema_name', 'public','source_table_name', 'wcm_ptax_audit_event','target_table_name', 'wcm_ptax_audit_event','clone_order', 170,'notes', jsonb_build_object('slice', 'PTAX','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PTAX audit table registration failed: %', v_result::text; end if;

  v_result := public.platform_register_async_worker(jsonb_build_object(
    'worker_code', 'ptax_monthly_worker',
    'module_code', 'PTAX',
    'dispatch_mode', 'db_inline_handler',
    'handler_contract', 'platform_process_ptax_batch_job',
    'is_active', true,
    'max_batch_size', 4,
    'default_lease_seconds', 600,
    'heartbeat_grace_seconds', 900,
    'retry_backoff_policy', jsonb_build_object('base_seconds', 90, 'multiplier', 2, 'max_seconds', 3600),
    'metadata', jsonb_build_object('slice', 'PTAX', 'notes', 'First clean PTAX monthly worker on shared F04 spine.')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PTAX monthly worker registration failed: %', v_result::text; end if;

  v_result := public.platform_register_async_worker(jsonb_build_object(
    'worker_code', 'ptax_arrear_worker',
    'module_code', 'PTAX',
    'dispatch_mode', 'db_inline_handler',
    'handler_contract', 'platform_process_ptax_arrear_job',
    'is_active', true,
    'max_batch_size', 5,
    'default_lease_seconds', 300,
    'heartbeat_grace_seconds', 600,
    'retry_backoff_policy', jsonb_build_object('base_seconds', 60, 'multiplier', 2, 'max_seconds', 1800),
    'metadata', jsonb_build_object('slice', 'PTAX', 'notes', 'First clean PTAX arrear worker on shared F04 spine.')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PTAX arrear worker registration failed: %', v_result::text; end if;
end;
$$;;
