create or replace function public.platform_sim_i01_fixture_identity(p_scenario text, p_fixture_run_key text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_scenario text := lower(trim(coalesce(p_scenario, '')));
  v_fixture_run_key text := trim(coalesce(p_fixture_run_key, ''));
  v_suffix text := substr(md5(v_fixture_run_key || ':' || v_scenario), 1, 12);
  v_mobile_core text := translate(substr(md5(v_scenario || ':' || v_fixture_run_key), 1, 9), 'abcdef', '123456');
  v_email text;
  v_mobile text;
  v_full_name text;
  v_shared_identity boolean := v_scenario in (
    'signin_password_success',
    'signin_access_not_available',
    'signin_invalid_credentials',
    'signin_rate_limited',
    'signin_otp_delivery_unavailable',
    'signin_invalid_otp'
  );
begin
  if v_scenario = '' or v_fixture_run_key = '' then
    raise exception 'scenario and fixture_run_key are required';
  end if;

  if v_scenario = 'signin_otp_delivery_unavailable' then
    v_email := 'i01.sim.otp.delivery.20260323@example.com';
    v_mobile := '9988776633';
    v_full_name := 'I01 OTP Delivery Identity';
  elsif v_shared_identity and v_scenario = 'signin_invalid_otp' then
    v_email := 'i01.sim.otp.shared.20260323@example.com';
    v_mobile := '9988776644';
    v_full_name := 'I01 OTP Shared Identity';
  elsif v_shared_identity then
    v_email := 'i01.sim.identity.shared.20260323@example.com';
    v_mobile := '9988776655';
    v_full_name := 'I01 Shared Identity';
  else
    v_email := format('i01.%s.%s@example.com', replace(v_scenario, '_', '.'), v_suffix);
    v_mobile := '9' || v_mobile_core;
    v_full_name := format('I01 %s %s', initcap(replace(v_scenario, '_', ' ')), substr(v_suffix, 1, 8));
  end if;

  return jsonb_build_object(
    'scenario', v_scenario,
    'fixture_run_key', v_fixture_run_key,
    'shared_identity', v_shared_identity,
    'email', lower(v_email),
    'mobile_no', v_mobile,
    'password', 'Default@123',
    'bad_password', 'Wrong@123',
    'full_name', v_full_name,
    'status_token', format('i01-status-%s-%s-token-bridge-2026', replace(v_scenario, '_', '-'), substr(md5(v_fixture_run_key), 1, 20)),
    'challenge_token', format('i01-challenge-%s-%s-token-bridge-2026', replace(v_scenario, '_', '-'), substr(md5(v_fixture_run_key || ':challenge'), 1, 20)),
    'otp', '00000000'
  );
end;
$$;;
