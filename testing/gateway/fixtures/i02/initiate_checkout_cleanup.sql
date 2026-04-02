select public.platform_sim_i02_cleanup_case(jsonb_build_object(
  'scenario', 'initiate_free_checkout_success',
  'fixture_run_key', 'i02_gateway_initiate_checkout'
))::text;
