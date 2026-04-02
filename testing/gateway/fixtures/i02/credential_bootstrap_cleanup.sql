do $$
declare
  v_payload jsonb;
  v_schema_result jsonb;
  v_tenant_code text;
  v_schema_name text;
begin
  perform public.platform_sim_i02_cleanup_case(jsonb_build_object(
    'scenario', 'complete_credential_setup_success',
    'fixture_run_key', 'i02_gateway_credential_bootstrap'
  ));

  v_payload := public.platform_sim_i02_fixture_payload('complete_credential_setup_success', 'i02_gateway_credential_bootstrap');
  v_tenant_code := public.platform_normalize_tenant_code(v_payload->>'company_name');
  v_schema_result := public.platform_generate_schema_name(jsonb_build_object('tenant_code', v_tenant_code));
  v_schema_name := v_schema_result->'details'->>'schema_name';

  if v_schema_name is not null and public.platform_schema_exists(v_schema_name) then
    execute format('drop schema if exists %I cascade', v_schema_name);
  end if;
end;
$$;

select json_build_object(
  'success', true,
  'fixture_run_key', 'i02_gateway_credential_bootstrap'
)::text;
