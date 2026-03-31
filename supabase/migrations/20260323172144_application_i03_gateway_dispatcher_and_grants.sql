create or replace function public.platform_execute_gateway_request(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_started_at timestamptz := clock_timestamp();
  v_request_id uuid := coalesce(public.platform_try_uuid(p_params->>'request_id'), gen_random_uuid());
  v_operation_code text := nullif(btrim(p_params->>'operation_code'), '');
  v_payload jsonb := coalesce(p_params->'payload', '{}'::jsonb);
  v_request_metadata jsonb := coalesce(p_params->'request_metadata', '{}'::jsonb);
  v_idempotency_key text := nullif(btrim(p_params->>'idempotency_key'), '');
  v_internal_actor_user_id uuid := case when public.platform_is_internal_caller() then public.platform_try_uuid(p_params->>'actor_user_id') else null end;
  v_operation public.platform_gateway_operation%rowtype;
  v_context_result jsonb;
  v_access_result jsonb;
  v_payload_validation_result jsonb;
  v_claim_result jsonb;
  v_result jsonb;
  v_duration_ms integer;
  v_request_status text := 'failed';
  v_error_code text := null;
begin
  if jsonb_typeof(v_request_metadata) <> 'object' then
    v_result := public.platform_json_response(false, 'INVALID_REQUEST_METADATA', 'request_metadata must be a JSON object.', jsonb_build_object('request_id', v_request_id));
    perform public.platform_log_gateway_request(jsonb_build_object(
      'request_id', v_request_id,
      'request_status', 'blocked',
      'error_code', 'INVALID_REQUEST_METADATA',
      'request_payload', jsonb_build_object('operation_code', p_params->>'operation_code', 'payload', v_payload),
      'response_payload', v_result,
      'metadata', jsonb_build_object('request_metadata', v_request_metadata)
    ));
    return v_result;
  end if;

  if v_operation_code is null then
    v_result := public.platform_json_response(false, 'OPERATION_CODE_REQUIRED', 'operation_code is required.', jsonb_build_object('request_id', v_request_id));
    perform public.platform_log_gateway_request(jsonb_build_object(
      'request_id', v_request_id,
      'request_status', 'blocked',
      'error_code', 'OPERATION_CODE_REQUIRED',
      'request_payload', jsonb_build_object('operation_code', p_params->>'operation_code', 'payload', v_payload),
      'response_payload', v_result,
      'metadata', jsonb_build_object('request_metadata', v_request_metadata)
    ));
    return v_result;
  end if;

  select *
  into v_operation
  from public.platform_gateway_operation
  where operation_code = v_operation_code;

  if not found then
    v_result := public.platform_json_response(false, 'OPERATION_NOT_FOUND', 'Gateway operation not found.', jsonb_build_object('operation_code', v_operation_code, 'request_id', v_request_id));
    perform public.platform_log_gateway_request(jsonb_build_object(
      'request_id', v_request_id,
      'operation_code', v_operation_code,
      'request_status', 'blocked',
      'error_code', 'OPERATION_NOT_FOUND',
      'request_payload', jsonb_build_object('payload', v_payload),
      'response_payload', v_result,
      'metadata', jsonb_build_object('request_metadata', v_request_metadata)
    ));
    return v_result;
  end if;

  if jsonb_typeof(v_payload) <> 'object' then
    v_result := public.platform_json_response(false, 'INVALID_PAYLOAD', 'payload must be a JSON object.', jsonb_build_object('operation_code', v_operation_code, 'request_id', v_request_id));
    perform public.platform_log_gateway_request(jsonb_build_object(
      'request_id', v_request_id,
      'operation_code', v_operation_code,
      'request_status', 'blocked',
      'operation_mode', v_operation.operation_mode,
      'dispatch_kind', v_operation.dispatch_kind,
      'error_code', 'INVALID_PAYLOAD',
      'request_payload', jsonb_build_object('payload', v_payload),
      'response_payload', v_result,
      'metadata', jsonb_build_object('request_metadata', v_request_metadata)
    ));
    return v_result;
  end if;

  if v_internal_actor_user_id is not null then
    v_context_result := public.platform_apply_execution_context(jsonb_build_object(
      'execution_mode', 'internal_platform',
      'tenant_id', p_params->>'tenant_id',
      'tenant_code', p_params->>'tenant_code',
      'context_source', 'i03_gateway_internal'
    ));
  else
    v_context_result := public.platform_apply_execution_context(jsonb_build_object(
      'execution_mode', 'client_request',
      'tenant_id', p_params->>'tenant_id',
      'tenant_code', p_params->>'tenant_code',
      'context_source', 'i03_gateway'
    ));
  end if;

  if coalesce((v_context_result->>'success')::boolean, false) = false then
    v_result := v_context_result;
    v_error_code := v_context_result->>'code';
    perform public.platform_log_gateway_request(jsonb_build_object(
      'request_id', v_request_id,
      'operation_code', v_operation_code,
      'request_status', 'blocked',
      'operation_mode', v_operation.operation_mode,
      'dispatch_kind', v_operation.dispatch_kind,
      'error_code', v_error_code,
      'request_payload', jsonb_build_object('payload', v_payload),
      'response_payload', v_result,
      'metadata', jsonb_build_object('request_metadata', v_request_metadata)
    ));
    return v_result;
  end if;

  if v_internal_actor_user_id is not null then
    perform set_config('platform.actor_user_id', v_internal_actor_user_id::text, true);
  end if;

  v_access_result := public.platform_validate_gateway_access(jsonb_build_object(
    'operation_code', v_operation_code
  ));

  if coalesce((v_access_result->>'success')::boolean, false) = false then
    v_result := v_access_result;
    v_error_code := v_access_result->>'code';
    perform public.platform_log_gateway_request(jsonb_build_object(
      'request_id', v_request_id,
      'operation_code', v_operation_code,
      'actor_user_id', public.platform_current_actor_user_id(),
      'tenant_id', public.platform_current_tenant_id(),
      'execution_mode', public.platform_current_execution_mode(),
      'operation_mode', v_operation.operation_mode,
      'dispatch_kind', v_operation.dispatch_kind,
      'request_status', 'blocked',
      'error_code', v_error_code,
      'idempotency_key', v_idempotency_key,
      'request_payload', jsonb_build_object('payload', v_payload),
      'response_payload', v_result,
      'metadata', jsonb_build_object('request_metadata', v_request_metadata)
    ));
    return v_result;
  end if;

  v_payload_validation_result := public.platform_validate_gateway_payload(jsonb_build_object(
    'operation_code', v_operation_code,
    'payload', v_payload
  ));

  if coalesce((v_payload_validation_result->>'success')::boolean, false) = false then
    v_result := v_payload_validation_result;
    v_error_code := v_payload_validation_result->>'code';
    perform public.platform_log_gateway_request(jsonb_build_object(
      'request_id', v_request_id,
      'operation_code', v_operation_code,
      'actor_user_id', public.platform_current_actor_user_id(),
      'tenant_id', public.platform_current_tenant_id(),
      'execution_mode', public.platform_current_execution_mode(),
      'operation_mode', v_operation.operation_mode,
      'dispatch_kind', v_operation.dispatch_kind,
      'request_status', 'blocked',
      'error_code', v_error_code,
      'idempotency_key', v_idempotency_key,
      'request_payload', jsonb_build_object('payload', v_payload),
      'response_payload', v_result,
      'metadata', jsonb_build_object('request_metadata', v_request_metadata)
    ));
    return v_result;
  end if;

  if v_operation.idempotency_policy = 'required' and v_idempotency_key is null then
    v_result := public.platform_json_response(false, 'IDEMPOTENCY_KEY_REQUIRED', 'idempotency_key is required for this operation.', jsonb_build_object('operation_code', v_operation_code, 'request_id', v_request_id));
    perform public.platform_log_gateway_request(jsonb_build_object(
      'request_id', v_request_id,
      'operation_code', v_operation_code,
      'actor_user_id', public.platform_current_actor_user_id(),
      'tenant_id', public.platform_current_tenant_id(),
      'execution_mode', public.platform_current_execution_mode(),
      'operation_mode', v_operation.operation_mode,
      'dispatch_kind', v_operation.dispatch_kind,
      'request_status', 'blocked',
      'error_code', 'IDEMPOTENCY_KEY_REQUIRED',
      'request_payload', jsonb_build_object('payload', v_payload),
      'response_payload', v_result,
      'metadata', jsonb_build_object('request_metadata', v_request_metadata)
    ));
    return v_result;
  end if;

  if v_operation.operation_mode in ('mutate', 'action')
     and (v_operation.idempotency_policy <> 'none' or v_idempotency_key is not null) then
    v_claim_result := public.platform_claim_gateway_idempotency(jsonb_build_object(
      'operation_code', v_operation_code,
      'idempotency_key', v_idempotency_key,
      'request_payload', v_payload,
      'metadata', jsonb_build_object(
        'request_id', v_request_id,
        'request_metadata', v_request_metadata
      )
    ));

    if coalesce((v_claim_result->>'success')::boolean, false) = true
       and v_claim_result->>'code' = 'IDEMPOTENT_REPLAY' then
      v_result := coalesce(v_claim_result->'details'->'response_payload', public.platform_json_response(true, 'OK', 'Idempotent replay with no stored response payload.', '{}'::jsonb));
      v_duration_ms := greatest((extract(epoch from (clock_timestamp() - v_started_at)) * 1000)::integer, 0);
      perform public.platform_log_gateway_request(jsonb_build_object(
        'request_id', v_request_id,
        'operation_code', v_operation_code,
        'actor_user_id', public.platform_current_actor_user_id(),
        'tenant_id', public.platform_current_tenant_id(),
        'execution_mode', public.platform_current_execution_mode(),
        'operation_mode', v_operation.operation_mode,
        'dispatch_kind', v_operation.dispatch_kind,
        'request_status', 'replayed',
        'duration_ms', v_duration_ms,
        'idempotency_key', v_idempotency_key,
        'request_payload', jsonb_build_object('payload', v_payload),
        'response_payload', v_result,
        'metadata', jsonb_build_object('request_metadata', v_request_metadata)
      ));
      return v_result;
    elsif coalesce((v_claim_result->>'success')::boolean, false) = false then
      v_result := v_claim_result;
      v_error_code := v_claim_result->>'code';
      v_duration_ms := greatest((extract(epoch from (clock_timestamp() - v_started_at)) * 1000)::integer, 0);
      perform public.platform_log_gateway_request(jsonb_build_object(
        'request_id', v_request_id,
        'operation_code', v_operation_code,
        'actor_user_id', public.platform_current_actor_user_id(),
        'tenant_id', public.platform_current_tenant_id(),
        'execution_mode', public.platform_current_execution_mode(),
        'operation_mode', v_operation.operation_mode,
        'dispatch_kind', v_operation.dispatch_kind,
        'request_status', 'blocked',
        'error_code', v_error_code,
        'duration_ms', v_duration_ms,
        'idempotency_key', v_idempotency_key,
        'request_payload', jsonb_build_object('payload', v_payload),
        'response_payload', v_result,
        'metadata', jsonb_build_object('request_metadata', v_request_metadata)
      ));
      return v_result;
    end if;
  end if;

  case v_operation.operation_mode
    when 'read' then
      v_result := public.platform_execute_gateway_read(jsonb_build_object(
        'operation_code', v_operation_code,
        'request_id', v_request_id,
        'payload', v_payload
      ));
    when 'mutate' then
      v_result := public.platform_execute_gateway_mutation(jsonb_build_object(
        'operation_code', v_operation_code,
        'request_id', v_request_id,
        'payload', v_payload
      ));
    when 'action' then
      v_result := public.platform_execute_gateway_action(jsonb_build_object(
        'operation_code', v_operation_code,
        'request_id', v_request_id,
        'payload', v_payload
      ));
    else
      v_result := public.platform_json_response(false, 'INVALID_OPERATION_MODE', 'operation_mode is invalid.', jsonb_build_object('operation_mode', v_operation.operation_mode));
  end case;

  v_duration_ms := greatest((extract(epoch from (clock_timestamp() - v_started_at)) * 1000)::integer, 0);
  v_request_status := case when coalesce((v_result->>'success')::boolean, false) then 'succeeded' else 'failed' end;
  v_error_code := case when v_request_status = 'failed' then v_result->>'code' else null end;

  if v_operation.operation_mode in ('mutate', 'action')
     and (v_operation.idempotency_policy <> 'none' or v_idempotency_key is not null)
     and v_idempotency_key is not null then
    update public.platform_gateway_idempotency_claim
    set claim_status = case when v_request_status = 'succeeded' then 'succeeded' else 'failed' end,
        response_payload = case when v_request_status = 'succeeded' then coalesce(v_result, '{}'::jsonb) else '{}'::jsonb end,
        error_payload = case when v_request_status = 'failed' then coalesce(v_result, '{}'::jsonb) else '{}'::jsonb end,
        completed_at = timezone('utc', now()),
        metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('request_metadata', v_request_metadata)
    where operation_code = v_operation_code
      and tenant_id = public.platform_current_tenant_id()
      and actor_user_id = public.platform_current_actor_user_id()
      and idempotency_key = v_idempotency_key;
  end if;

  perform public.platform_log_gateway_request(jsonb_build_object(
    'request_id', v_request_id,
    'operation_code', v_operation_code,
    'actor_user_id', public.platform_current_actor_user_id(),
    'tenant_id', public.platform_current_tenant_id(),
    'execution_mode', public.platform_current_execution_mode(),
    'operation_mode', v_operation.operation_mode,
    'dispatch_kind', v_operation.dispatch_kind,
    'request_status', v_request_status,
    'error_code', v_error_code,
    'duration_ms', v_duration_ms,
    'idempotency_key', v_idempotency_key,
    'request_payload', jsonb_build_object('payload', v_payload),
    'response_payload', coalesce(v_result, '{}'::jsonb),
    'metadata', jsonb_build_object('request_metadata', v_request_metadata)
  ));

  return v_result;
exception
  when others then
    v_duration_ms := greatest((extract(epoch from (clock_timestamp() - v_started_at)) * 1000)::integer, 0);
    v_result := public.platform_json_response(false, 'GATEWAY_EXECUTION_FAILED', 'Unexpected error in platform_execute_gateway_request.', jsonb_build_object('request_id', v_request_id, 'sqlstate', sqlstate, 'sqlerrm', sqlerrm));
    perform public.platform_log_gateway_request(jsonb_build_object(
      'request_id', v_request_id,
      'operation_code', v_operation_code,
      'actor_user_id', public.platform_current_actor_user_id(),
      'tenant_id', public.platform_current_tenant_id(),
      'execution_mode', public.platform_current_execution_mode(),
      'operation_mode', coalesce(v_operation.operation_mode, ''),
      'dispatch_kind', coalesce(v_operation.dispatch_kind, ''),
      'request_status', 'failed',
      'error_code', 'GATEWAY_EXECUTION_FAILED',
      'duration_ms', v_duration_ms,
      'idempotency_key', v_idempotency_key,
      'request_payload', jsonb_build_object('payload', v_payload),
      'response_payload', v_result,
      'metadata', jsonb_build_object('request_metadata', v_request_metadata)
    ));
    return v_result;
end;
$function$;

revoke all on public.platform_gateway_operation from public, anon, authenticated;
revoke all on public.platform_gateway_operation_role from public, anon, authenticated;
revoke all on public.platform_gateway_idempotency_claim from public, anon, authenticated;
revoke all on public.platform_gateway_request_log from public, anon, authenticated;

grant all on public.platform_gateway_operation to service_role;
grant all on public.platform_gateway_operation_role to service_role;
grant all on public.platform_gateway_idempotency_claim to service_role;
grant all on public.platform_gateway_request_log to service_role;

revoke all on function public.platform_register_gateway_operation(jsonb) from public, anon, authenticated;
revoke all on function public.platform_assign_gateway_operation_role(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_gateway_operation(jsonb) from public, anon, authenticated;
revoke all on function public.platform_validate_gateway_access(jsonb) from public, anon, authenticated;
revoke all on function public.platform_claim_gateway_idempotency(jsonb) from public, anon, authenticated;
revoke all on function public.platform_log_gateway_request(jsonb) from public, anon, authenticated;
revoke all on function public.platform_update_gateway_operation_metadata(jsonb) from public, anon, authenticated;
revoke all on function public.platform_validate_gateway_payload(jsonb) from public, anon, authenticated;
revoke all on function public.platform_execute_gateway_read(jsonb) from public, anon, authenticated;
revoke all on function public.platform_execute_gateway_mutation(jsonb) from public, anon, authenticated;
revoke all on function public.platform_execute_gateway_action(jsonb) from public, anon, authenticated;
revoke all on function public.platform_execute_gateway_request(jsonb) from public, anon, authenticated;

grant execute on function public.platform_register_gateway_operation(jsonb) to service_role;
grant execute on function public.platform_assign_gateway_operation_role(jsonb) to service_role;
grant execute on function public.platform_get_gateway_operation(jsonb) to service_role;
grant execute on function public.platform_validate_gateway_access(jsonb) to service_role;
grant execute on function public.platform_claim_gateway_idempotency(jsonb) to service_role;
grant execute on function public.platform_log_gateway_request(jsonb) to service_role;
grant execute on function public.platform_update_gateway_operation_metadata(jsonb) to service_role;
grant execute on function public.platform_validate_gateway_payload(jsonb) to service_role;
grant execute on function public.platform_execute_gateway_read(jsonb) to service_role;
grant execute on function public.platform_execute_gateway_mutation(jsonb) to service_role;
grant execute on function public.platform_execute_gateway_action(jsonb) to service_role;
grant execute on function public.platform_execute_gateway_request(jsonb) to service_role;
grant execute on function public.platform_execute_gateway_request(jsonb) to authenticated;;
