create or replace function public.platform_sim_resolve_client_execution_context(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_effective_params jsonb := coalesce(p_params, '{}'::jsonb);
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Internal caller is required.', '{}'::jsonb);
  end if;

  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
  end if;

  perform set_config('request.jwt.claim.sub', v_actor_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  return public.platform_resolve_client_execution_context(v_effective_params - 'actor_user_id');
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_sim_resolve_client_execution_context.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_sim_apply_and_get_execution_context(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_execution_mode text := lower(coalesce(nullif(p_params->>'execution_mode', ''), ''));
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_effective_params jsonb := coalesce(p_params, '{}'::jsonb);
  v_apply_result jsonb;
  v_current_context jsonb;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Internal caller is required.', '{}'::jsonb);
  end if;

  if v_execution_mode is null or v_execution_mode = '' then
    return public.platform_json_response(false, 'EXECUTION_MODE_REQUIRED', 'execution_mode is required.', '{}'::jsonb);
  end if;

  if v_execution_mode = 'client_request' then
    if v_actor_user_id is null then
      return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
    end if;

    perform set_config('request.jwt.claim.sub', v_actor_user_id::text, true);
    perform set_config('request.jwt.claim.role', 'authenticated', true);
    v_effective_params := v_effective_params - 'actor_user_id';
  end if;

  v_apply_result := public.platform_apply_execution_context(v_effective_params);
  if coalesce((v_apply_result->>'success')::boolean, false) = false then
    return v_apply_result;
  end if;

  v_current_context := public.platform_get_current_execution_context();
  if coalesce((v_current_context->>'success')::boolean, false) = false then
    return v_current_context;
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'Simulator execution context applied and read back.',
    jsonb_build_object(
      'apply_result', v_apply_result,
      'current_context', coalesce(v_current_context->'details', '{}'::jsonb)
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_sim_apply_and_get_execution_context.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

revoke all on function public.platform_sim_resolve_client_execution_context(jsonb) from public;
revoke all on function public.platform_sim_apply_and_get_execution_context(jsonb) from public;
revoke all on function public.platform_sim_resolve_client_execution_context(jsonb) from anon;
revoke all on function public.platform_sim_apply_and_get_execution_context(jsonb) from anon;
revoke all on function public.platform_sim_resolve_client_execution_context(jsonb) from authenticated;
revoke all on function public.platform_sim_apply_and_get_execution_context(jsonb) from authenticated;

grant execute on function public.platform_sim_resolve_client_execution_context(jsonb) to service_role;
grant execute on function public.platform_sim_apply_and_get_execution_context(jsonb) to service_role;;
