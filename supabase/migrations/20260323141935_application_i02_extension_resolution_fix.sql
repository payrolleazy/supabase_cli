create or replace function public.platform_issue_owner_bootstrap_token(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_id uuid := public.platform_i02_resolve_provision_request_id(p_params);
  v_token_purpose text := lower(coalesce(nullif(btrim(p_params->>'token_purpose'), ''), ''));
  v_expires_in_minutes integer := coalesce(nullif(p_params->>'expires_in_minutes', '')::integer, 1440);
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_request public.platform_client_provision_request%rowtype;
  v_raw_token text;
  v_token_hash text;
  v_token public.platform_owner_bootstrap_token%rowtype;
begin
  if v_request_id is null then
    return public.platform_json_response(false, 'PROVISION_REQUEST_ID_REQUIRED', 'provision_request_id or request_key is required.', '{}'::jsonb);
  end if;
  if v_token_purpose not in ('purchase_activation', 'credential_setup') then
    return public.platform_json_response(false, 'TOKEN_PURPOSE_REQUIRED', 'token_purpose must be purchase_activation or credential_setup.', jsonb_build_object('token_purpose', v_token_purpose));
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  select *
  into v_request
  from public.platform_client_provision_request
  where provision_request_id = v_request_id
  for update;

  if not found then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_FOUND', 'Provision request not found.', jsonb_build_object('provision_request_id', v_request_id));
  end if;

  if v_token_purpose = 'purchase_activation'
     and v_request.provisioning_status not in ('activation_ready', 'payment_paid') then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_ACTIVATION_READY', 'Provision request is not ready for purchase activation.', jsonb_build_object('provisioning_status', v_request.provisioning_status));
  end if;

  if v_token_purpose = 'credential_setup'
     and v_request.provisioning_status not in ('credential_setup_required', 'activation_ready', 'payment_paid') then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_CREDENTIAL_SETUP_READY', 'Provision request is not ready for credential setup.', jsonb_build_object('provisioning_status', v_request.provisioning_status));
  end if;

  update public.platform_owner_bootstrap_token
  set token_status = 'revoked',
      updated_at = timezone('utc', now())
  where provision_request_id = v_request_id
    and token_purpose = v_token_purpose
    and token_status = 'issued';

  v_raw_token := encode(extensions.gen_random_bytes(24), 'hex');
  v_token_hash := public.platform_i02_hash_token(v_raw_token);

  insert into public.platform_owner_bootstrap_token (
    provision_request_id,
    token_purpose,
    token_hash,
    token_status,
    issued_for_email,
    expires_at,
    metadata
  )
  values (
    v_request_id,
    v_token_purpose,
    v_token_hash,
    'issued',
    v_request.primary_work_email,
    timezone('utc', now()) + make_interval(mins => v_expires_in_minutes),
    v_metadata
  )
  returning *
  into v_token;

  update public.platform_client_provision_request
  set provisioning_status = case
        when v_token_purpose = 'purchase_activation' then 'activation_ready'
        when provisioning_status in ('activation_ready', 'payment_paid') then 'credential_setup_required'
        else provisioning_status
      end,
      next_action = case
        when v_token_purpose = 'purchase_activation' then 'purchase_activation'
        else 'credential_setup'
      end,
      updated_at = timezone('utc', now())
  where provision_request_id = v_request_id;

  perform public.platform_i02_append_provision_event(jsonb_build_object(
    'provision_request_id', v_request_id,
    'event_type', v_token_purpose || '_token_issued',
    'event_source', 'platform_issue_owner_bootstrap_token',
    'event_message', 'Owner bootstrap token issued.',
    'event_details', jsonb_build_object(
      'token_id', v_token.token_id,
      'token_purpose', v_token_purpose,
      'expires_at', v_token.expires_at
    )
  ));

  return public.platform_json_response(
    true,
    'OK',
    'Owner bootstrap token issued.',
    jsonb_build_object(
      'token_id', v_token.token_id,
      'provision_request_id', v_request_id,
      'token_purpose', v_token_purpose,
      'token', v_raw_token,
      'expires_at', v_token.expires_at
    )
  );
end;
$function$;

;
