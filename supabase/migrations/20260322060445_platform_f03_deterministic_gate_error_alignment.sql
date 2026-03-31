create or replace function public.platform_resolve_client_execution_context(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_actor_user_id uuid := public.platform_resolve_actor();
  v_requested_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_tenant_id uuid;
  v_gate jsonb;
  v_gate_details jsonb;
  v_schema_state jsonb;
  v_schema_details jsonb;
  v_gate_reason_code text;
  v_active_count integer;
  v_default_count integer;
  v_membership_status text;
  v_routing_status text;
begin
  if v_actor_user_id is null then
    return public.platform_json_response(false, 'AUTHENTICATED_USER_REQUIRED', 'Authenticated user context is required.', '{}'::jsonb);
  end if;
  if v_requested_tenant_id is not null then
    select patm.membership_status, patm.routing_status into v_membership_status, v_routing_status
    from public.platform_actor_tenant_membership patm
    where patm.actor_user_id = v_actor_user_id and patm.tenant_id = v_requested_tenant_id;
    if not found then
      return public.platform_json_response(false, 'ACTOR_TENANT_MEMBERSHIP_NOT_FOUND', 'Actor is not linked to the requested tenant.', jsonb_build_object('tenant_id', v_requested_tenant_id, 'actor_user_id', v_actor_user_id));
    end if;
    if not (v_membership_status = 'active' and v_routing_status = 'enabled') then
      return public.platform_json_response(false, 'ACTOR_TENANT_MEMBERSHIP_DISABLED', 'Actor routing membership is not active for the requested tenant.', jsonb_build_object('tenant_id', v_requested_tenant_id, 'actor_user_id', v_actor_user_id));
    end if;
    v_tenant_id := v_requested_tenant_id;
  else
    select count(*) filter (where membership_status = 'active' and routing_status = 'enabled'), count(*) filter (where membership_status = 'active' and routing_status = 'enabled' and is_default_tenant = true)
    into v_active_count, v_default_count
    from public.platform_actor_tenant_membership
    where actor_user_id = v_actor_user_id;
    if coalesce(v_active_count, 0) = 0 then
      return public.platform_json_response(false, 'ACTOR_TENANT_MEMBERSHIP_NOT_FOUND', 'Actor has no active tenant routing membership.', jsonb_build_object('actor_user_id', v_actor_user_id));
    elsif coalesce(v_default_count, 0) = 1 then
      select patm.tenant_id into v_tenant_id
      from public.platform_actor_tenant_membership patm
      where patm.actor_user_id = v_actor_user_id and patm.membership_status = 'active' and patm.routing_status = 'enabled' and patm.is_default_tenant = true
      limit 1;
    elsif v_active_count = 1 then
      select patm.tenant_id into v_tenant_id
      from public.platform_actor_tenant_membership patm
      where patm.actor_user_id = v_actor_user_id and patm.membership_status = 'active' and patm.routing_status = 'enabled'
      limit 1;
    else
      return public.platform_json_response(false, 'TENANT_RESOLUTION_AMBIGUOUS', 'Multiple active tenant memberships exist and no default tenant is set.', jsonb_build_object('actor_user_id', v_actor_user_id, 'active_membership_count', v_active_count));
    end if;
  end if;
  v_gate := public.platform_get_tenant_access_gate(jsonb_build_object('tenant_id', v_tenant_id));
  if coalesce((v_gate->>'success')::boolean, false) = false then return v_gate; end if;
  v_gate_details := coalesce(v_gate->'details', '{}'::jsonb);
  v_gate_reason_code := nullif(v_gate_details->>'reason_code', '');
  if coalesce((v_gate_details->>'ready_for_routing')::boolean, false) = false then
    return public.platform_json_response(false, 'TENANT_NOT_READY_FOR_ROUTING', 'Tenant is not ready for routing.', v_gate_details || jsonb_build_object('gate_reason_code', v_gate_reason_code));
  end if;
  if coalesce((v_gate_details->>'client_access_allowed')::boolean, false) = false then
    return public.platform_json_response(false, case
      when v_gate_details->>'access_state' = 'disabled' then 'TENANT_DISABLED'
      when v_gate_details->>'access_state' = 'terminated' then 'TENANT_TERMINATED'
      else 'TENANT_ACCESS_BLOCKED_DORMANT'
    end, 'Client access is blocked for the tenant.', v_gate_details || jsonb_build_object('gate_reason_code', v_gate_reason_code));
  end if;
  v_schema_state := public.platform_get_tenant_schema_state(jsonb_build_object('tenant_id', v_tenant_id));
  if coalesce((v_schema_state->>'success')::boolean, false) = false then return v_schema_state; end if;
  v_schema_details := coalesce(v_schema_state->'details', '{}'::jsonb);
  if coalesce((v_schema_details->>'schema_exists')::boolean, false) = false or nullif(v_schema_details->>'schema_name', '') is null then
    return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_AVAILABLE', 'Tenant schema is not available.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;
  return public.platform_json_response(true, 'OK', 'Client execution context resolved.', jsonb_build_object(
    'execution_mode', 'client_request',
    'actor_user_id', v_actor_user_id,
    'tenant_id', v_tenant_id,
    'tenant_code', v_gate_details->>'tenant_code',
    'schema_name', v_schema_details->>'schema_name',
    'access_state', v_gate_details->>'access_state',
    'client_access_allowed', coalesce((v_gate_details->>'client_access_allowed')::boolean, false),
    'background_processing_allowed', coalesce((v_gate_details->>'background_processing_allowed')::boolean, false),
    'reason_code', null,
    'context_source', 'client_request'
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_resolve_client_execution_context.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_resolve_background_execution_context(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_gate jsonb;
  v_gate_details jsonb;
  v_schema_state jsonb;
  v_schema_details jsonb;
  v_gate_reason_code text;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Internal caller is required.', '{}'::jsonb);
  end if;
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;
  v_gate := public.platform_get_tenant_access_gate(jsonb_build_object('tenant_id', v_tenant_id));
  if coalesce((v_gate->>'success')::boolean, false) = false then return v_gate; end if;
  v_gate_details := coalesce(v_gate->'details', '{}'::jsonb);
  v_gate_reason_code := nullif(v_gate_details->>'reason_code', '');
  if coalesce((v_gate_details->>'ready_for_routing')::boolean, false) = false then
    return public.platform_json_response(false, 'TENANT_NOT_READY_FOR_ROUTING', 'Tenant is not ready for routing.', v_gate_details || jsonb_build_object('gate_reason_code', v_gate_reason_code));
  end if;
  if coalesce((v_gate_details->>'background_processing_allowed')::boolean, false) = false then
    return public.platform_json_response(false, case
      when v_gate_details->>'access_state' = 'disabled' then 'TENANT_DISABLED'
      when v_gate_details->>'access_state' = 'terminated' then 'TENANT_TERMINATED'
      else 'TENANT_BACKGROUND_BLOCKED_DORMANT'
    end, 'Background processing is blocked for the tenant.', v_gate_details || jsonb_build_object('gate_reason_code', v_gate_reason_code));
  end if;
  v_schema_state := public.platform_get_tenant_schema_state(jsonb_build_object('tenant_id', v_tenant_id));
  if coalesce((v_schema_state->>'success')::boolean, false) = false then return v_schema_state; end if;
  v_schema_details := coalesce(v_schema_state->'details', '{}'::jsonb);
  if coalesce((v_schema_details->>'schema_exists')::boolean, false) = false or nullif(v_schema_details->>'schema_name', '') is null then
    return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_AVAILABLE', 'Tenant schema is not available.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;
  return public.platform_json_response(true, 'OK', 'Background execution context resolved.', jsonb_build_object(
    'execution_mode', 'background_job',
    'tenant_id', v_tenant_id,
    'tenant_code', v_gate_details->>'tenant_code',
    'schema_name', v_schema_details->>'schema_name',
    'access_state', v_gate_details->>'access_state',
    'client_access_allowed', coalesce((v_gate_details->>'client_access_allowed')::boolean, false),
    'background_processing_allowed', coalesce((v_gate_details->>'background_processing_allowed')::boolean, false),
    'reason_code', null,
    'context_source', coalesce(nullif(p_params->>'context_source', ''), nullif(p_params->>'source', ''), 'background_job')
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_resolve_background_execution_context.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
