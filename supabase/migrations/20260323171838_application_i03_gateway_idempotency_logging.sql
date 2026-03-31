create or replace function public.platform_claim_gateway_idempotency(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_operation_code text := nullif(btrim(p_params->>'operation_code'), '');
  v_idempotency_key text := nullif(btrim(p_params->>'idempotency_key'), '');
  v_actor_user_id uuid := public.platform_current_actor_user_id();
  v_tenant_id uuid := public.platform_current_tenant_id();
  v_request_payload jsonb := coalesce(p_params->'request_payload', '{}'::jsonb);
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_expires_in_minutes integer := 1440;
  v_existing public.platform_gateway_idempotency_claim%rowtype;
begin
  if v_operation_code is null then
    return public.platform_json_response(false, 'OPERATION_CODE_REQUIRED', 'operation_code is required.', '{}'::jsonb);
  end if;

  if v_idempotency_key is null then
    return public.platform_json_response(false, 'IDEMPOTENCY_KEY_REQUIRED', 'idempotency_key is required.', '{}'::jsonb);
  end if;

  if v_actor_user_id is null or v_tenant_id is null then
    return public.platform_json_response(false, 'EXECUTION_CONTEXT_REQUIRED', 'Actor and tenant execution context are required.', '{}'::jsonb);
  end if;

  if jsonb_typeof(v_request_payload) <> 'object' or jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_JSON_INPUT', 'request_payload and metadata must be JSON objects.', '{}'::jsonb);
  end if;

  if nullif(p_params->>'expires_in_minutes', '') is not null then
    begin
      v_expires_in_minutes := greatest((p_params->>'expires_in_minutes')::integer, 1);
    exception
      when others then
        return public.platform_json_response(false, 'INVALID_EXPIRY_MINUTES', 'expires_in_minutes must be an integer.', '{}'::jsonb);
    end;
  end if;

  select *
  into v_existing
  from public.platform_gateway_idempotency_claim
  where operation_code = v_operation_code
    and tenant_id = v_tenant_id
    and actor_user_id = v_actor_user_id
    and idempotency_key = v_idempotency_key;

  if found then
    if v_existing.claim_status = 'succeeded' then
      return public.platform_json_response(true, 'IDEMPOTENT_REPLAY', 'Prior successful response replayed.', jsonb_build_object(
        'claim_id', v_existing.claim_id,
        'claim_status', v_existing.claim_status,
        'response_payload', v_existing.response_payload
      ));
    elsif v_existing.claim_status = 'claimed' and v_existing.expires_at > timezone('utc', now()) then
      return public.platform_json_response(false, 'IDEMPOTENCY_IN_PROGRESS', 'An in-flight request already holds this idempotency key.', jsonb_build_object(
        'claim_id', v_existing.claim_id,
        'claim_status', v_existing.claim_status,
        'expires_at', v_existing.expires_at
      ));
    else
      update public.platform_gateway_idempotency_claim
      set claim_status = 'claimed',
          request_hash = md5(v_request_payload::text),
          request_payload = v_request_payload,
          response_payload = '{}'::jsonb,
          error_payload = '{}'::jsonb,
          claimed_at = timezone('utc', now()),
          completed_at = null,
          expires_at = timezone('utc', now()) + make_interval(mins => v_expires_in_minutes),
          metadata = v_metadata
      where claim_id = v_existing.claim_id;

      return public.platform_json_response(true, 'OK', 'Idempotency claim refreshed.', jsonb_build_object(
        'claim_id', v_existing.claim_id,
        'claim_status', 'claimed'
      ));
    end if;
  end if;

  insert into public.platform_gateway_idempotency_claim (
    operation_code,
    tenant_id,
    actor_user_id,
    idempotency_key,
    claim_status,
    request_hash,
    request_payload,
    expires_at,
    metadata
  ) values (
    v_operation_code,
    v_tenant_id,
    v_actor_user_id,
    v_idempotency_key,
    'claimed',
    md5(v_request_payload::text),
    v_request_payload,
    timezone('utc', now()) + make_interval(mins => v_expires_in_minutes),
    v_metadata
  )
  returning *
  into v_existing;

  return public.platform_json_response(true, 'OK', 'Idempotency claim created.', jsonb_build_object(
    'claim_id', v_existing.claim_id,
    'claim_status', v_existing.claim_status
  ));
end;
$function$;

create or replace function public.platform_log_gateway_request(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_id uuid := coalesce(public.platform_try_uuid(p_params->>'request_id'), gen_random_uuid());
  v_operation_code text := nullif(btrim(p_params->>'operation_code'), '');
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_tenant_id uuid := coalesce(public.platform_try_uuid(p_params->>'tenant_id'), public.platform_current_tenant_id());
  v_execution_mode text := lower(coalesce(nullif(p_params->>'execution_mode', ''), nullif(current_setting('platform.execution_mode', true), '')));
  v_operation_mode text := lower(coalesce(nullif(p_params->>'operation_mode', ''), ''));
  v_dispatch_kind text := lower(coalesce(nullif(p_params->>'dispatch_kind', ''), ''));
  v_request_status text := lower(coalesce(nullif(p_params->>'request_status', ''), 'failed'));
  v_error_code text := nullif(btrim(p_params->>'error_code'), '');
  v_duration_ms integer;
  v_idempotency_key text := nullif(btrim(p_params->>'idempotency_key'), '');
  v_request_payload jsonb := coalesce(p_params->'request_payload', '{}'::jsonb);
  v_response_payload jsonb := coalesce(p_params->'response_payload', '{}'::jsonb);
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
begin
  if v_request_status not in ('succeeded', 'failed', 'replayed', 'blocked') then
    return public.platform_json_response(false, 'INVALID_REQUEST_STATUS', 'request_status is invalid.', jsonb_build_object('request_status', v_request_status));
  end if;

  if jsonb_typeof(v_request_payload) <> 'object'
    or jsonb_typeof(v_response_payload) <> 'object'
    or jsonb_typeof(v_metadata) <> 'object'
  then
    return public.platform_json_response(false, 'INVALID_JSON_INPUT', 'request_payload, response_payload, and metadata must be JSON objects.', '{}'::jsonb);
  end if;

  if nullif(p_params->>'duration_ms', '') is not null then
    begin
      v_duration_ms := greatest((p_params->>'duration_ms')::integer, 0);
    exception
      when others then
        return public.platform_json_response(false, 'INVALID_DURATION_MS', 'duration_ms must be an integer.', '{}'::jsonb);
    end;
  end if;

  insert into public.platform_gateway_request_log (
    request_id,
    operation_code,
    actor_user_id,
    tenant_id,
    execution_mode,
    operation_mode,
    dispatch_kind,
    request_status,
    error_code,
    duration_ms,
    idempotency_key,
    request_payload,
    response_payload,
    metadata
  ) values (
    v_request_id,
    v_operation_code,
    v_actor_user_id,
    v_tenant_id,
    v_execution_mode,
    v_operation_mode,
    v_dispatch_kind,
    v_request_status,
    v_error_code,
    v_duration_ms,
    v_idempotency_key,
    v_request_payload,
    v_response_payload,
    v_metadata
  )
  on conflict (request_id) do update
  set operation_code = excluded.operation_code,
      actor_user_id = excluded.actor_user_id,
      tenant_id = excluded.tenant_id,
      execution_mode = excluded.execution_mode,
      operation_mode = excluded.operation_mode,
      dispatch_kind = excluded.dispatch_kind,
      request_status = excluded.request_status,
      error_code = excluded.error_code,
      duration_ms = excluded.duration_ms,
      idempotency_key = excluded.idempotency_key,
      request_payload = excluded.request_payload,
      response_payload = excluded.response_payload,
      metadata = excluded.metadata;

  return public.platform_json_response(true, 'OK', 'Gateway request log recorded.', jsonb_build_object('request_id', v_request_id));
end;
$function$;

create or replace function public.platform_update_gateway_operation_metadata(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_target_operation_code text := nullif(btrim(coalesce(p_params->>'target_operation_code', p_params->>'operation_code')), '');
  v_metadata_patch jsonb := coalesce(p_params->'metadata_patch', '{}'::jsonb);
  v_actor_user_id uuid := coalesce(public.platform_current_actor_user_id(), public.platform_try_uuid(p_params->>'actor_user_id'));
  v_updated jsonb;
begin
  if v_target_operation_code is null then
    return public.platform_json_response(false, 'TARGET_OPERATION_CODE_REQUIRED', 'target_operation_code is required.', '{}'::jsonb);
  end if;

  if jsonb_typeof(v_metadata_patch) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA_PATCH', 'metadata_patch must be a JSON object.', '{}'::jsonb);
  end if;

  update public.platform_gateway_operation
  set metadata = coalesce(metadata, '{}'::jsonb) || v_metadata_patch,
      updated_at = timezone('utc', now()),
      updated_by = v_actor_user_id
  where operation_code = v_target_operation_code
  returning jsonb_build_object(
    'operation_code', operation_code,
    'metadata', metadata,
    'updated_by', updated_by
  )
  into v_updated;

  if v_updated is null then
    return public.platform_json_response(false, 'OPERATION_NOT_FOUND', 'Gateway operation not found.', jsonb_build_object('operation_code', v_target_operation_code));
  end if;

  return public.platform_json_response(true, 'OK', 'Gateway operation metadata updated.', v_updated);
end;
$function$;

create or replace function public.platform_validate_gateway_payload(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_operation_code text := nullif(btrim(p_params->>'operation_code'), '');
  v_payload jsonb := coalesce(p_params->'payload', '{}'::jsonb);
  v_request_contract jsonb := '{}'::jsonb;
  v_required_keys text[] := '{}'::text[];
  v_allowed_keys text[] := '{}'::text[];
  v_payload_key text;
begin
  if v_operation_code is null then
    return public.platform_json_response(false, 'OPERATION_CODE_REQUIRED', 'operation_code is required.', '{}'::jsonb);
  end if;

  if jsonb_typeof(v_payload) <> 'object' then
    return public.platform_json_response(false, 'INVALID_PAYLOAD', 'payload must be a JSON object.', '{}'::jsonb);
  end if;

  select coalesce(request_contract, '{}'::jsonb)
  into v_request_contract
  from public.platform_gateway_operation
  where operation_code = v_operation_code;

  if not found then
    return public.platform_json_response(false, 'OPERATION_NOT_FOUND', 'Gateway operation not found.', jsonb_build_object('operation_code', v_operation_code));
  end if;

  if v_request_contract ? 'required_keys' then
    if jsonb_typeof(v_request_contract->'required_keys') <> 'array' then
      return public.platform_json_response(false, 'INVALID_REQUEST_CONTRACT', 'required_keys must be a JSON array.', jsonb_build_object('operation_code', v_operation_code));
    end if;

    select coalesce(array_agg(value), '{}'::text[])
    into v_required_keys
    from jsonb_array_elements_text(v_request_contract->'required_keys');

    foreach v_payload_key in array v_required_keys loop
      if not (v_payload ? v_payload_key) then
        return public.platform_json_response(false, 'PAYLOAD_REQUIRED_KEY_MISSING', 'Required payload key is missing.', jsonb_build_object('operation_code', v_operation_code, 'missing_key', v_payload_key));
      end if;
    end loop;
  end if;

  if v_request_contract ? 'allowed_keys' then
    if jsonb_typeof(v_request_contract->'allowed_keys') <> 'array' then
      return public.platform_json_response(false, 'INVALID_REQUEST_CONTRACT', 'allowed_keys must be a JSON array.', jsonb_build_object('operation_code', v_operation_code));
    end if;

    select coalesce(array_agg(value), '{}'::text[])
    into v_allowed_keys
    from jsonb_array_elements_text(v_request_contract->'allowed_keys');

    for v_payload_key in
      select key
      from jsonb_each(v_payload)
    loop
      if not (v_payload_key = any(v_allowed_keys)) then
        return public.platform_json_response(false, 'PAYLOAD_KEY_NOT_ALLOWED', 'Payload key is not allowed for this operation.', jsonb_build_object('operation_code', v_operation_code, 'key', v_payload_key, 'allowed_keys', v_allowed_keys));
      end if;
    end loop;
  end if;

  return public.platform_json_response(true, 'OK', 'Gateway payload validated.', jsonb_build_object(
    'operation_code', v_operation_code,
    'payload_keys', coalesce((select jsonb_agg(key order by key) from jsonb_each(v_payload)), '[]'::jsonb)
  ));
end;
$function$;;
