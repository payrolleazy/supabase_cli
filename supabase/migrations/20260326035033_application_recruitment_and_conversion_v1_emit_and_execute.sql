create or replace function public.platform_emit_rcm_conversion_billable_event(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_conversion_case_id uuid := public.platform_try_uuid(p_params->>'conversion_case_id');
  v_application_id uuid := public.platform_try_uuid(p_params->>'application_id');
  v_candidate_id uuid := public.platform_try_uuid(p_params->>'candidate_id');
  v_requisition_id uuid := public.platform_try_uuid(p_params->>'requisition_id');
  v_wcm_employee_id uuid := public.platform_try_uuid(p_params->>'wcm_employee_id');
  v_target_position_id bigint := public.platform_hierarchy_try_bigint(p_params->>'target_position_id');
  v_occurred_on date := coalesce(public.platform_rcm_try_date(p_params->>'occurred_on'), current_date);
  v_idempotency_key text := coalesce(nullif(btrim(p_params->>'idempotency_key'), ''), 'rcm_conversion:' || coalesce(v_conversion_case_id::text, 'unknown'));
  v_result jsonb;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;
  if v_conversion_case_id is null then
    return public.platform_json_response(false, 'CONVERSION_CASE_ID_REQUIRED', 'conversion_case_id is required.', '{}'::jsonb);
  end if;

  v_result := public.platform_register_billable_unit(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'metric_code', 'recruitment_conversion',
    'quantity', 1,
    'source_type', 'recruitment_conversion',
    'source_id', v_conversion_case_id::text,
    'occurred_on', v_occurred_on,
    'idempotency_key', v_idempotency_key,
    'source_reference', jsonb_build_object('conversion_case_id', v_conversion_case_id,'application_id', v_application_id,'candidate_id', v_candidate_id,'requisition_id', v_requisition_id,'wcm_employee_id', v_wcm_employee_id,'target_position_id', v_target_position_id)
  ));

  if coalesce((v_result->>'success')::boolean, false) is not true then
    return v_result;
  end if;

  return public.platform_json_response(true,'OK','Recruitment conversion billable event emitted.',jsonb_build_object('tenant_id', v_tenant_id,'conversion_case_id', v_conversion_case_id,'billing', v_result->'details'));
exception
  when others then
    return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_emit_rcm_conversion_billable_event.',jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_execute_rcm_conversion(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context_result jsonb;
  v_context_details jsonb;
  v_schema_name text;
  v_conversion_case_id uuid := public.platform_try_uuid(p_params->>'conversion_case_id');
  v_application_id uuid := public.platform_try_uuid(p_params->>'application_id');
  v_employee_code text := nullif(btrim(coalesce(p_params->>'employee_code', '')), '');
  v_employee_actor_user_id uuid := public.platform_try_uuid(p_params->>'employee_actor_user_id');
  v_joining_date date := coalesce(public.platform_rcm_try_date(p_params->>'joining_date'), current_date);
  v_service_state text := lower(coalesce(nullif(btrim(p_params->>'service_state'), ''), 'pending_join'));
  v_employment_status text := coalesce(nullif(btrim(p_params->>'employment_status'), ''), 'preboarding');
  v_conversion_notes jsonb := coalesce(p_params->'conversion_notes', '{}'::jsonb);
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_candidate_id uuid;
  v_requisition_id uuid;
  v_target_position_id bigint;
  v_conversion_status text;
  v_existing_employee_id uuid;
  v_current_stage_code text;
  v_application_status text;
  v_candidate_code text;
  v_candidate_first_name text;
  v_candidate_middle_name text;
  v_candidate_last_name text;
  v_candidate_email text;
  v_requisition_openings integer;
  v_requisition_status text;
  v_register_employee_result jsonb;
  v_service_state_result jsonb;
  v_billable_result jsonb;
  v_employee_id uuid;
  v_converted_count integer;
begin
  v_context_result := public.platform_rcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;
  if jsonb_typeof(v_conversion_notes) <> 'object' then
    return public.platform_json_response(false, 'INVALID_CONVERSION_NOTES', 'conversion_notes must be a JSON object.', '{}'::jsonb);
  end if;
  if v_service_state not in ('pending_join', 'active') then
    return public.platform_json_response(false, 'INVALID_CONVERSION_SERVICE_STATE', 'service_state must be pending_join or active.', '{}'::jsonb);
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');

  if v_conversion_case_id is null then
    if v_application_id is null then
      return public.platform_json_response(false, 'CONVERSION_CASE_REFERENCE_REQUIRED', 'conversion_case_id or application_id is required.', '{}'::jsonb);
    end if;
    execute format('select conversion_case_id from %I.rcm_conversion_case where application_id = $1', v_schema_name)
    into v_conversion_case_id
    using v_application_id;
  end if;

  if v_conversion_case_id is null then
    return public.platform_json_response(false, 'CONVERSION_CASE_NOT_FOUND', 'Conversion case not found.', jsonb_build_object('application_id', v_application_id));
  end if;

  execute format(
    'select c.application_id, c.candidate_id, c.requisition_id, c.target_position_id, c.conversion_status, c.wcm_employee_id,
            a.current_stage_code, a.application_status,
            cand.candidate_code, cand.first_name, cand.middle_name, cand.last_name, cand.primary_email,
            r.openings_count, r.requisition_status
     from %I.rcm_conversion_case c
     join %I.rcm_job_application a on a.application_id = c.application_id
     join %I.rcm_candidate cand on cand.candidate_id = c.candidate_id
     join %I.rcm_requisition r on r.requisition_id = c.requisition_id
     where c.conversion_case_id = $1',
    v_schema_name,
    v_schema_name,
    v_schema_name,
    v_schema_name
  )
  into v_application_id, v_candidate_id, v_requisition_id, v_target_position_id, v_conversion_status, v_existing_employee_id, v_current_stage_code, v_application_status, v_candidate_code, v_candidate_first_name, v_candidate_middle_name, v_candidate_last_name, v_candidate_email, v_requisition_openings, v_requisition_status
  using v_conversion_case_id;

  if v_application_id is null then
    return public.platform_json_response(false, 'CONVERSION_CASE_NOT_FOUND', 'Conversion case not found.', jsonb_build_object('conversion_case_id', v_conversion_case_id));
  end if;
  if v_conversion_status = 'converted' and v_existing_employee_id is not null then
    return public.platform_json_response(true,'OK','Recruitment conversion already executed.',jsonb_build_object('tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),'conversion_case_id', v_conversion_case_id,'application_id', v_application_id,'employee_id', v_existing_employee_id,'operation_kind', 'noop'));
  end if;
  if v_conversion_status <> 'ready' then
    return public.platform_json_response(false, 'CONVERSION_NOT_PREPARED', 'The conversion case must be in ready status before execution.', jsonb_build_object('conversion_case_id', v_conversion_case_id, 'conversion_status', v_conversion_status));
  end if;
  if v_application_status <> 'active' then
    return public.platform_json_response(false, 'APPLICATION_NOT_READY_FOR_CONVERSION', 'Only active applications can be converted.', jsonb_build_object('application_status', v_application_status));
  end if;

  if v_employee_code is null then
    v_employee_code := upper(v_candidate_code) || '-EMP';
  end if;

  v_register_employee_result := public.platform_register_wcm_employee(jsonb_build_object('tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),'employee_id', v_existing_employee_id,'employee_code', v_employee_code,'first_name', v_candidate_first_name,'middle_name', v_candidate_middle_name,'last_name', v_candidate_last_name,'official_email', v_candidate_email,'employee_actor_user_id', v_employee_actor_user_id));
  if coalesce((v_register_employee_result->>'success')::boolean, false) is not true then
    return v_register_employee_result;
  end if;
  v_employee_id := public.platform_try_uuid(v_register_employee_result->'details'->>'employee_id');

  v_service_state_result := public.platform_upsert_wcm_service_state(jsonb_build_object('tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),'employee_id', v_employee_id,'joining_date', v_joining_date,'service_state', v_service_state,'employment_status', v_employment_status,'position_id', v_target_position_id,'last_billable', false,'state_notes', jsonb_build_object('source_module', 'RECRUITMENT_AND_CONVERSION','conversion_case_id', v_conversion_case_id,'application_id', v_application_id)));
  if coalesce((v_service_state_result->>'success')::boolean, false) is not true then
    raise exception 'RCM_SERVICE_STATE_APPLY_FAILED: %', v_service_state_result::text;
  end if;

  execute format('update %I.rcm_job_application set current_stage_code = ''converted'', application_status = ''converted'', converted_at = timezone(''utc'', now()), updated_at = timezone(''utc'', now()) where application_id = $1', v_schema_name)
  using v_application_id;

  execute format(
    'insert into %I.rcm_application_stage_event (application_id, prior_stage_code, new_stage_code, stage_outcome, event_reason, event_details, actor_user_id)
     values ($1, $2, ''converted'', ''converted'', ''conversion_executed'', jsonb_build_object(''conversion_case_id'', $3, ''employee_id'', $4), $5)',
    v_schema_name
  )
  using v_application_id, v_current_stage_code, v_conversion_case_id, v_employee_id, v_actor_user_id;

  execute format('update %I.rcm_candidate set candidate_status = ''converted'', updated_at = timezone(''utc'', now()) where candidate_id = $1', v_schema_name)
  using v_candidate_id;

  execute format('update %I.rcm_conversion_case set conversion_status = ''converted'', converted_at = timezone(''utc'', now()), wcm_employee_id = $1, conversion_notes = $2, converted_by_actor_user_id = $3, updated_at = timezone(''utc'', now()) where conversion_case_id = $4', v_schema_name)
  using v_employee_id, v_conversion_notes, v_actor_user_id, v_conversion_case_id;

  perform public.platform_rcm_log_conversion_event_internal(v_schema_name, v_conversion_case_id, 'converted', jsonb_build_object('application_id', v_application_id,'employee_id', v_employee_id,'target_position_id', v_target_position_id,'service_state', v_service_state,'employment_status', v_employment_status), v_actor_user_id);

  v_billable_result := public.platform_emit_rcm_conversion_billable_event(jsonb_build_object('tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),'conversion_case_id', v_conversion_case_id,'application_id', v_application_id,'candidate_id', v_candidate_id,'requisition_id', v_requisition_id,'wcm_employee_id', v_employee_id,'target_position_id', v_target_position_id,'occurred_on', current_date,'idempotency_key', 'rcm_conversion:' || v_conversion_case_id::text));
  if coalesce((v_billable_result->>'success')::boolean, false) is not true then
    raise exception 'RCM_BILLABLE_EMIT_FAILED: %', v_billable_result::text;
  end if;

  perform public.platform_rcm_log_conversion_event_internal(v_schema_name, v_conversion_case_id, 'billing_emitted', jsonb_build_object('billing', v_billable_result->'details'), v_actor_user_id);

  execute format('select count(*)::integer from %I.rcm_job_application where requisition_id = $1 and application_status = ''converted''', v_schema_name)
  into v_converted_count
  using v_requisition_id;

  if coalesce(v_converted_count, 0) >= coalesce(v_requisition_openings, 1)
     and coalesce(v_requisition_status, 'open') not in ('cancelled', 'closed', 'filled') then
    execute format('update %I.rcm_requisition set requisition_status = ''filled'', updated_at = timezone(''utc'', now()) where requisition_id = $1', v_schema_name)
    using v_requisition_id;
  end if;

  return public.platform_json_response(true,'OK','Recruitment conversion executed.',jsonb_build_object('tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),'conversion_case_id', v_conversion_case_id,'application_id', v_application_id,'candidate_id', v_candidate_id,'employee_id', v_employee_id,'target_position_id', v_target_position_id,'billing', v_billable_result->'details','operation_kind', 'converted'));
exception
  when others then
    return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_execute_rcm_conversion.',jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
