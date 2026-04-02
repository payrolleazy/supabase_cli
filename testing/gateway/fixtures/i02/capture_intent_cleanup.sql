select public.platform_sim_i02_cleanup_case(jsonb_build_object(
  'scenario', 'capture_intent_success',
  'fixture_run_key', 'i02_gateway_capture_intent'
))::text;
