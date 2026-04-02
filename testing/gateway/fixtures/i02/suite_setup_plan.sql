do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_plan(jsonb_build_object(
    'plan_code', 'i02_rt_free',
    'plan_name', 'I02 Runtime Free',
    'status', 'active',
    'billing_cadence', 'monthly',
    'currency_code', 'INR',
    'description', 'Deterministic local I02 certification plan.',
    'metadata', jsonb_build_object(
      'is_free_plan', true,
      'base_amount', 0,
      'certification_seed', 'i02_local_runtime'
    )
  ));

  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'I02 plan registration failed: %', v_result::text;
  end if;
end;
$$;

select json_build_object(
  'I02_PLAN_CODE', 'i02_rt_free'
)::text;
