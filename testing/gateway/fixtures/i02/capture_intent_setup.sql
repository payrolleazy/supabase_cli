do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_sim_i02_seed_case(jsonb_build_object(
    'scenario', 'capture_intent_success',
    'fixture_run_key', 'i02_gateway_capture_intent'
  ));

  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'I02 capture intent seed failed: %', v_result::text;
  end if;
end;
$$;

with seeded as (
  select public.platform_sim_i02_fixture_payload('capture_intent_success', 'i02_gateway_capture_intent') as payload
)
select json_build_object(
  'I02_REQUEST_KEY', payload->>'request_key',
  'I02_COMPANY_NAME', payload->>'company_name',
  'I02_LEGAL_NAME', payload->>'legal_name',
  'I02_PRIMARY_CONTACT_NAME', payload->>'primary_contact_name',
  'I02_PRIMARY_WORK_EMAIL', payload->>'primary_work_email',
  'I02_PRIMARY_MOBILE', payload->>'primary_mobile',
  'I02_SELECTED_PLAN_CODE', payload->>'selected_plan_code'
)::text
from seeded;
