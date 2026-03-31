create or replace function public.platform_restore_tenant_access(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.platform_resolve_actor();
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_source text := coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_restore_tenant_access');
  v_reason_code text := coalesce(nullif(btrim(p_params->>'reason_code'), ''), 'DUES_CLEARED');
  v_reason_details jsonb := coalesce(p_params->'reason_details', '{}'::jsonb);
  v_row public.platform_tenant_access_state%rowtype;
  v_now timestamptz := timezone('utc', now());
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  if jsonb_typeof(v_reason_details) is distinct from 'object' then
    return public.platform_json_response(false, 'INVALID_REASON_DETAILS', 'reason_details must be a JSON object.', jsonb_build_object('field', 'reason_details'));
  end if;

  select *
  into v_row
  from public.platform_tenant_access_state
  where tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant access state row not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_row.access_state = 'terminated' then
    return public.platform_json_response(false, 'TENANT_TERMINATED', 'Terminated tenants cannot be restored.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_row.access_state = 'disabled' then
    return public.platform_json_response(false, 'TENANT_DISABLED', 'Disabled tenants cannot be restored through dues-cleared flow.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_row.access_state = 'active' then
    return public.platform_json_response(true, 'OK', 'Tenant access is already active.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if not public.platform_access_transition_allowed(v_row.access_state, 'active') then
    return public.platform_json_response(false, 'INVALID_ACCESS_TRANSITION', 'Access transition is not allowed.', jsonb_build_object('from_state', v_row.access_state, 'to_state', 'active'));
  end if;

  update public.platform_tenant_access_state
  set
    access_state = 'active',
    reason_code = null,
    reason_details = '{}'::jsonb,
    billing_state = 'current',
    dormant_started_at = null,
    background_stop_at = null,
    restored_at = v_now,
    disabled_at = null,
    terminated_at = null,
    updated_by = v_actor
  where tenant_id = v_tenant_id;

  perform public.platform_append_status_history(v_tenant_id, 'access', v_row.access_state, 'active', v_reason_code, v_reason_details, v_actor, v_source);

  if v_row.billing_state is distinct from 'current' then
    perform public.platform_append_status_history(v_tenant_id, 'billing', v_row.billing_state, 'current', v_reason_code, v_reason_details, v_actor, v_source);
  end if;

  return public.platform_json_response(true, 'OK', 'Tenant access restored.', jsonb_build_object('tenant_id', v_tenant_id, 'access_state', 'active', 'billing_state', 'current', 'restored_at', v_now));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_restore_tenant_access.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;

create or replace function public.platform_disable_tenant(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.platform_resolve_actor();
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_source text := coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_disable_tenant');
  v_reason_code text := coalesce(nullif(btrim(p_params->>'reason_code'), ''), 'ADMIN_DISABLED');
  v_reason_details jsonb := coalesce(p_params->'reason_details', '{}'::jsonb);
  v_row public.platform_tenant_access_state%rowtype;
  v_now timestamptz := timezone('utc', now());
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  if jsonb_typeof(v_reason_details) is distinct from 'object' then
    return public.platform_json_response(false, 'INVALID_REASON_DETAILS', 'reason_details must be a JSON object.', jsonb_build_object('field', 'reason_details'));
  end if;

  select *
  into v_row
  from public.platform_tenant_access_state
  where tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant access state row not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_row.access_state = 'terminated' then
    return public.platform_json_response(false, 'TENANT_TERMINATED', 'Terminated tenants cannot be disabled again.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_row.access_state = 'disabled' then
    return public.platform_json_response(true, 'OK', 'Tenant is already disabled.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if not public.platform_access_transition_allowed(v_row.access_state, 'disabled') then
    return public.platform_json_response(false, 'INVALID_ACCESS_TRANSITION', 'Access transition is not allowed.', jsonb_build_object('from_state', v_row.access_state, 'to_state', 'disabled'));
  end if;

  update public.platform_tenant_access_state
  set
    access_state = 'disabled',
    reason_code = v_reason_code,
    reason_details = v_reason_details,
    billing_state = 'suspended',
    dormant_started_at = null,
    background_stop_at = null,
    restored_at = null,
    disabled_at = v_now,
    updated_by = v_actor
  where tenant_id = v_tenant_id;

  perform public.platform_append_status_history(v_tenant_id, 'access', v_row.access_state, 'disabled', v_reason_code, v_reason_details, v_actor, v_source);

  if v_row.billing_state is distinct from 'suspended' then
    perform public.platform_append_status_history(v_tenant_id, 'billing', v_row.billing_state, 'suspended', v_reason_code, v_reason_details, v_actor, v_source);
  end if;

  return public.platform_json_response(true, 'OK', 'Tenant disabled.', jsonb_build_object('tenant_id', v_tenant_id, 'access_state', 'disabled', 'billing_state', 'suspended', 'disabled_at', v_now));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_disable_tenant.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;

create or replace function public.platform_terminate_tenant(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.platform_resolve_actor();
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_source text := coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_terminate_tenant');
  v_reason_code text := coalesce(nullif(btrim(p_params->>'reason_code'), ''), 'TENANT_TERMINATED');
  v_reason_details jsonb := coalesce(p_params->'reason_details', '{}'::jsonb);
  v_row public.platform_tenant_access_state%rowtype;
  v_now timestamptz := timezone('utc', now());
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  if jsonb_typeof(v_reason_details) is distinct from 'object' then
    return public.platform_json_response(false, 'INVALID_REASON_DETAILS', 'reason_details must be a JSON object.', jsonb_build_object('field', 'reason_details'));
  end if;

  select *
  into v_row
  from public.platform_tenant_access_state
  where tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant access state row not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_row.access_state = 'terminated' then
    return public.platform_json_response(true, 'OK', 'Tenant is already terminated.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if not public.platform_access_transition_allowed(v_row.access_state, 'terminated') then
    return public.platform_json_response(false, 'INVALID_ACCESS_TRANSITION', 'Access transition is not allowed. Tenant must be disabled before termination.', jsonb_build_object('from_state', v_row.access_state, 'to_state', 'terminated'));
  end if;

  update public.platform_tenant_access_state
  set
    access_state = 'terminated',
    reason_code = v_reason_code,
    reason_details = v_reason_details,
    billing_state = 'closed',
    dormant_started_at = null,
    background_stop_at = null,
    restored_at = null,
    terminated_at = v_now,
    updated_by = v_actor
  where tenant_id = v_tenant_id;

  perform public.platform_append_status_history(v_tenant_id, 'access', v_row.access_state, 'terminated', v_reason_code, v_reason_details, v_actor, v_source);

  if v_row.billing_state is distinct from 'closed' then
    perform public.platform_append_status_history(v_tenant_id, 'billing', v_row.billing_state, 'closed', v_reason_code, v_reason_details, v_actor, v_source);
  end if;

  return public.platform_json_response(true, 'OK', 'Tenant terminated.', jsonb_build_object('tenant_id', v_tenant_id, 'access_state', 'terminated', 'billing_state', 'closed', 'terminated_at', v_now));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_terminate_tenant.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;

create or replace function public.platform_get_tenant_access_gate(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_row public.platform_tenant_registry_view%rowtype;
  v_effective_reason_code text;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select *
  into v_row
  from public.platform_tenant_registry_view
  where tenant_id = v_tenant_id;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  v_effective_reason_code := case
    when v_row.access_state = 'dormant_access_blocked' then coalesce(v_row.reason_code, 'TENANT_ACCESS_BLOCKED_DORMANT')
    when v_row.access_state = 'dormant_background_blocked' then coalesce(v_row.reason_code, 'TENANT_BACKGROUND_BLOCKED_DORMANT')
    when v_row.access_state = 'disabled' then coalesce(v_row.reason_code, 'TENANT_DISABLED')
    when v_row.access_state = 'terminated' then coalesce(v_row.reason_code, 'TENANT_TERMINATED')
    when not v_row.ready_for_routing then 'TENANT_NOT_READY_FOR_ROUTING'
    else null
  end;

  return public.platform_json_response(
    true,
    'OK',
    'Tenant access gate resolved.',
    jsonb_build_object(
      'tenant_id', v_row.tenant_id,
      'tenant_code', v_row.tenant_code,
      'provisioning_status', v_row.provisioning_status,
      'ready_for_routing', v_row.ready_for_routing,
      'access_state', v_row.access_state,
      'billing_state', v_row.billing_state,
      'client_access_allowed', v_row.client_access_allowed,
      'background_processing_allowed', v_row.background_processing_allowed,
      'reason_code', v_effective_reason_code,
      'background_stop_at', v_row.background_stop_at
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_get_tenant_access_gate.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;

revoke all on table public.platform_tenant from public, anon, authenticated;
revoke all on table public.platform_tenant_provisioning from public, anon, authenticated;
revoke all on table public.platform_tenant_access_state from public, anon, authenticated;
revoke all on table public.platform_tenant_status_history from public, anon, authenticated;
revoke all on public.platform_tenant_registry_view from public, anon, authenticated;

grant all on table public.platform_tenant to service_role;
grant all on table public.platform_tenant_provisioning to service_role;
grant all on table public.platform_tenant_access_state to service_role;
grant all on table public.platform_tenant_status_history to service_role;
grant select on public.platform_tenant_registry_view to service_role;

revoke all on function public.platform_set_updated_at() from public, anon, authenticated;
revoke all on function public.platform_json_response(boolean, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.platform_try_uuid(text) from public, anon, authenticated;
revoke all on function public.platform_normalize_tenant_code(text) from public, anon, authenticated;
revoke all on function public.platform_resolve_actor() from public, anon, authenticated;
revoke all on function public.platform_access_transition_allowed(text, text) from public, anon, authenticated;
revoke all on function public.platform_provisioning_transition_allowed(text, text) from public, anon, authenticated;
revoke all on function public.platform_append_status_history(uuid, text, text, text, text, jsonb, uuid, text) from public, anon, authenticated;
revoke all on function public.platform_resolve_tenant_id(jsonb) from public, anon, authenticated;
revoke all on function public.platform_create_tenant_registry(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_tenant_registry(jsonb) from public, anon, authenticated;
revoke all on function public.platform_transition_provisioning_state(jsonb) from public, anon, authenticated;
revoke all on function public.platform_mark_tenant_dormant(jsonb) from public, anon, authenticated;
revoke all on function public.platform_enforce_dormant_background_cutoff(jsonb) from public, anon, authenticated;
revoke all on function public.platform_restore_tenant_access(jsonb) from public, anon, authenticated;
revoke all on function public.platform_disable_tenant(jsonb) from public, anon, authenticated;
revoke all on function public.platform_terminate_tenant(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_tenant_access_gate(jsonb) from public, anon, authenticated;

grant execute on function public.platform_create_tenant_registry(jsonb) to service_role;
grant execute on function public.platform_get_tenant_registry(jsonb) to service_role;
grant execute on function public.platform_transition_provisioning_state(jsonb) to service_role;
grant execute on function public.platform_mark_tenant_dormant(jsonb) to service_role;
grant execute on function public.platform_enforce_dormant_background_cutoff(jsonb) to service_role;
grant execute on function public.platform_restore_tenant_access(jsonb) to service_role;
grant execute on function public.platform_disable_tenant(jsonb) to service_role;
grant execute on function public.platform_terminate_tenant(jsonb) to service_role;
grant execute on function public.platform_get_tenant_access_gate(jsonb) to service_role;;
