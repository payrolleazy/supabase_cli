create or replace function public.platform_sim_i01_http_post(p_path text, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_request extensions.http_request;
  v_response extensions.http_response;
  v_body jsonb := '{}'::jsonb;
  v_base_url text := 'https://ztafqxxkqprudyorrhff.supabase.co';
  v_anon_key text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp0YWZxeHhrcXBydWR5b3JyaGZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQwMDgzNjEsImV4cCI6MjA4OTU4NDM2MX0.nLN1pYwu_z9ku3u3Qhk36fKkXURPgSlBednJoZ4OZNA';
begin
  perform extensions.http_reset_curlopt();
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT_MS', '15000');
  perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS', '5000');

  v_request := (
    'POST'::extensions.http_method,
    rtrim(v_base_url, '/') || p_path,
    array[
      row('Content-Type', 'application/json')::extensions.http_header,
      row('apikey', v_anon_key)::extensions.http_header
    ]::extensions.http_header[],
    'application/json',
    coalesce(p_payload, '{}'::jsonb)::text
  )::extensions.http_request;

  select * into v_response
  from extensions.http(v_request);

  begin
    v_body := coalesce(v_response.content, '{}')::jsonb;
  exception
    when others then
      v_body := jsonb_build_object('raw_content', coalesce(v_response.content, ''));
  end;

  perform extensions.http_reset_curlopt();

  return jsonb_build_object(
    'success', v_response.status between 200 and 299,
    'http_status', v_response.status,
    'body', v_body
  );
exception when others then
  perform extensions.http_reset_curlopt();
  return jsonb_build_object('success', false, 'error', sqlerrm);
end;
$$;

create or replace function public.platform_sim_i01_prepare_real_signin_subject(
  p_identity jsonb,
  p_fixture_run_key text,
  p_scenario text,
  p_tenant_id uuid,
  p_tenant_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invitation jsonb;
  v_signup_response jsonb;
  v_status_response jsonb;
  v_status_body jsonb := '{}'::jsonb;
  v_request_id uuid;
  v_status_token text;
  v_status text := '';
  v_user_id uuid;
  v_attempt integer;
begin
  v_invitation := public.platform_issue_membership_invitation(jsonb_build_object(
    'tenant_id', p_tenant_id,
    'invited_email', p_identity->>'email',
    'invited_mobile', p_identity->>'mobile_no',
    'role_code', 'i01_portal_user',
    'metadata', jsonb_build_object('fixture_run_key', p_fixture_run_key, 'scenario', p_scenario)
  ));

  if coalesce((v_invitation->>'success')::boolean, false) is not true then
    return jsonb_build_object('success', false, 'error', 'INVITATION_ISSUE_FAILED', 'details', v_invitation);
  end if;

  v_signup_response := public.platform_sim_i01_http_post(
    '/functions/v1/identity-signup-request',
    jsonb_build_object(
      'email', p_identity->>'email',
      'password', p_identity->>'password',
      'full_name', p_identity->>'full_name',
      'mobile_no', p_identity->>'mobile_no',
      'role_code', 'i01_portal_user'
    )
  );

  if coalesce((v_signup_response->>'success')::boolean, false) is not true
     or coalesce((v_signup_response->'body'->>'success')::boolean, false) is not true then
    return jsonb_build_object('success', false, 'error', 'SIGNUP_REQUEST_FAILED', 'details', v_signup_response);
  end if;

  v_request_id := nullif(v_signup_response->'body'->>'request_id', '')::uuid;
  v_status_token := nullif(v_signup_response->'body'->>'status_token', '');

  if v_request_id is null or v_status_token is null then
    return jsonb_build_object('success', false, 'error', 'SIGNUP_REQUEST_STATE_MISSING', 'details', v_signup_response);
  end if;

  for v_attempt in 1..12 loop
    v_status_response := public.platform_sim_i01_http_post(
      '/functions/v1/identity-signup-status',
      jsonb_build_object(
        'request_id', v_request_id,
        'status_token', v_status_token
      )
    );

    if coalesce((v_status_response->>'success')::boolean, false) is not true
       or coalesce((v_status_response->'body'->>'success')::boolean, false) is not true then
      perform pg_sleep(0.5);
      continue;
    end if;

    v_status_body := coalesce(v_status_response->'body', '{}'::jsonb);
    v_status := lower(coalesce(v_status_body->'request'->>'status', ''));

    exit when v_status in ('completed', 'failed');

    perform pg_sleep(0.5);
  end loop;

  if v_status <> 'completed' then
    return jsonb_build_object(
      'success', false,
      'error', 'SIGNUP_DID_NOT_COMPLETE',
      'details', jsonb_build_object(
        'signup_response', v_signup_response,
        'status_response', v_status_response,
        'request_status', v_status
      )
    );
  end if;

  select id into v_user_id
  from auth.users
  where lower(email) = lower(p_identity->>'email')
  limit 1;

  if v_user_id is null then
    return jsonb_build_object('success', false, 'error', 'AUTH_USER_NOT_FOUND_AFTER_SIGNUP');
  end if;

  return jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'user_id', v_user_id,
      'tenant_id', p_tenant_id,
      'tenant_code', p_tenant_code,
      'request_id', v_request_id,
      'status_token', v_status_token,
      'email', p_identity->>'email',
      'mobile_no', p_identity->>'mobile_no',
      'password', p_identity->>'password',
      'bad_password', p_identity->>'bad_password',
      'full_name', p_identity->>'full_name',
      'challenge_token', p_identity->>'challenge_token',
      'otp', p_identity->>'otp'
    )
  );
end;
$$;

create or replace function public.platform_sim_i01_seed_case(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_scenario text := lower(trim(coalesce(p_params->>'scenario', '')));
  v_fixture_run_key text := trim(coalesce(p_params->>'fixture_run_key', ''));
  v_identity jsonb;
  v_tenant_id uuid;
  v_tenant_code text;
  v_invitation jsonb;
  v_signup jsonb;
  v_signup_request_id uuid;
  v_challenge jsonb;
  v_user_id uuid;
begin
  if v_scenario = '' or v_fixture_run_key = '' then
    return jsonb_build_object('success', false, 'error', 'scenario and fixture_run_key are required');
  end if;

  insert into public.platform_access_role (
    role_code, role_scope, role_status, description, metadata
  ) values
    ('i01_portal_user', 'tenant', 'active', 'I01 simulator role', jsonb_build_object('source', 'application_i01_simulator')),
    ('i01_portal_unmatched', 'tenant', 'active', 'I01 simulator unmatched role', jsonb_build_object('source', 'application_i01_simulator'))
  on conflict (role_code) do update
  set role_scope = excluded.role_scope,
      role_status = excluded.role_status,
      description = excluded.description,
      metadata = excluded.metadata,
      updated_at = timezone('utc', now());

  insert into public.platform_signin_policy (
    policy_code, entrypoint_code, requires_password, requires_otp, allowed_role_codes, allowed_membership_statuses, policy_status, metadata
  ) values
    ('i01_password_only', 'employee_portal', true, false, array['i01_portal_user'], array['active'], 'active', jsonb_build_object('source', 'application_i01_simulator')),
    ('i01_email_otp', 'employee_portal', true, true, array['i01_portal_user'], array['active'], 'active', jsonb_build_object('source', 'application_i01_simulator')),
    ('i01_unmatched_policy', 'employee_portal', true, false, array['i01_portal_unmatched'], array['active'], 'active', jsonb_build_object('source', 'application_i01_simulator'))
  on conflict (policy_code) do update
  set entrypoint_code = excluded.entrypoint_code,
      requires_password = excluded.requires_password,
      requires_otp = excluded.requires_otp,
      allowed_role_codes = excluded.allowed_role_codes,
      allowed_membership_statuses = excluded.allowed_membership_statuses,
      policy_status = excluded.policy_status,
      metadata = excluded.metadata,
      updated_at = timezone('utc', now());

  v_identity := public.platform_sim_i01_fixture_identity(v_scenario, v_fixture_run_key);

  if v_scenario = 'signin_invalid_otp_challenge' then
    return jsonb_build_object(
      'success', true,
      'data', jsonb_build_object(
        'challenge_token', v_identity->>'challenge_token',
        'otp', v_identity->>'otp'
      )
    );
  end if;

  select tenant_id, tenant_code
    into v_tenant_id, v_tenant_code
  from public.platform_rm_tenant_registry
  where ready_for_routing = true
    and client_access_allowed = true
  order by tenant_code
  limit 1;

  if v_tenant_id is null then
    return jsonb_build_object('success', false, 'error', 'NO_ROUTE_READY_TENANT');
  end if;

  if v_scenario = 'signup_invited_success' then
    v_invitation := public.platform_issue_membership_invitation(jsonb_build_object(
      'tenant_id', v_tenant_id,
      'invited_email', v_identity->>'email',
      'invited_mobile', v_identity->>'mobile_no',
      'role_code', 'i01_portal_user',
      'metadata', jsonb_build_object('fixture_run_key', v_fixture_run_key, 'scenario', v_scenario)
    ));

    if coalesce((v_invitation->>'success')::boolean, false) is not true then
      return jsonb_build_object('success', false, 'error', 'INVITATION_ISSUE_FAILED', 'details', v_invitation);
    end if;

    return jsonb_build_object(
      'success', true,
      'data', jsonb_build_object(
        'tenant_id', v_tenant_id,
        'tenant_code', v_tenant_code,
        'email', v_identity->>'email',
        'mobile_no', v_identity->>'mobile_no',
        'password', v_identity->>'password',
        'full_name', v_identity->>'full_name'
      )
    );
  end if;

  if v_scenario = 'signup_rate_limited' then
    v_invitation := public.platform_issue_membership_invitation(jsonb_build_object(
      'tenant_id', v_tenant_id,
      'invited_email', v_identity->>'email',
      'invited_mobile', v_identity->>'mobile_no',
      'role_code', 'i01_portal_user',
      'metadata', jsonb_build_object('fixture_run_key', v_fixture_run_key, 'scenario', v_scenario)
    ));

    if coalesce((v_invitation->>'success')::boolean, false) is not true then
      return jsonb_build_object('success', false, 'error', 'INVITATION_ISSUE_FAILED', 'details', v_invitation);
    end if;

    insert into public.platform_signup_request (
      signup_request_id,
      invitation_id,
      email,
      mobile_no,
      request_status,
      decision_reason,
      status_token_hash,
      source_ip,
      user_agent,
      metadata,
      created_at,
      updated_at
    )
    select
      gen_random_uuid(),
      nullif(v_invitation->'details'->>'invitation_id', '')::uuid,
      v_identity->>'email',
      v_identity->>'mobile_no',
      'received',
      null,
      encode(extensions.digest(format('%s:%s:%s', v_fixture_run_key, v_scenario, seq.n), 'sha256'), 'hex'),
      'sim-i01-rate-limit',
      'sim-platform-runner',
      jsonb_build_object('fixture_run_key', v_fixture_run_key, 'scenario', v_scenario, 'seed_row', seq.n),
      timezone('utc', now()) - make_interval(mins => 1),
      timezone('utc', now()) - make_interval(mins => 1)
    from generate_series(1, 5) as seq(n);

    return jsonb_build_object(
      'success', true,
      'data', jsonb_build_object(
        'tenant_id', v_tenant_id,
        'tenant_code', v_tenant_code,
        'email', v_identity->>'email',
        'mobile_no', v_identity->>'mobile_no',
        'password', v_identity->>'password',
        'full_name', v_identity->>'full_name'
      )
    );
  end if;

  if v_scenario = 'signup_status_completed' then
    v_signup_request_id := gen_random_uuid();

    insert into public.platform_signup_request (
      signup_request_id,
      invitation_id,
      email,
      mobile_no,
      request_status,
      decision_reason,
      completed_at,
      status_token_hash,
      source_ip,
      user_agent,
      metadata,
      created_at,
      updated_at
    ) values (
      v_signup_request_id,
      null,
      v_identity->>'email',
      v_identity->>'mobile_no',
      'completed',
      'SIGNUP_COMPLETED',
      timezone('utc', now()),
      encode(extensions.digest(v_identity->>'status_token', 'sha256'), 'hex'),
      'sim-i01-status',
      'sim-platform-runner',
      jsonb_build_object('fixture_run_key', v_fixture_run_key, 'scenario', v_scenario),
      timezone('utc', now()),
      timezone('utc', now())
    );

    return jsonb_build_object(
      'success', true,
      'data', jsonb_build_object(
        'request_id', v_signup_request_id,
        'status_token', v_identity->>'status_token'
      )
    );
  end if;

  if v_scenario = 'signup_status_failed_auth_user_exists' then
    v_signup_request_id := gen_random_uuid();

    insert into public.platform_signup_request (
      signup_request_id,
      invitation_id,
      email,
      mobile_no,
      request_status,
      decision_reason,
      completed_at,
      status_token_hash,
      source_ip,
      user_agent,
      metadata,
      created_at,
      updated_at
    ) values (
      v_signup_request_id,
      null,
      v_identity->>'email',
      v_identity->>'mobile_no',
      'failed',
      'AUTH_USER_EXISTS',
      timezone('utc', now()),
      encode(extensions.digest(v_identity->>'status_token', 'sha256'), 'hex'),
      'sim-i01-status',
      'sim-platform-runner',
      jsonb_build_object('fixture_run_key', v_fixture_run_key, 'scenario', v_scenario),
      timezone('utc', now()),
      timezone('utc', now())
    );

    return jsonb_build_object(
      'success', true,
      'data', jsonb_build_object(
        'request_id', v_signup_request_id,
        'status_token', v_identity->>'status_token'
      )
    );
  end if;

  v_signup := public.platform_sim_i01_prepare_real_signin_subject(
    v_identity,
    v_fixture_run_key,
    v_scenario,
    v_tenant_id,
    v_tenant_code
  );

  if coalesce((v_signup->>'success')::boolean, false) is not true then
    return v_signup;
  end if;

  v_user_id := nullif(v_signup->'data'->>'user_id', '')::uuid;

  if v_user_id is null then
    return jsonb_build_object('success', false, 'error', 'REAL_SIGNUP_USER_ID_MISSING', 'details', v_signup);
  end if;

  if v_scenario = 'signin_rate_limited' then
    insert into public.platform_signin_attempt_log (
      actor_user_id,
      policy_code,
      identifier,
      identifier_type,
      attempt_result,
      source_ip,
      metadata,
      created_at
    )
    select
      v_user_id,
      'i01_password_only',
      lower(v_identity->>'email'),
      'email',
      'failed_credentials',
      'sim-i01-rate-limit',
      jsonb_build_object('fixture_run_key', v_fixture_run_key, 'scenario', v_scenario, 'seed_row', seq.n),
      timezone('utc', now()) - make_interval(mins => 1)
    from generate_series(1, 5) as seq(n);
  elsif v_scenario = 'signin_invalid_otp' then
    v_challenge := public.platform_issue_signin_challenge(jsonb_build_object(
      'actor_user_id', v_user_id,
      'policy_code', 'i01_email_otp',
      'challenge_token_hash', encode(extensions.digest(v_identity->>'challenge_token', 'sha256'), 'hex'),
      'source_ip', 'sim-i01-otp',
      'metadata', jsonb_build_object(
        'fixture_run_key', v_fixture_run_key,
        'scenario', v_scenario,
        'selected_tenant_id', v_tenant_id,
        'selected_tenant_code', v_tenant_code,
        'selected_role_codes', jsonb_build_array('i01_portal_user')
      )
    ));

    if coalesce((v_challenge->>'success')::boolean, false) is not true then
      return jsonb_build_object('success', false, 'error', 'CHALLENGE_ISSUE_FAILED', 'details', v_challenge);
    end if;
  end if;

  return jsonb_build_object(
    'success', true,
    'data', v_signup->'data'
  );
end;
$$;;
