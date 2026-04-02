do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_sim_i02_seed_case(jsonb_build_object(
    'scenario', 'activate_after_purchase_success',
    'fixture_run_key', 'i02_gateway_resolve_checkout'
  ));

  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'I02 resolve-checkout seed failed: %', v_result::text;
  end if;
end;
$$;

with seeded as (
  select public.platform_sim_i02_seed_case(jsonb_build_object(
    'scenario', 'activate_after_purchase_success',
    'fixture_run_key', 'i02_gateway_resolve_checkout'
  )) as result
)
select json_build_object(
  'I02_REQUEST_KEY', result->'data'->>'request_key',
  'I02_PROVISION_REQUEST_ID', result->'data'->>'provision_request_id'
)::text
from seeded;
