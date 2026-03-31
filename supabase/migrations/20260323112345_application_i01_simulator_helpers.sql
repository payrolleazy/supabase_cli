create or replace function public.platform_sim_i01_fixture_identity(
  p_scenario text,
  p_fixture_run_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_scenario text := lower(trim(coalesce(p_scenario, '')));
  v_fixture_run_key text := trim(coalesce(p_fixture_run_key, ''));
  v_suffix text := substr(md5(v_fixture_run_key || ':' || v_scenario), 1, 12);
  v_mobile_core text := translate(substr(md5(v_scenario || ':' || v_fixture_run_key), 1, 9), 'abcdef', '123456');
  v_email text;
  v_full_name text;
begin
  if v_scenario = '' or v_fixture_run_key = '' then
    raise exception 'scenario and fixture_run_key are required';
  end if;

  v_email := format('i01.%s.%s@example.com', replace(v_scenario, '_', '.'), v_suffix);
  v_full_name := format('I01 %s %s', initcap(replace(v_scenario, '_', ' ')), substr(v_suffix, 1, 8));

  return jsonb_build_object(
    'scenario', v_scenario,
    'fixture_run_key', v_fixture_run_key,
    'email', lower(v_email),
    'mobile_no', '9' || v_mobile_core,
    'password', 'Default@123',
    'bad_password', 'Wrong@123',
    'full_name', v_full_name,
    'status_token', format('i01-status-%s-%s-token-bridge-2026', replace(v_scenario, '_', '-'), substr(md5(v_fixture_run_key), 1, 20)),
    'challenge_token', format('i01-challenge-%s-%s-token-bridge-2026', replace(v_scenario, '_', '-'), substr(md5(v_fixture_run_key || ':challenge'), 1, 20)),
    'otp', '00000000'
  );
end;
$function$;

create or replace function public.platform_sim_i01_seed_case(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_scenario text := lower(trim(coalesce(p_params->>'scenario', '')));
  v_fixture_run_key text := trim(coalesce(p_params->>'fixture_run_key', ''));
  v_identity jsonb;
  v_tenant_id uuid;
  v_tenant_code text;
  v_invitation jsonb;
  v_invitation_id uuid;
  v_user_id uuid;
  v_signup_request_id uuid;
  v_completion jsonb;
  v_challenge jsonb;
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

  v_user_id := gen_random_uuid();

  insert into auth.users (
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    phone,
    created_at,
    updated_at,
    is_sso_user,
    is_anonymous
  ) values (
    v_user_id,
    'authenticated',
    'authenticated',
    v_identity->>'email',
    extensions.crypt(v_identity->>'password', extensions.gen_salt('bf')),
    timezone('utc', now()),
    timezone('utc', now()),
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    jsonb_build_object('display_name', v_identity->>'full_name', 'primary_mobile', v_identity->>'mobile_no', 'fixture_run_key', v_fixture_run_key, 'scenario', v_scenario),
    v_identity->>'mobile_no',
    timezone('utc', now()),
    timezone('utc', now()),
    false,
    false
  );

  insert into auth.identities (
    provider_id,
    user_id,
    identity_data,
    provider,
    email,
    created_at,
    updated_at
  ) values (
    v_user_id::text,
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_identity->>'email', 'email_verified', false, 'phone_verified', false),
    'email',
    v_identity->>'email',
    timezone('utc', now()),
    timezone('utc', now())
  );

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

  v_invitation_id := nullif(v_invitation->'details'->>'invitation_id', '')::uuid;
  v_signup_request_id := gen_random_uuid();

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
  ) values (
    v_signup_request_id,
    v_invitation_id,
    v_identity->>'email',
    v_identity->>'mobile_no',
    'processing',
    'SIMULATOR_PREPARED',
    encode(extensions.digest(v_identity->>'status_token', 'sha256'), 'hex'),
    'sim-i01-seed',
    'sim-platform-runner',
    jsonb_build_object('fixture_run_key', v_fixture_run_key, 'scenario', v_scenario),
    timezone('utc', now()),
    timezone('utc', now())
  );

  v_completion := public.platform_complete_invited_signup(jsonb_build_object(
    'signup_request_id', v_signup_request_id,
    'actor_user_id', v_user_id,
    'email', v_identity->>'email',
    'mobile_no', v_identity->>'mobile_no',
    'display_name', v_identity->>'full_name'
  ));

  if coalesce((v_completion->>'success')::boolean, false) is not true then
    return jsonb_build_object('success', false, 'error', 'SIGNUP_COMPLETION_FAILED', 'details', v_completion);
  end if;

  if v_scenario = 'signin_rate_limited' then
    insert into public.platform_signin_attempt_log (
      attempt_id,
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
      gen_random_uuid(),
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
    'data', jsonb_build_object(
      'tenant_id', v_tenant_id,
      'tenant_code', v_tenant_code,
      'email', v_identity->>'email',
      'mobile_no', v_identity->>'mobile_no',
      'password', v_identity->>'password',
      'bad_password', v_identity->>'bad_password',
      'full_name', v_identity->>'full_name',
      'challenge_token', v_identity->>'challenge_token',
      'otp', v_identity->>'otp'
    )
  );
end;
$function$;

create or replace function public.platform_sim_i01_cleanup_case(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_scenario text := lower(trim(coalesce(p_params->>'scenario', '')));
  v_fixture_run_key text := trim(coalesce(p_params->>'fixture_run_key', ''));
  v_identity jsonb;
  v_user_id uuid;
  v_deleted_users integer := 0;
  v_deleted_requests integer := 0;
  v_deleted_invitations integer := 0;
begin
  if v_scenario = '' or v_fixture_run_key = '' then
    return jsonb_build_object('success', false, 'error', 'scenario and fixture_run_key are required');
  end if;

  v_identity := public.platform_sim_i01_fixture_identity(v_scenario, v_fixture_run_key);

  select id into v_user_id
  from auth.users
  where lower(email) = lower(v_identity->>'email')
  limit 1;

  delete from public.platform_signin_challenge
  where (v_user_id is not null and actor_user_id = v_user_id)
     or coalesce(metadata->>'fixture_run_key', '') = v_fixture_run_key;

  delete from public.platform_signin_attempt_log
  where lower(identifier) = lower(v_identity->>'email')
     or (v_user_id is not null and actor_user_id = v_user_id)
     or coalesce(metadata->>'fixture_run_key', '') = v_fixture_run_key;

  delete from public.platform_actor_role_grant
  where v_user_id is not null and actor_user_id = v_user_id;

  delete from public.platform_actor_tenant_membership
  where v_user_id is not null and actor_user_id = v_user_id;

  delete from public.platform_identity_event_log
  where (v_user_id is not null and actor_user_id = v_user_id)
     or coalesce(details->>'fixture_run_key', '') = v_fixture_run_key;

  delete from public.platform_actor_profile
  where v_user_id is not null and actor_user_id = v_user_id;

  delete from public.platform_signup_request
  where lower(email) = lower(v_identity->>'email')
    and mobile_no = v_identity->>'mobile_no';
  get diagnostics v_deleted_requests = row_count;

  delete from public.platform_membership_invitation
  where lower(invited_email) = lower(v_identity->>'email')
    and invited_mobile = v_identity->>'mobile_no';
  get diagnostics v_deleted_invitations = row_count;

  delete from auth.identities
  where (v_user_id is not null and user_id = v_user_id)
     or lower(email) = lower(v_identity->>'email');

  delete from auth.users
  where (v_user_id is not null and id = v_user_id)
     or lower(email) = lower(v_identity->>'email');
  get diagnostics v_deleted_users = row_count;

  return jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'deleted_users', v_deleted_users,
      'deleted_signup_requests', v_deleted_requests,
      'deleted_invitations', v_deleted_invitations,
      'email', v_identity->>'email'
    )
  );
end;
$function$;

revoke all on function public.platform_sim_i01_fixture_identity(text, text) from public, anon, authenticated;
revoke all on function public.platform_sim_i01_seed_case(jsonb) from public, anon, authenticated;
revoke all on function public.platform_sim_i01_cleanup_case(jsonb) from public, anon, authenticated;

grant execute on function public.platform_sim_i01_fixture_identity(text, text) to service_role;
grant execute on function public.platform_sim_i01_seed_case(jsonb) to service_role;
grant execute on function public.platform_sim_i01_cleanup_case(jsonb) to service_role;;
