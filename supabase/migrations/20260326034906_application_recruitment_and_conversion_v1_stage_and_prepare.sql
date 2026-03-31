create or replace function public.platform_transition_rcm_application_stage(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context_result jsonb;
  v_context_details jsonb;
  v_schema_name text;
  v_application_id uuid := public.platform_try_uuid(p_params->>'application_id');
  v_new_stage_code text := lower(nullif(btrim(coalesce(p_params->>'new_stage_code', '')), ''));
  v_stage_outcome text := lower(coalesce(nullif(btrim(p_params->>'stage_outcome'), ''), 'progressed'));
  v_event_reason text := nullif(btrim(coalesce(p_params->>'event_reason', '')), '');
  v_event_details jsonb := coalesce(p_params->'event_details', '{}'::jsonb);
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_current_stage_code text;
  v_current_status text;
  v_new_status text;
begin
  v_context_result := public.platform_rcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;
  if v_application_id is null then
    return public.platform_json_response(false, 'APPLICATION_ID_REQUIRED', 'application_id is required.', '{}'::jsonb);
  end if;
  if v_new_stage_code is null then
    return public.platform_json_response(false, 'NEW_STAGE_REQUIRED', 'new_stage_code is required.', '{}'::jsonb);
  end if;
  if v_stage_outcome not in ('progressed', 'rejected', 'withdrawn', 'returned') then
    return public.platform_json_response(false, 'INVALID_STAGE_OUTCOME', 'stage_outcome must be progressed, rejected, withdrawn, or returned.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_event_details) <> 'object' then
    return public.platform_json_response(false, 'INVALID_STAGE_EVENT_DETAILS', 'event_details must be a JSON object.', '{}'::jsonb);
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');

  execute format('select current_stage_code, application_status from %I.rcm_job_application where application_id = $1', v_schema_name)
  into v_current_stage_code, v_current_status
  using v_application_id;

  if v_current_stage_code is null then
    return public.platform_json_response(false, 'APPLICATION_NOT_FOUND', 'Application not found.', jsonb_build_object('application_id', v_application_id));
  end if;
  if v_current_status in ('converted', 'cancelled') then
    return public.platform_json_response(false, 'APPLICATION_TERMINAL', 'The application is already in a terminal state.', jsonb_build_object('application_id', v_application_id, 'application_status', v_current_status));
  end if;

  v_new_status := case v_stage_outcome when 'rejected' then 'rejected' when 'withdrawn' then 'withdrawn' else 'active' end;

  execute format(
    'update %I.rcm_job_application
     set current_stage_code = $1,
         application_status = $2,
         rejected_at = case when $2 = ''rejected'' then timezone(''utc'', now()) else rejected_at end,
         withdrawn_at = case when $2 = ''withdrawn'' then timezone(''utc'', now()) else withdrawn_at end,
         updated_at = timezone(''utc'', now())
     where application_id = $3',
    v_schema_name
  )
  using v_new_stage_code, v_new_status, v_application_id;

  execute format(
    'insert into %I.rcm_application_stage_event (application_id, prior_stage_code, new_stage_code, stage_outcome, event_reason, event_details, actor_user_id)
     values ($1, $2, $3, $4, $5, $6, $7)',
    v_schema_name
  )
  using v_application_id, v_current_stage_code, v_new_stage_code, v_stage_outcome, v_event_reason, v_event_details, v_actor_user_id;

  return public.platform_json_response(true,'OK','Recruitment application stage transitioned.',jsonb_build_object('tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),'application_id', v_application_id,'prior_stage_code', v_current_stage_code,'new_stage_code', v_new_stage_code,'application_status', v_new_status,'stage_outcome', v_stage_outcome));
exception
  when others then
    return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_transition_rcm_application_stage.',jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_prepare_rcm_conversion_contract(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context_result jsonb;
  v_context_details jsonb;
  v_schema_name text;
  v_application_id uuid := public.platform_try_uuid(p_params->>'application_id');
  v_requested_conversion_case_id uuid := public.platform_try_uuid(p_params->>'conversion_case_id');
  v_requested_position_id bigint := public.platform_hierarchy_try_bigint(p_params->>'target_position_id');
  v_conversion_notes jsonb := coalesce(p_params->'conversion_notes', '{}'::jsonb);
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_requisition_id uuid;
  v_candidate_id uuid;
  v_current_stage_code text;
  v_application_status text;
  v_requisition_position_id bigint;
  v_target_position_id bigint;
  v_position_status text;
  v_existing_case_id uuid;
  v_existing_status text;
  v_existing_converted_case uuid;
  v_validation_payload jsonb;
begin
  v_context_result := public.platform_rcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;
  if v_application_id is null then
    return public.platform_json_response(false, 'APPLICATION_ID_REQUIRED', 'application_id is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_conversion_notes) <> 'object' then
    return public.platform_json_response(false, 'INVALID_CONVERSION_NOTES', 'conversion_notes must be a JSON object.', '{}'::jsonb);
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');

  execute format(
    'select a.requisition_id, a.candidate_id, a.current_stage_code, a.application_status, r.position_id
     from %I.rcm_job_application a
     join %I.rcm_requisition r on r.requisition_id = a.requisition_id
     where a.application_id = $1',
    v_schema_name,
    v_schema_name
  )
  into v_requisition_id, v_candidate_id, v_current_stage_code, v_application_status, v_requisition_position_id
  using v_application_id;

  if v_requisition_id is null then
    return public.platform_json_response(false, 'APPLICATION_NOT_FOUND', 'Application not found.', jsonb_build_object('application_id', v_application_id));
  end if;
  if v_application_status <> 'active' then
    return public.platform_json_response(false, 'APPLICATION_NOT_READY_FOR_CONVERSION', 'Only active applications can be prepared for conversion.', jsonb_build_object('application_status', v_application_status));
  end if;
  if coalesce(v_current_stage_code, '') not in ('offer_accepted', 'ready_for_conversion', 'selected') then
    return public.platform_json_response(false, 'APPLICATION_NOT_READY_FOR_CONVERSION', 'The application has not reached a conversion-ready stage.', jsonb_build_object('current_stage_code', v_current_stage_code));
  end if;

  v_target_position_id := coalesce(v_requested_position_id, v_requisition_position_id);
  if v_target_position_id is null then
    return public.platform_json_response(false, 'TARGET_POSITION_REQUIRED', 'A target position is required before conversion.', '{}'::jsonb);
  end if;

  execute format('select position_status from %I.hierarchy_position where position_id = $1', v_schema_name)
  into v_position_status
  using v_target_position_id;
  if v_position_status is null then
    return public.platform_json_response(false, 'POSITION_NOT_FOUND', 'target_position_id was not found in the tenant.', jsonb_build_object('target_position_id', v_target_position_id));
  end if;
  if v_position_status = 'inactive' then
    return public.platform_json_response(false, 'POSITION_NOT_AVAILABLE', 'Inactive positions cannot be used for conversion.', jsonb_build_object('target_position_id', v_target_position_id));
  end if;

  execute format('select conversion_case_id, conversion_status from %I.rcm_conversion_case where application_id = $1', v_schema_name)
  into v_existing_case_id, v_existing_status
  using v_application_id;

  if v_requested_conversion_case_id is not null and v_existing_case_id is not null and v_requested_conversion_case_id <> v_existing_case_id then
    return public.platform_json_response(false, 'CONVERSION_CASE_MISMATCH', 'conversion_case_id does not match the application.', jsonb_build_object('conversion_case_id', v_requested_conversion_case_id, 'expected_conversion_case_id', v_existing_case_id));
  end if;
  if v_existing_case_id is null and v_requested_conversion_case_id is not null then
    return public.platform_json_response(false, 'CONVERSION_CASE_NOT_FOUND', 'conversion_case_id was not found for this application.', jsonb_build_object('conversion_case_id', v_requested_conversion_case_id));
  end if;

  execute format('select conversion_case_id from %I.rcm_conversion_case where candidate_id = $1 and conversion_status = ''converted'' and application_id <> $2 limit 1', v_schema_name)
  into v_existing_converted_case
  using v_candidate_id, v_application_id;
  if v_existing_converted_case is not null then
    return public.platform_json_response(false, 'CANDIDATE_ALREADY_CONVERTED', 'The candidate is already converted in this tenant.', jsonb_build_object('candidate_id', v_candidate_id, 'conversion_case_id', v_existing_converted_case));
  end if;
  if v_existing_status = 'converted' then
    return public.platform_json_response(false, 'CONVERSION_ALREADY_EXECUTED', 'The application is already converted.', jsonb_build_object('application_id', v_application_id, 'conversion_case_id', v_existing_case_id));
  end if;

  v_validation_payload := jsonb_build_object('application_id', v_application_id,'candidate_id', v_candidate_id,'requisition_id', v_requisition_id,'target_position_id', v_target_position_id,'current_stage_code', v_current_stage_code,'prepared_at', timezone('utc', now()));

  if v_existing_case_id is null then
    execute format(
      'insert into %I.rcm_conversion_case (application_id, candidate_id, requisition_id, target_position_id, conversion_status, conversion_notes, last_validation_payload, prepared_by_actor_user_id)
       values ($1, $2, $3, $4, ''ready'', $5, $6, $7)
       returning conversion_case_id',
      v_schema_name
    )
    into v_existing_case_id
    using v_application_id, v_candidate_id, v_requisition_id, v_target_position_id, v_conversion_notes, v_validation_payload, v_actor_user_id;
  else
    execute format(
      'update %I.rcm_conversion_case
       set target_position_id = $1,
           conversion_status = ''ready'',
           conversion_notes = $2,
           last_validation_payload = $3,
           prepared_at = timezone(''utc'', now()),
           prepared_by_actor_user_id = $4,
           updated_at = timezone(''utc'', now())
       where conversion_case_id = $5',
      v_schema_name
    )
    using v_target_position_id, v_conversion_notes, v_validation_payload, v_actor_user_id, v_existing_case_id;
  end if;

  perform public.platform_rcm_log_conversion_event_internal(v_schema_name, v_existing_case_id, 'prepared', jsonb_build_object('application_id', v_application_id,'target_position_id', v_target_position_id,'current_stage_code', v_current_stage_code), v_actor_user_id);

  return public.platform_json_response(true,'OK','Recruitment conversion contract prepared.',jsonb_build_object('tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),'conversion_case_id', v_existing_case_id,'application_id', v_application_id,'candidate_id', v_candidate_id,'requisition_id', v_requisition_id,'target_position_id', v_target_position_id,'conversion_status', 'ready'));
exception
  when others then
    return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_prepare_rcm_conversion_contract.',jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
