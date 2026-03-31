create or replace function public.platform_sim_i02_fixture_payload(p_scenario text, p_fixture_run_key text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_scenario text := lower(trim(coalesce(p_scenario, '')));
  v_fixture_run_key text := trim(coalesce(p_fixture_run_key, ''));
  v_suffix text := substr(md5(v_fixture_run_key || ':' || v_scenario), 1, 12);
  v_request_hash text := substr(md5(v_fixture_run_key || ':' || v_scenario || ':request'), 1, 20);
  v_mobile_core text := translate(substr(md5(v_scenario || ':' || v_fixture_run_key || ':mobile'), 1, 9), 'abcdef', '123456');
  v_company_code text := upper(substr(v_suffix, 1, 6));
  v_request_key text;
  v_company_name text;
begin
  if v_scenario = '' or v_fixture_run_key = '' then
    raise exception 'scenario and fixture_run_key are required';
  end if;

  v_request_key := format('sim_i02_%s_%s', replace(v_scenario, '_', '_'), v_request_hash);
  v_company_name := format('Sim I02 %s %s', initcap(replace(v_scenario, '_', ' ')), v_company_code);

  return jsonb_build_object(
    'scenario', v_scenario,
    'fixture_run_key', v_fixture_run_key,
    'request_key', v_request_key,
    'request_id', v_request_key,
    'company_name', v_company_name,
    'legal_name', v_company_name || ' Pvt Ltd',
    'primary_contact_name', format('Sim Owner %s', v_company_code),
    'primary_work_email', lower(format('i02.%s.%s@example.com', replace(v_scenario, '_', '.'), v_suffix)),
    'primary_mobile', '9' || v_mobile_core,
    'selected_plan_code', 'i02_rt_free',
    'currency_code', 'INR',
    'country_code', 'IN',
    'timezone', 'Asia/Kolkata',
    'password', 'Owner@12345',
    'display_name', format('Sim Owner %s', v_company_code)
  );
end;
$function$;

create or replace function public.platform_sim_i02_cleanup_case(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_scenario text := lower(trim(coalesce(p_params->>'scenario', '')));
  v_fixture_run_key text := trim(coalesce(p_params->>'fixture_run_key', ''));
  v_payload jsonb;
  v_request_key text;
  v_email text;
  v_actor_user_id uuid;
  v_tenant_id uuid;
  v_provision_request_id uuid;
  v_lookup_tenant_id uuid;
  v_deleted_provision_requests integer := 0;
  v_deleted_tenants integer := 0;
  v_deleted_users integer := 0;
  v_deleted_identities integer := 0;
  v_deleted_actor_profiles integer := 0;
  v_deleted_memberships integer := 0;
  v_deleted_role_grants integer := 0;
  v_deleted_signin_challenges integer := 0;
  v_deleted_signin_attempts integer := 0;
  v_deleted_identity_events integer := 0;
  v_deleted_gateway_logs integer := 0;
  v_deleted_idempotency_claims integer := 0;
begin
  if v_scenario = '' or v_fixture_run_key = '' then
    return jsonb_build_object('success', false, 'error', 'scenario and fixture_run_key are required');
  end if;

  v_payload := public.platform_sim_i02_fixture_payload(v_scenario, v_fixture_run_key);
  v_request_key := v_payload->>'request_key';
  v_email := lower(coalesce(v_payload->>'primary_work_email', ''));

  select provision_request_id, tenant_id, owner_actor_user_id
    into v_provision_request_id, v_tenant_id, v_actor_user_id
  from public.platform_client_provision_request
  where request_key = v_request_key
  order by created_at desc
  limit 1;

  if v_actor_user_id is null and v_email <> '' then
    select id
      into v_actor_user_id
    from auth.users
    where lower(email) = v_email
    order by created_at desc
    limit 1;
  end if;

  if v_tenant_id is null and v_actor_user_id is not null then
    select tenant_id
      into v_lookup_tenant_id
    from public.platform_actor_tenant_membership
    where actor_user_id = v_actor_user_id
    order by linked_at desc nulls last, created_at desc
    limit 1;

    v_tenant_id := coalesce(v_tenant_id, v_lookup_tenant_id);
  end if;

  delete from public.platform_signin_challenge
  where (v_actor_user_id is not null and actor_user_id = v_actor_user_id)
     or (v_email <> '' and lower(coalesce(metadata->>'primary_work_email', metadata->>'email', '')) = v_email)
     or (v_provision_request_id is not null and coalesce(metadata->>'provision_request_id', '') = v_provision_request_id::text);
  get diagnostics v_deleted_signin_challenges = row_count;

  delete from public.platform_signin_attempt_log
  where (v_actor_user_id is not null and actor_user_id = v_actor_user_id)
     or (v_email <> '' and lower(coalesce(identifier, '')) = v_email)
     or (v_email <> '' and lower(coalesce(metadata->>'primary_work_email', metadata->>'email', '')) = v_email)
     or (v_provision_request_id is not null and coalesce(metadata->>'provision_request_id', '') = v_provision_request_id::text);
  get diagnostics v_deleted_signin_attempts = row_count;

  delete from public.platform_identity_event_log
  where (v_actor_user_id is not null and actor_user_id = v_actor_user_id)
     or (v_email <> '' and lower(coalesce(details->>'primary_email', details->>'email', '')) = v_email)
     or (v_provision_request_id is not null and coalesce(details->>'provision_request_id', '') = v_provision_request_id::text);
  get diagnostics v_deleted_identity_events = row_count;

  if v_actor_user_id is not null then
    delete from public.platform_actor_role_grant
    where actor_user_id = v_actor_user_id;
    get diagnostics v_deleted_role_grants = row_count;

    delete from public.platform_actor_tenant_membership
    where actor_user_id = v_actor_user_id;
    get diagnostics v_deleted_memberships = row_count;

    delete from public.platform_actor_profile
    where actor_user_id = v_actor_user_id;
    get diagnostics v_deleted_actor_profiles = row_count;
  end if;

  if v_tenant_id is not null then
    delete from public.platform_gateway_idempotency_claim
    where tenant_id = v_tenant_id;
    get diagnostics v_deleted_idempotency_claims = row_count;

    delete from public.platform_gateway_request_log
    where tenant_id = v_tenant_id;
    get diagnostics v_deleted_gateway_logs = row_count;

    delete from public.platform_tenant
    where tenant_id = v_tenant_id;
    get diagnostics v_deleted_tenants = row_count;
  end if;

  delete from public.platform_client_provision_request
  where request_key = v_request_key;
  get diagnostics v_deleted_provision_requests = row_count;

  delete from auth.identities
  where (v_actor_user_id is not null and user_id = v_actor_user_id)
     or (v_email <> '' and lower(coalesce(email, '')) = v_email);
  get diagnostics v_deleted_identities = row_count;

  delete from auth.users
  where (v_actor_user_id is not null and id = v_actor_user_id)
     or (v_email <> '' and lower(coalesce(email, '')) = v_email);
  get diagnostics v_deleted_users = row_count;

  return jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'scenario', v_scenario,
      'fixture_run_key', v_fixture_run_key,
      'request_key', v_request_key,
      'provision_request_id', v_provision_request_id,
      'tenant_id', v_tenant_id,
      'actor_user_id', v_actor_user_id,
      'deleted_provision_requests', v_deleted_provision_requests,
      'deleted_tenants', v_deleted_tenants,
      'deleted_users', v_deleted_users,
      'deleted_identities', v_deleted_identities,
      'deleted_actor_profiles', v_deleted_actor_profiles,
      'deleted_memberships', v_deleted_memberships,
      'deleted_role_grants', v_deleted_role_grants,
      'deleted_signin_challenges', v_deleted_signin_challenges,
      'deleted_signin_attempts', v_deleted_signin_attempts,
      'deleted_identity_events', v_deleted_identity_events,
      'deleted_gateway_logs', v_deleted_gateway_logs,
      'deleted_idempotency_claims', v_deleted_idempotency_claims
    )
  );
end;
$function$;

create or replace function public.platform_sim_i02_seed_case(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_scenario text := lower(trim(coalesce(p_params->>'scenario', '')));
  v_fixture_run_key text := trim(coalesce(p_params->>'fixture_run_key', ''));
  v_payload jsonb;
  v_capture_result jsonb;
  v_checkout_result jsonb;
  v_purchase_token_result jsonb;
  v_activation_result jsonb;
begin
  if v_scenario = '' or v_fixture_run_key = '' then
    return jsonb_build_object('success', false, 'error', 'scenario and fixture_run_key are required');
  end if;

  perform public.platform_sim_i02_cleanup_case(jsonb_build_object(
    'scenario', v_scenario,
    'fixture_run_key', v_fixture_run_key
  ));

  v_payload := public.platform_sim_i02_fixture_payload(v_scenario, v_fixture_run_key);

  if v_scenario = 'capture_intent_success' then
    return jsonb_build_object('success', true, 'data', v_payload);
  end if;

  v_capture_result := public.platform_capture_client_provision_intent(jsonb_build_object(
    'request_key', v_payload->>'request_key',
    'company_name', v_payload->>'company_name',
    'legal_name', v_payload->>'legal_name',
    'primary_contact_name', v_payload->>'primary_contact_name',
    'primary_work_email', v_payload->>'primary_work_email',
    'primary_mobile', v_payload->>'primary_mobile',
    'selected_plan_code', v_payload->>'selected_plan_code',
    'currency_code', v_payload->>'currency_code',
    'country_code', v_payload->>'country_code',
    'timezone', v_payload->>'timezone',
    'request_source', 'simulator',
    'source_ip', 'sim-i02',
    'user_agent', 'sim-platform-runner',
    'metadata', jsonb_build_object(
      'fixture_run_key', v_fixture_run_key,
      'scenario', v_scenario,
      'seed_strategy', 'application_i02_simulator'
    )
  ));

  if coalesce((v_capture_result->>'success')::boolean, false) is not true then
    return jsonb_build_object('success', false, 'error', 'CAPTURE_INTENT_FAILED', 'details', v_capture_result);
  end if;

  v_payload := v_payload || jsonb_build_object(
    'provision_request_id', v_capture_result->'details'->>'provision_request_id'
  );

  if v_scenario = 'initiate_free_checkout_success' then
    return jsonb_build_object('success', true, 'data', v_payload);
  end if;

  v_checkout_result := public.platform_create_or_resume_public_checkout(jsonb_build_object(
    'request_key', v_payload->>'request_key',
    'provider_code', 'internal_free',
    'quoted_amount', 0,
    'metadata', jsonb_build_object(
      'fixture_run_key', v_fixture_run_key,
      'scenario', v_scenario,
      'seed_strategy', 'application_i02_simulator'
    )
  ));

  if coalesce((v_checkout_result->>'success')::boolean, false) is not true then
    return jsonb_build_object('success', false, 'error', 'CHECKOUT_STAGE_FAILED', 'details', v_checkout_result);
  end if;

  v_payload := v_payload || jsonb_build_object(
    'checkout_id', v_checkout_result->'details'->>'checkout_id'
  );

  if v_scenario = 'activate_after_purchase_success' then
    v_purchase_token_result := public.platform_issue_owner_bootstrap_token(jsonb_build_object(
      'request_key', v_payload->>'request_key',
      'token_purpose', 'purchase_activation',
      'expires_in_minutes', 60,
      'metadata', jsonb_build_object(
        'fixture_run_key', v_fixture_run_key,
        'scenario', v_scenario,
        'seed_strategy', 'application_i02_simulator'
      )
    ));

    if coalesce((v_purchase_token_result->>'success')::boolean, false) is not true then
      return jsonb_build_object('success', false, 'error', 'PURCHASE_TOKEN_STAGE_FAILED', 'details', v_purchase_token_result);
    end if;

    return jsonb_build_object(
      'success', true,
      'data', v_payload || jsonb_build_object(
        'purchase_activation_token', v_purchase_token_result->'details'->>'token',
        'purchase_activation_token_id', v_purchase_token_result->'details'->>'token_id'
      )
    );
  end if;

  if v_scenario = 'complete_credential_setup_success' then
    v_purchase_token_result := public.platform_issue_owner_bootstrap_token(jsonb_build_object(
      'request_key', v_payload->>'request_key',
      'token_purpose', 'purchase_activation',
      'expires_in_minutes', 60,
      'metadata', jsonb_build_object(
        'fixture_run_key', v_fixture_run_key,
        'scenario', v_scenario,
        'seed_strategy', 'application_i02_simulator'
      )
    ));

    if coalesce((v_purchase_token_result->>'success')::boolean, false) is not true then
      return jsonb_build_object('success', false, 'error', 'PURCHASE_TOKEN_STAGE_FAILED', 'details', v_purchase_token_result);
    end if;

    v_activation_result := public.platform_accept_purchase_activation(jsonb_build_object(
      'token', v_purchase_token_result->'details'->>'token',
      'credential_setup_expires_in_minutes', 1440
    ));

    if coalesce((v_activation_result->>'success')::boolean, false) is not true then
      return jsonb_build_object('success', false, 'error', 'PURCHASE_ACTIVATION_STAGE_FAILED', 'details', v_activation_result);
    end if;

    return jsonb_build_object(
      'success', true,
      'data', v_payload || jsonb_build_object(
        'credential_setup_token', v_activation_result->'details'->>'credential_setup_token',
        'credential_setup_token_id', v_activation_result->'details'->>'credential_setup_token_id'
      )
    );
  end if;

  return jsonb_build_object('success', false, 'error', 'UNKNOWN_SCENARIO', 'details', jsonb_build_object('scenario', v_scenario));
end;
$function$;;
