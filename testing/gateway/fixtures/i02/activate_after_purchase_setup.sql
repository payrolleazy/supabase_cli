do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_sim_i02_seed_case(jsonb_build_object(
    'scenario', 'activate_after_purchase_success',
    'fixture_run_key', 'i02_gateway_activate_after_purchase'
  ));

  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'I02 activate-after-purchase seed failed: %', v_result::text;
  end if;
end;
$$;

with seeded as (
  select public.platform_sim_i02_seed_case(jsonb_build_object(
    'scenario', 'activate_after_purchase_success',
    'fixture_run_key', 'i02_gateway_activate_after_purchase'
  )) as result
)
select json_build_object(
  'I02_REQUEST_KEY', result->'data'->>'request_key',
  'I02_PROVISION_REQUEST_ID', result->'data'->>'provision_request_id',
  'I02_PURCHASE_ACTIVATION_TOKEN', result->'data'->>'purchase_activation_token'
)::text
from seeded;
