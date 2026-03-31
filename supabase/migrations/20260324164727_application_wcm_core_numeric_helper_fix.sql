set search_path = public, pg_temp;

create or replace function public.platform_wcm_try_date(p_value text)
returns date
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $function$
begin
  if nullif(btrim(coalesce(p_value, '')), '') is null then
    return null;
  end if;

  return p_value::date;
exception
  when others then
    return null;
end;
$function$;

create or replace function public.platform_wcm_try_bigint(p_value text)
returns bigint
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $function$
begin
  if nullif(btrim(coalesce(p_value, '')), '') is null then
    return null;
  end if;

  return p_value::bigint;
exception
  when others then
    return null;
end;
$function$;

create or replace function public.platform_upsert_wcm_service_state(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context_result jsonb;
  v_context_details jsonb;
  v_schema_name text;
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_input_joining_date date := public.platform_wcm_try_date(p_params->>'joining_date');
  v_input_service_state text := lower(coalesce(nullif(btrim(p_params->>'service_state'), ''), ''));
  v_input_employment_status text := nullif(btrim(coalesce(p_params->>'employment_status', '')), '');
  v_input_confirmation_date date := public.platform_wcm_try_date(p_params->>'confirmation_date');
  v_input_leaving_date date := public.platform_wcm_try_date(p_params->>'leaving_date');
  v_input_relief_date date := public.platform_wcm_try_date(p_params->>'relief_date');
  v_input_separation_type text := nullif(btrim(coalesce(p_params->>'separation_type', '')), '');
  v_input_full_and_final_status text := nullif(btrim(coalesce(p_params->>'full_and_final_status', '')), '');
  v_input_full_and_final_process_date date := public.platform_wcm_try_date(p_params->>'full_and_final_process_date');
  v_input_position_id bigint := public.platform_wcm_try_bigint(p_params->>'position_id');
  v_input_last_billable boolean := case when p_params ? 'last_billable' then (p_params->>'last_billable')::boolean else null end;
  v_input_state_notes jsonb := coalesce(p_params->'state_notes', '{}'::jsonb);
  v_employee_exists boolean := false;
  v_existing_employee_id uuid;
  v_existing_joining_date date;
  v_existing_service_state text;
  v_existing_employment_status text;
  v_existing_confirmation_date date;
  v_existing_leaving_date date;
  v_existing_relief_date date;
  v_existing_separation_type text;
  v_existing_full_and_final_status text;
  v_existing_full_and_final_process_date date;
  v_existing_position_id bigint;
  v_existing_last_billable boolean;
  v_existing_state_notes jsonb;
  v_state_exists boolean := false;
  v_final_joining_date date;
  v_final_service_state text;
  v_final_employment_status text;
  v_final_confirmation_date date;
  v_final_leaving_date date;
  v_final_relief_date date;
  v_final_separation_type text;
  v_final_full_and_final_status text;
  v_final_full_and_final_process_date date;
  v_final_position_id bigint;
  v_final_last_billable boolean;
  v_final_state_notes jsonb;
  v_current_billable boolean;
  v_event_result jsonb;
  v_event_type text;
begin
  v_context_result := public.platform_wcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  if v_employee_id is null then
    return public.platform_json_response(false, 'EMPLOYEE_ID_REQUIRED', 'employee_id is required.', '{}'::jsonb);
  end if;

  if jsonb_typeof(v_input_state_notes) is distinct from 'object' then
    return public.platform_json_response(false, 'INVALID_STATE_NOTES', 'state_notes must be a JSON object.', '{}'::jsonb);
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');

  execute format('select exists (select 1 from %I.wcm_employee where employee_id = $1)', v_schema_name)
  into v_employee_exists
  using v_employee_id;

  if not v_employee_exists then
    return public.platform_json_response(false, 'EMPLOYEE_NOT_FOUND', 'Employee not found.', jsonb_build_object('employee_id', v_employee_id));
  end if;

  execute format(
    'select employee_id, joining_date, service_state, employment_status, confirmation_date, leaving_date, relief_date, separation_type, full_and_final_status, full_and_final_process_date, position_id, last_billable, state_notes
     from %I.wcm_employee_service_state
     where employee_id = $1',
    v_schema_name
  )
  into v_existing_employee_id, v_existing_joining_date, v_existing_service_state, v_existing_employment_status, v_existing_confirmation_date, v_existing_leaving_date, v_existing_relief_date, v_existing_separation_type, v_existing_full_and_final_status, v_existing_full_and_final_process_date, v_existing_position_id, v_existing_last_billable, v_existing_state_notes
  using v_employee_id;

  v_state_exists := v_existing_employee_id is not null;

  v_final_joining_date := coalesce(v_input_joining_date, v_existing_joining_date);
  v_final_service_state := coalesce(nullif(v_input_service_state, ''), v_existing_service_state, 'active');
  v_final_employment_status := coalesce(v_input_employment_status, v_existing_employment_status, 'active');
  v_final_confirmation_date := coalesce(v_input_confirmation_date, v_existing_confirmation_date);
  v_final_leaving_date := coalesce(v_input_leaving_date, v_existing_leaving_date);
  v_final_relief_date := coalesce(v_input_relief_date, v_existing_relief_date);
  v_final_separation_type := coalesce(v_input_separation_type, v_existing_separation_type);
  v_final_full_and_final_status := coalesce(v_input_full_and_final_status, v_existing_full_and_final_status);
  v_final_full_and_final_process_date := coalesce(v_input_full_and_final_process_date, v_existing_full_and_final_process_date);
  v_final_position_id := coalesce(v_input_position_id, v_existing_position_id);
  v_final_last_billable := coalesce(v_input_last_billable, v_existing_last_billable, true);
  v_final_state_notes := case when p_params ? 'state_notes' then v_input_state_notes else coalesce(v_existing_state_notes, '{}'::jsonb) end;

  if v_final_joining_date is null then
    return public.platform_json_response(false, 'JOINING_DATE_REQUIRED', 'joining_date is required for the first service-state write.', '{}'::jsonb);
  end if;

  if v_final_service_state not in ('pending_join', 'active', 'inactive', 'separated') then
    return public.platform_json_response(false, 'INVALID_SERVICE_STATE', 'service_state is invalid.', jsonb_build_object('service_state', v_final_service_state));
  end if;

  if v_final_employment_status is null then
    return public.platform_json_response(false, 'EMPLOYMENT_STATUS_REQUIRED', 'employment_status is required.', '{}'::jsonb);
  end if;

  if v_final_leaving_date is not null and v_final_leaving_date < v_final_joining_date then
    return public.platform_json_response(false, 'INVALID_LEAVING_DATE', 'leaving_date cannot be earlier than joining_date.', '{}'::jsonb);
  end if;

  if v_final_relief_date is not null and v_final_relief_date < v_final_joining_date then
    return public.platform_json_response(false, 'INVALID_RELIEF_DATE', 'relief_date cannot be earlier than joining_date.', '{}'::jsonb);
  end if;

  if v_state_exists then
    execute format(
      'update %I.wcm_employee_service_state
       set joining_date = $1,
           service_state = $2,
           employment_status = $3,
           confirmation_date = $4,
           leaving_date = $5,
           relief_date = $6,
           separation_type = $7,
           full_and_final_status = $8,
           full_and_final_process_date = $9,
           position_id = $10,
           last_billable = $11,
           state_notes = $12,
           updated_at = timezone(''utc'', now())
       where employee_id = $13',
      v_schema_name
    )
    using v_final_joining_date, v_final_service_state, v_final_employment_status, v_final_confirmation_date, v_final_leaving_date, v_final_relief_date, v_final_separation_type, v_final_full_and_final_status, v_final_full_and_final_process_date, v_final_position_id, v_final_last_billable, v_final_state_notes, v_employee_id;
  else
    execute format(
      'insert into %I.wcm_employee_service_state (
         employee_id,
         joining_date,
         service_state,
         employment_status,
         confirmation_date,
         leaving_date,
         relief_date,
         separation_type,
         full_and_final_status,
         full_and_final_process_date,
         position_id,
         last_billable,
         state_notes
       )
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)',
      v_schema_name
    )
    using v_employee_id, v_final_joining_date, v_final_service_state, v_final_employment_status, v_final_confirmation_date, v_final_leaving_date, v_final_relief_date, v_final_separation_type, v_final_full_and_final_status, v_final_full_and_final_process_date, v_final_position_id, v_final_last_billable, v_final_state_notes;
  end if;

  v_current_billable := case
    when v_final_service_state = 'active' then true
    when v_final_service_state in ('inactive', 'separated')
      and v_final_last_billable = true
      and coalesce(lower(v_final_full_and_final_status), '') not in ('completed', 'settled', 'waived')
    then true
    else false
  end;

  v_event_type := case
    when not v_state_exists then 'service_state_initialized'
    when v_existing_service_state is distinct from v_final_service_state
      or v_existing_employment_status is distinct from v_final_employment_status
      or v_existing_full_and_final_status is distinct from v_final_full_and_final_status
    then 'service_state_changed'
    else 'service_state_updated'
  end;

  v_event_result := public.platform_log_wcm_lifecycle_event(jsonb_build_object(
    'tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),
    'employee_id', v_employee_id,
    'event_type', v_event_type,
    'source_module', coalesce(nullif(btrim(p_params->>'source_module'), ''), 'WCM_CORE'),
    'event_reason', nullif(btrim(p_params->>'event_reason'), ''),
    'prior_service_state', v_existing_service_state,
    'new_service_state', v_final_service_state,
    'prior_employment_status', v_existing_employment_status,
    'new_employment_status', v_final_employment_status,
    'event_details', jsonb_build_object(
      'joining_date', v_final_joining_date,
      'leaving_date', v_final_leaving_date,
      'relief_date', v_final_relief_date,
      'full_and_final_status', v_final_full_and_final_status,
      'full_and_final_process_date', v_final_full_and_final_process_date,
      'last_billable', v_final_last_billable,
      'current_billable', v_current_billable,
      'position_id', v_final_position_id
    )
  ));

  if coalesce((v_event_result->>'success')::boolean, false) is not true then
    return v_event_result;
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'WCM service state recorded.',
    jsonb_build_object(
      'tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),
      'employee_id', v_employee_id,
      'service_state', v_final_service_state,
      'employment_status', v_final_employment_status,
      'full_and_final_status', v_final_full_and_final_status,
      'last_billable', v_final_last_billable,
      'current_billable', v_current_billable,
      'event_type', v_event_type
    )
  );
exception
  when others then
    return public.platform_json_response(
      false,
      'UNEXPECTED_ERROR',
      'Unexpected error in platform_upsert_wcm_service_state.',
      jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
    );
end;
$function$;

revoke all on function public.platform_wcm_try_date(text) from public, anon, authenticated;
revoke all on function public.platform_wcm_try_bigint(text) from public, anon, authenticated;;
