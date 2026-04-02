select public.platform_sim_i02_cleanup_case(jsonb_build_object(
  'scenario', 'activate_after_purchase_success',
  'fixture_run_key', 'i02_gateway_activate_after_purchase'
))::text;
