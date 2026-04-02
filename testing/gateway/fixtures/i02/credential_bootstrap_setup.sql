do $$
declare
  v_payload jsonb;
  v_template_result jsonb;
  v_seed_result jsonb;
  v_schema_result jsonb;
  v_tenant_code text;
  v_schema_name text;
begin
  v_payload := public.platform_sim_i02_fixture_payload('complete_credential_setup_success', 'i02_gateway_credential_bootstrap');
  v_tenant_code := public.platform_normalize_tenant_code(v_payload->>'company_name');
  v_schema_result := public.platform_generate_schema_name(jsonb_build_object('tenant_code', v_tenant_code));
  v_schema_name := v_schema_result->'details'->>'schema_name';

  if v_schema_name is not null and public.platform_schema_exists(v_schema_name) then
    execute format('drop schema if exists %I cascade', v_schema_name);
  end if;

  insert into public.platform_access_role (role_code, role_scope, role_status, description, metadata)
  values ('i01_portal_user', 'tenant', 'active', 'I01 local certification role', jsonb_build_object('source', 'i02_local_runtime'))
  on conflict (role_code) do update
  set role_scope = excluded.role_scope,
      role_status = excluded.role_status,
      description = excluded.description,
      metadata = excluded.metadata,
      updated_at = timezone('utc', now());

  v_template_result := public.platform_register_template_version(jsonb_build_object(
    'template_version', 'foundation_local_v1',
    'template_scope', 'foundation',
    'template_status', 'released',
    'release_notes', jsonb_build_object(
      'source', 'i02_local_runtime',
      'purpose', 'credential_bootstrap_certification'
    )
  ));

  if coalesce((v_template_result->>'success')::boolean, false) is not true then
    raise exception 'I02 local foundation template seed failed: %', v_template_result::text;
  end if;

  v_seed_result := public.platform_sim_i02_seed_case(jsonb_build_object(
    'scenario', 'complete_credential_setup_success',
    'fixture_run_key', 'i02_gateway_credential_bootstrap'
  ));

  if coalesce((v_seed_result->>'success')::boolean, false) is not true then
    raise exception 'I02 credential-bootstrap seed failed: %', v_seed_result::text;
  end if;
end;
$$;

with seeded as (
  select public.platform_sim_i02_seed_case(jsonb_build_object(
    'scenario', 'complete_credential_setup_success',
    'fixture_run_key', 'i02_gateway_credential_bootstrap'
  )) as result
)
select json_build_object(
  'I02_REQUEST_KEY', result->'data'->>'request_key',
  'I02_PROVISION_REQUEST_ID', result->'data'->>'provision_request_id',
  'I02_CREDENTIAL_SETUP_TOKEN', result->'data'->>'credential_setup_token'
)::text
from seeded;
