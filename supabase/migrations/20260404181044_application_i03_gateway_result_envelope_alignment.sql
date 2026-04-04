create or replace function public.platform_execute_gateway_mutation(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_operation_code text := nullif(btrim(p_params->>'operation_code'), '');
  v_request_id uuid := coalesce(public.platform_try_uuid(p_params->>'request_id'), gen_random_uuid());
  v_actor_user_id uuid := public.platform_current_actor_user_id();
  v_tenant_id uuid := public.platform_current_tenant_id();
  v_operation public.platform_gateway_operation%rowtype;
  v_payload jsonb := coalesce(p_params->'payload', '{}'::jsonb);
  v_final_params jsonb;
  v_result jsonb;
  v_result_details jsonb;
begin
  if v_operation_code is null then
    return public.platform_json_response(false, 'OPERATION_CODE_REQUIRED', 'operation_code is required.', '{}'::jsonb);
  end if;

  select *
  into v_operation
  from public.platform_gateway_operation
  where operation_code = v_operation_code
    and operation_mode = 'mutate'
    and operation_status = 'active';

  if not found then
    return public.platform_json_response(false, 'MUTATION_OPERATION_NOT_FOUND', 'Active mutation operation not found.', jsonb_build_object('operation_code', v_operation_code));
  end if;

  if jsonb_typeof(v_payload) <> 'object' then
    return public.platform_json_response(false, 'INVALID_PAYLOAD', 'payload must be a JSON object.', '{}'::jsonb);
  end if;

  v_final_params := coalesce(v_operation.static_params, '{}'::jsonb)
    || v_payload
    || jsonb_build_object(
      'operation_code', v_operation_code,
      'gateway_request_id', v_request_id,
      'tenant_id', v_tenant_id,
      'actor_user_id', v_actor_user_id
    );

  if not (v_final_params ? 'request_id') then
    v_final_params := v_final_params || jsonb_build_object('request_id', v_request_id);
  end if;

  execute format('select public.%I($1)', v_operation.binding_ref)
  into v_result
  using v_final_params;

  if v_result is null then
    v_result := public.platform_json_response(true, 'OK', 'Mutation executed.', '{}'::jsonb);
  elsif jsonb_typeof(v_result) <> 'object' or not (v_result ? 'success') then
    v_result := public.platform_json_response(true, 'OK', 'Mutation executed.', jsonb_build_object('result', v_result));
  elsif not (v_result ? 'code') or not (v_result ? 'message') or not (v_result ? 'details') then
    v_result := public.platform_json_response(
      coalesce((v_result->>'success')::boolean, true),
      coalesce(v_result->>'code', 'OK'),
      coalesce(v_result->>'message', 'Mutation executed.'),
      (v_result - 'success' - 'code' - 'message')
    );
  end if;

  v_result_details := coalesce(v_result->'details', '{}'::jsonb);
  if not (v_result_details ? 'request_id') then
    v_result_details := v_result_details || jsonb_build_object('request_id', v_request_id);
  else
    v_result_details := v_result_details || jsonb_build_object('gateway_request_id', v_request_id);
  end if;

  v_result_details := v_result_details || jsonb_build_object(
    'operation_code', v_operation_code,
    'mode', 'mutate',
    'actor_user_id', v_actor_user_id,
    'tenant_id', v_tenant_id
  );

  return jsonb_build_object(
    'success', coalesce((v_result->>'success')::boolean, true),
    'code', coalesce(v_result->>'code', 'OK'),
    'message', coalesce(v_result->>'message', 'Gateway mutation executed.'),
    'details', v_result_details
  );
exception
  when others then
    return public.platform_json_response(false, 'MUTATION_EXECUTION_FAILED', 'Unexpected error while executing gateway mutation.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_execute_gateway_action(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_operation_code text := nullif(btrim(p_params->>'operation_code'), '');
  v_request_id uuid := coalesce(public.platform_try_uuid(p_params->>'request_id'), gen_random_uuid());
  v_actor_user_id uuid := public.platform_current_actor_user_id();
  v_tenant_id uuid := public.platform_current_tenant_id();
  v_operation public.platform_gateway_operation%rowtype;
  v_payload jsonb := coalesce(p_params->'payload', '{}'::jsonb);
  v_final_params jsonb;
  v_result jsonb;
  v_result_details jsonb;
begin
  if v_operation_code is null then
    return public.platform_json_response(false, 'OPERATION_CODE_REQUIRED', 'operation_code is required.', '{}'::jsonb);
  end if;

  select *
  into v_operation
  from public.platform_gateway_operation
  where operation_code = v_operation_code
    and operation_mode = 'action'
    and operation_status = 'active';

  if not found then
    return public.platform_json_response(false, 'ACTION_OPERATION_NOT_FOUND', 'Active action operation not found.', jsonb_build_object('operation_code', v_operation_code));
  end if;

  if jsonb_typeof(v_payload) <> 'object' then
    return public.platform_json_response(false, 'INVALID_PAYLOAD', 'payload must be a JSON object.', '{}'::jsonb);
  end if;

  v_final_params := coalesce(v_operation.static_params, '{}'::jsonb)
    || v_payload
    || jsonb_build_object(
      'operation_code', v_operation_code,
      'gateway_request_id', v_request_id,
      'tenant_id', v_tenant_id,
      'actor_user_id', v_actor_user_id
    );

  if not (v_final_params ? 'request_id') then
    v_final_params := v_final_params || jsonb_build_object('request_id', v_request_id);
  end if;

  execute format('select public.%I($1)', v_operation.binding_ref)
  into v_result
  using v_final_params;

  if v_result is null then
    v_result := public.platform_json_response(true, 'OK', 'Action executed.', '{}'::jsonb);
  elsif jsonb_typeof(v_result) <> 'object' or not (v_result ? 'success') then
    v_result := public.platform_json_response(true, 'OK', 'Action executed.', jsonb_build_object('result', v_result));
  elsif not (v_result ? 'code') or not (v_result ? 'message') or not (v_result ? 'details') then
    v_result := public.platform_json_response(
      coalesce((v_result->>'success')::boolean, true),
      coalesce(v_result->>'code', 'OK'),
      coalesce(v_result->>'message', 'Action executed.'),
      (v_result - 'success' - 'code' - 'message')
    );
  end if;

  v_result_details := coalesce(v_result->'details', '{}'::jsonb);
  if not (v_result_details ? 'request_id') then
    v_result_details := v_result_details || jsonb_build_object('request_id', v_request_id);
  else
    v_result_details := v_result_details || jsonb_build_object('gateway_request_id', v_request_id);
  end if;

  v_result_details := v_result_details || jsonb_build_object(
    'operation_code', v_operation_code,
    'mode', 'action',
    'actor_user_id', v_actor_user_id,
    'tenant_id', v_tenant_id
  );

  return jsonb_build_object(
    'success', coalesce((v_result->>'success')::boolean, true),
    'code', coalesce(v_result->>'code', 'OK'),
    'message', coalesce(v_result->>'message', 'Gateway action executed.'),
    'details', v_result_details
  );
exception
  when others then
    return public.platform_json_response(false, 'ACTION_EXECUTION_FAILED', 'Unexpected error while executing gateway action.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;