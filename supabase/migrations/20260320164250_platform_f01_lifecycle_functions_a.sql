create or replace function public.platform_create_tenant_registry(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.platform_resolve_actor();
  v_tenant_id uuid;
  v_requested_tenant_id uuid;
  v_tenant_code text := public.platform_normalize_tenant_code(p_params->>'tenant_code');
  v_display_name text := nullif(btrim(coalesce(p_params->>'display_name', '')), '');
  v_legal_name text := nullif(btrim(coalesce(p_params->>'legal_name', '')), '');
  v_default_currency_code text := upper(coalesce(nullif(btrim(p_params->>'default_currency_code'), ''), 'INR'));
  v_default_timezone text := coalesce(nullif(btrim(p_params->>'default_timezone'), ''), 'Asia/Kolkata');
  v_tenant_kind text := lower(coalesce(nullif(btrim(p_params->>'tenant_kind'), ''), 'client'));
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
begin
  if v_tenant_code is null then
    return public.platform_json_response(false, 'TENANT_CODE_REQUIRED', 'tenant_code is required.', jsonb_build_object('field', 'tenant_code'));
  end if;

  if v_display_name is null then
    return public.platform_json_response(false, 'DISPLAY_NAME_REQUIRED', 'display_name is required.', jsonb_build_object('field', 'display_name'));
  end if;

  if jsonb_typeof(v_metadata) is distinct from 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', jsonb_build_object('field', 'metadata'));
  end if;

  if p_params ? 'tenant_id' then
    v_requested_tenant_id := public.platform_try_uuid(p_params->>'tenant_id');
    if v_requested_tenant_id is null then
      return public.platform_json_response(false, 'INVALID_TENANT_ID', 'tenant_id must be a valid UUID when provided.', jsonb_build_object('field', 'tenant_id'));
    end if;
  end if;

  if exists (
    select 1
    from public.platform_tenant pt
    where pt.tenant_code = v_tenant_code
  ) then
    return public.platform_json_response(false, 'TENANT_CODE_ALREADY_EXISTS', 'A tenant with this tenant_code already exists.', jsonb_build_object('tenant_code', v_tenant_code));
  end if;

  v_tenant_id := coalesce(v_requested_tenant_id, gen_random_uuid());

  insert into public.platform_tenant (
    tenant_id,
    tenant_code,
    display_name,
    legal_name,
    default_currency_code,
    default_timezone,
    tenant_kind,
    created_by,
    metadata
  )
  values (
    v_tenant_id,
    v_tenant_code,
    v_display_name,
    v_legal_name,
    v_default_currency_code,
    v_default_timezone,
    v_tenant_kind,
    v_actor,
    v_metadata
  );

  insert into public.platform_tenant_provisioning (
    tenant_id,
    provisioning_status,
    schema_provisioned,
    ready_for_routing,
    details
  )
  values (
    v_tenant_id,
    'registry_created',
    false,
    false,
    '{}'::jsonb
  );

  insert into public.platform_tenant_access_state (
    tenant_id,
    access_state,
    billing_state,
    updated_by
  )
  values (
    v_tenant_id,
    'active',
    'current',
    v_actor
  );

  perform public.platform_append_status_history(v_tenant_id, 'provisioning', null, 'registry_created', 'TENANT_REGISTRY_CREATED', jsonb_build_object('tenant_code', v_tenant_code), v_actor, 'platform_create_tenant_registry');
  perform public.platform_append_status_history(v_tenant_id, 'access', null, 'active', 'TENANT_ACCESS_INITIALIZED', '{}'::jsonb, v_actor, 'platform_create_tenant_registry');
  perform public.platform_append_status_history(v_tenant_id, 'billing', null, 'current', 'TENANT_BILLING_INITIALIZED', '{}'::jsonb, v_actor, 'platform_create_tenant_registry');

  return public.platform_json_response(
    true,
    'OK',
    'Tenant registry created.',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'tenant_code', v_tenant_code,
      'provisioning_status', 'registry_created',
      'access_state', 'active',
      'billing_state', 'current',
      'ready_for_routing', false
    )
  );
exception
  when unique_violation then
    return public.platform_json_response(false, 'TENANT_CODE_ALREADY_EXISTS', 'A tenant with this tenant_code already exists.', jsonb_build_object('tenant_code', v_tenant_code));
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_create_tenant_registry.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;

create or replace function public.platform_get_tenant_registry(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_registry jsonb;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select to_jsonb(v.*)
  into v_registry
  from public.platform_tenant_registry_view v
  where v.tenant_id = v_tenant_id;

  if v_registry is null then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  return public.platform_json_response(true, 'OK', 'Tenant registry fetched.', jsonb_build_object('tenant', v_registry));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_get_tenant_registry.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;

create or replace function public.platform_transition_provisioning_state(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.platform_resolve_actor();
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_to_status text := lower(coalesce(nullif(btrim(p_params->>'to_status'), ''), ''));
  v_source text := coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_transition_provisioning_state');
  v_latest_completed_step text := nullif(btrim(coalesce(p_params->>'latest_completed_step', '')), '');
  v_foundation_version text := nullif(btrim(coalesce(p_params->>'foundation_version', '')), '');
  v_details_patch jsonb := coalesce(p_params->'details', '{}'::jsonb);
  v_last_error_code text := nullif(btrim(coalesce(p_params->>'last_error_code', '')), '');
  v_last_error_message text := nullif(btrim(coalesce(p_params->>'last_error_message', '')), '');
  v_row public.platform_tenant_provisioning%rowtype;
  v_schema_provisioned boolean;
  v_ready_for_routing boolean;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  if v_to_status = '' then
    return public.platform_json_response(false, 'PROVISIONING_STATUS_REQUIRED', 'to_status is required.', jsonb_build_object('field', 'to_status'));
  end if;

  if jsonb_typeof(v_details_patch) is distinct from 'object' then
    return public.platform_json_response(false, 'INVALID_DETAILS', 'details must be a JSON object.', jsonb_build_object('field', 'details'));
  end if;

  select *
  into v_row
  from public.platform_tenant_provisioning
  where tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant provisioning row not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if not public.platform_provisioning_transition_allowed(v_row.provisioning_status, v_to_status) then
    return public.platform_json_response(false, 'INVALID_PROVISIONING_TRANSITION', 'Provisioning transition is not allowed.', jsonb_build_object('from_status', v_row.provisioning_status, 'to_status', v_to_status));
  end if;

  v_schema_provisioned := case
    when p_params ? 'schema_provisioned' then coalesce((p_params->>'schema_provisioned')::boolean, v_row.schema_provisioned)
    when v_to_status in ('schema_ready', 'foundation_ready', 'ready_for_routing') then true
    else v_row.schema_provisioned
  end;

  v_ready_for_routing := case
    when p_params ? 'ready_for_routing' then coalesce((p_params->>'ready_for_routing')::boolean, v_row.ready_for_routing)
    when v_to_status = 'ready_for_routing' then true
    when v_to_status in ('failed', 'disabled') then false
    else v_row.ready_for_routing
  end;

  update public.platform_tenant_provisioning
  set
    provisioning_status = v_to_status,
    schema_provisioned = v_schema_provisioned,
    foundation_version = coalesce(v_foundation_version, foundation_version),
    latest_completed_step = coalesce(v_latest_completed_step, latest_completed_step),
    last_error_code = case when v_to_status = 'failed' then v_last_error_code else null end,
    last_error_message = case when v_to_status = 'failed' then v_last_error_message else null end,
    last_error_at = case when v_to_status = 'failed' and (v_last_error_code is not null or v_last_error_message is not null) then timezone('utc', now()) else null end,
    ready_for_routing = v_ready_for_routing,
    details = details || v_details_patch
  where tenant_id = v_tenant_id;

  if v_row.provisioning_status is distinct from v_to_status then
    perform public.platform_append_status_history(
      v_tenant_id,
      'provisioning',
      v_row.provisioning_status,
      v_to_status,
      case when v_to_status = 'failed' then coalesce(v_last_error_code, 'PROVISIONING_FAILED') else 'PROVISIONING_STATE_CHANGED' end,
      jsonb_build_object(
        'latest_completed_step', coalesce(v_latest_completed_step, v_row.latest_completed_step),
        'ready_for_routing', v_ready_for_routing
      ) || v_details_patch,
      v_actor,
      v_source
    );
  end if;

  return public.platform_json_response(true, 'OK', 'Provisioning state updated.', jsonb_build_object('tenant_id', v_tenant_id, 'from_status', v_row.provisioning_status, 'to_status', v_to_status, 'schema_provisioned', v_schema_provisioned, 'ready_for_routing', v_ready_for_routing));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_transition_provisioning_state.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;

create or replace function public.platform_mark_tenant_dormant(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.platform_resolve_actor();
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_source text := coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_mark_tenant_dormant');
  v_reason_code text := coalesce(nullif(btrim(p_params->>'reason_code'), ''), 'DUES_UNPAID');
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
    return public.platform_json_response(false, 'TENANT_TERMINATED', 'Terminated tenants cannot be marked dormant.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_row.access_state = 'disabled' then
    return public.platform_json_response(false, 'TENANT_DISABLED', 'Disabled tenants cannot be marked dormant.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_row.access_state in ('dormant_access_blocked', 'dormant_background_blocked') then
    return public.platform_json_response(true, 'OK', 'Tenant is already in a dormant lifecycle state.', jsonb_build_object('tenant_id', v_tenant_id, 'access_state', v_row.access_state, 'background_stop_at', v_row.background_stop_at));
  end if;

  if not public.platform_access_transition_allowed(v_row.access_state, 'dormant_access_blocked') then
    return public.platform_json_response(false, 'INVALID_ACCESS_TRANSITION', 'Access transition is not allowed.', jsonb_build_object('from_state', v_row.access_state, 'to_state', 'dormant_access_blocked'));
  end if;

  update public.platform_tenant_access_state
  set
    access_state = 'dormant_access_blocked',
    reason_code = v_reason_code,
    reason_details = v_reason_details,
    billing_state = 'dormant',
    dormant_started_at = v_now,
    background_stop_at = v_now + interval '60 days',
    restored_at = null,
    disabled_at = null,
    terminated_at = null,
    updated_by = v_actor
  where tenant_id = v_tenant_id;

  perform public.platform_append_status_history(v_tenant_id, 'access', v_row.access_state, 'dormant_access_blocked', v_reason_code, jsonb_build_object('background_stop_at', v_now + interval '60 days') || v_reason_details, v_actor, v_source);

  if v_row.billing_state is distinct from 'dormant' then
    perform public.platform_append_status_history(v_tenant_id, 'billing', v_row.billing_state, 'dormant', v_reason_code, v_reason_details, v_actor, v_source);
  end if;

  return public.platform_json_response(true, 'OK', 'Tenant marked dormant. Client access is blocked and background processing remains allowed until cutoff.', jsonb_build_object('tenant_id', v_tenant_id, 'access_state', 'dormant_access_blocked', 'billing_state', 'dormant', 'background_stop_at', v_now + interval '60 days'));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_mark_tenant_dormant.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;

create or replace function public.platform_enforce_dormant_background_cutoff(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.platform_resolve_actor();
  v_source text := coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_enforce_dormant_background_cutoff');
  v_requested_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_processed_count integer := 0;
  v_processed_tenants uuid[] := '{}';
  v_row public.platform_tenant_access_state%rowtype;
begin
  for v_row in
    select *
    from public.platform_tenant_access_state pas
    where pas.access_state = 'dormant_access_blocked'
      and pas.background_stop_at is not null
      and pas.background_stop_at <= timezone('utc', now())
      and (v_requested_tenant_id is null or pas.tenant_id = v_requested_tenant_id)
    for update
  loop
    update public.platform_tenant_access_state
    set
      access_state = 'dormant_background_blocked',
      reason_code = coalesce(reason_code, 'DORMANT_CUTOFF_REACHED'),
      billing_state = 'suspended',
      updated_by = v_actor
    where tenant_id = v_row.tenant_id;

    perform public.platform_append_status_history(v_row.tenant_id, 'access', v_row.access_state, 'dormant_background_blocked', coalesce(v_row.reason_code, 'DORMANT_CUTOFF_REACHED'), jsonb_build_object('background_stop_at', v_row.background_stop_at), v_actor, v_source);

    if v_row.billing_state is distinct from 'suspended' then
      perform public.platform_append_status_history(v_row.tenant_id, 'billing', v_row.billing_state, 'suspended', coalesce(v_row.reason_code, 'DORMANT_CUTOFF_REACHED'), jsonb_build_object('background_stop_at', v_row.background_stop_at), v_actor, v_source);
    end if;

    v_processed_count := v_processed_count + 1;
    v_processed_tenants := array_append(v_processed_tenants, v_row.tenant_id);
  end loop;

  return public.platform_json_response(true, 'OK', 'Dormant background cutoff enforcement completed.', jsonb_build_object('processed_count', v_processed_count, 'tenant_ids', to_jsonb(v_processed_tenants)));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_enforce_dormant_background_cutoff.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;;
