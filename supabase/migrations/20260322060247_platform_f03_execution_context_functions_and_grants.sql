create or replace function public.platform_register_actor_tenant_membership(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_membership_status text := lower(coalesce(nullif(p_params->>'membership_status', ''), 'active'));
  v_routing_status text := lower(coalesce(nullif(p_params->>'routing_status', ''), case when v_membership_status = 'active' then 'enabled' else 'blocked' end));
  v_requested_default boolean := case when p_params ? 'is_default_tenant' then (p_params->>'is_default_tenant')::boolean else false end;
  v_make_default boolean := false;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Internal caller is required.', '{}'::jsonb);
  end if;
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;
  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
  end if;
  if v_membership_status not in ('active', 'invited', 'disabled', 'revoked') then
    return public.platform_json_response(false, 'INVALID_MEMBERSHIP_STATUS', 'membership_status is invalid.', jsonb_build_object('membership_status', v_membership_status));
  end if;
  if v_routing_status not in ('enabled', 'blocked') then
    return public.platform_json_response(false, 'INVALID_ROUTING_STATUS', 'routing_status is invalid.', jsonb_build_object('routing_status', v_routing_status));
  end if;
  if not exists (select 1 from public.platform_tenant pt where pt.tenant_id = v_tenant_id) then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;
  if v_requested_default then
    v_make_default := true;
  elsif v_membership_status = 'active' and v_routing_status = 'enabled' and not exists (
    select 1 from public.platform_actor_tenant_membership patm
    where patm.actor_user_id = v_actor_user_id and patm.membership_status = 'active' and patm.routing_status = 'enabled' and patm.is_default_tenant = true
  ) then
    v_make_default := true;
  end if;
  if v_make_default then
    update public.platform_actor_tenant_membership set is_default_tenant = false where actor_user_id = v_actor_user_id and is_default_tenant = true;
  end if;
  insert into public.platform_actor_tenant_membership (
    tenant_id, actor_user_id, membership_status, is_default_tenant, routing_status, linked_at, linked_by, disabled_at, metadata
  ) values (
    v_tenant_id, v_actor_user_id, v_membership_status, v_make_default, v_routing_status, now(), public.platform_resolve_actor(),
    case when v_membership_status in ('disabled', 'revoked') or v_routing_status = 'blocked' then now() else null end,
    coalesce(p_params->'metadata', '{}'::jsonb)
  )
  on conflict (tenant_id, actor_user_id) do update
  set membership_status = excluded.membership_status,
      is_default_tenant = excluded.is_default_tenant,
      routing_status = excluded.routing_status,
      linked_at = excluded.linked_at,
      linked_by = excluded.linked_by,
      disabled_at = excluded.disabled_at,
      metadata = excluded.metadata,
      updated_at = now();
  return public.platform_json_response(true, 'OK', 'Actor tenant membership registered.', jsonb_build_object(
    'tenant_id', v_tenant_id, 'actor_user_id', v_actor_user_id, 'membership_status', v_membership_status, 'routing_status', v_routing_status, 'is_default_tenant', v_make_default
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_actor_tenant_membership.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

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
  v_reason_code text;
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
  v_reason_code := nullif(v_gate_details->>'reason_code', '');
  if coalesce((v_gate_details->>'ready_for_routing')::boolean, false) = false then
    return public.platform_json_response(false, coalesce(v_reason_code, 'TENANT_NOT_READY_FOR_ROUTING'), 'Tenant is not ready for routing.', v_gate_details);
  end if;
  if coalesce((v_gate_details->>'client_access_allowed')::boolean, false) = false then
    return public.platform_json_response(false, coalesce(v_reason_code, 'TENANT_ACCESS_BLOCKED_DORMANT'), 'Client access is blocked for the tenant.', v_gate_details);
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
    'reason_code', v_reason_code,
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
  v_reason_code text;
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
  v_reason_code := nullif(v_gate_details->>'reason_code', '');
  if coalesce((v_gate_details->>'ready_for_routing')::boolean, false) = false then
    return public.platform_json_response(false, coalesce(v_reason_code, 'TENANT_NOT_READY_FOR_ROUTING'), 'Tenant is not ready for routing.', v_gate_details);
  end if;
  if coalesce((v_gate_details->>'background_processing_allowed')::boolean, false) = false then
    return public.platform_json_response(false, coalesce(v_reason_code, 'TENANT_BACKGROUND_BLOCKED_DORMANT'), 'Background processing is blocked for the tenant.', v_gate_details);
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
    'reason_code', v_reason_code,
    'context_source', coalesce(nullif(p_params->>'context_source', ''), nullif(p_params->>'source', ''), 'background_job')
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_resolve_background_execution_context.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_apply_execution_context(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_execution_mode text := lower(coalesce(nullif(p_params->>'execution_mode', ''), ''));
  v_context jsonb;
  v_details jsonb;
begin
  if v_execution_mode is null or v_execution_mode = '' then
    return public.platform_json_response(false, 'EXECUTION_MODE_REQUIRED', 'execution_mode is required.', '{}'::jsonb);
  end if;
  case v_execution_mode
    when 'client_request' then v_context := public.platform_resolve_client_execution_context(p_params);
    when 'background_job', 'internal_platform' then v_context := public.platform_resolve_background_execution_context(p_params);
    else
      return public.platform_json_response(false, 'INVALID_EXECUTION_MODE', 'execution_mode is invalid.', jsonb_build_object('execution_mode', v_execution_mode));
  end case;
  if coalesce((v_context->>'success')::boolean, false) = false then return v_context; end if;
  v_details := coalesce(v_context->'details', '{}'::jsonb);
  if v_execution_mode = 'internal_platform' then
    v_details := jsonb_set(v_details, '{execution_mode}', '"internal_platform"', true);
  end if;
  perform set_config('platform.execution_mode', coalesce(v_details->>'execution_mode', ''), true);
  perform set_config('platform.actor_user_id', coalesce(v_details->>'actor_user_id', ''), true);
  perform set_config('platform.tenant_id', coalesce(v_details->>'tenant_id', ''), true);
  perform set_config('platform.tenant_code', coalesce(v_details->>'tenant_code', ''), true);
  perform set_config('platform.tenant_schema', coalesce(v_details->>'schema_name', ''), true);
  perform set_config('platform.access_state', coalesce(v_details->>'access_state', ''), true);
  perform set_config('platform.client_access_allowed', coalesce(v_details->>'client_access_allowed', 'false'), true);
  perform set_config('platform.background_processing_allowed', coalesce(v_details->>'background_processing_allowed', 'false'), true);
  perform set_config('platform.context_source', coalesce(v_details->>'context_source', v_execution_mode), true);
  return public.platform_json_response(true, 'OK', 'Execution context applied.', jsonb_build_object(
    'execution_mode', public.platform_current_execution_mode(),
    'actor_user_id', public.platform_current_actor_user_id(),
    'tenant_id', public.platform_current_tenant_id(),
    'tenant_code', nullif(current_setting('platform.tenant_code', true), ''),
    'tenant_schema', public.platform_current_tenant_schema(),
    'access_state', public.platform_current_access_state(),
    'client_access_allowed', coalesce(nullif(current_setting('platform.client_access_allowed', true), '')::boolean, false),
    'background_processing_allowed', coalesce(nullif(current_setting('platform.background_processing_allowed', true), '')::boolean, false),
    'context_source', nullif(current_setting('platform.context_source', true), '')
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_apply_execution_context.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

revoke all on public.platform_actor_tenant_membership from public, anon, authenticated;
revoke all on public.platform_actor_tenant_membership_view from public, anon, authenticated;
revoke all on function public.platform_is_internal_caller() from public, anon, authenticated;
revoke all on function public.platform_register_actor_tenant_membership(jsonb) from public, anon, authenticated;
revoke all on function public.platform_resolve_background_execution_context(jsonb) from public, anon, authenticated;
revoke all on function public.platform_current_tenant_id() from public, anon;
revoke all on function public.platform_current_tenant_schema() from public, anon;
revoke all on function public.platform_current_actor_user_id() from public, anon;
revoke all on function public.platform_current_execution_mode() from public, anon;
revoke all on function public.platform_current_access_state() from public, anon;
revoke all on function public.platform_get_current_execution_context() from public, anon;
revoke all on function public.platform_resolve_client_execution_context(jsonb) from public, anon;
revoke all on function public.platform_apply_execution_context(jsonb) from public, anon;

grant execute on function public.platform_is_internal_caller() to service_role;
grant execute on function public.platform_register_actor_tenant_membership(jsonb) to service_role;
grant execute on function public.platform_resolve_client_execution_context(jsonb) to authenticated, service_role;
grant execute on function public.platform_resolve_background_execution_context(jsonb) to service_role;
grant execute on function public.platform_apply_execution_context(jsonb) to authenticated, service_role;
grant execute on function public.platform_current_tenant_id() to authenticated, service_role;
grant execute on function public.platform_current_tenant_schema() to authenticated, service_role;
grant execute on function public.platform_current_actor_user_id() to authenticated, service_role;
grant execute on function public.platform_current_execution_mode() to authenticated, service_role;
grant execute on function public.platform_current_access_state() to authenticated, service_role;
grant execute on function public.platform_get_current_execution_context() to authenticated, service_role;;
