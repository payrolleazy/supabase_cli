create or replace function public.platform_register_rcm_job_application(p_params jsonb)
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
  v_input_requisition_id uuid := public.platform_try_uuid(p_params->>'requisition_id');
  v_input_candidate_id uuid := public.platform_try_uuid(p_params->>'candidate_id');
  v_input_stage_code text := nullif(lower(btrim(coalesce(p_params->>'current_stage_code', ''))), '');
  v_input_status text := nullif(lower(btrim(coalesce(p_params->>'application_status', ''))), '');
  v_input_applied_on date := case when p_params ? 'applied_on' then public.platform_rcm_try_date(p_params->>'applied_on') else null end;
  v_input_metadata jsonb := case when p_params ? 'application_metadata' then coalesce(p_params->'application_metadata', '{}'::jsonb) else null end;
  v_existing_requisition_id uuid;
  v_existing_candidate_id uuid;
  v_existing_stage_code text;
  v_existing_status text;
  v_existing_applied_on date;
  v_existing_metadata jsonb;
  v_duplicate_id uuid;
  v_operation_kind text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
begin
  v_context_result := public.platform_rcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  if v_input_status not in ('active', 'rejected', 'withdrawn', 'converted', 'cancelled') then
    return public.platform_json_response(false, 'INVALID_APPLICATION_STATUS', 'application_status is invalid.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_input_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_APPLICATION_METADATA', 'application_metadata must be a JSON object.', '{}'::jsonb);
  end if;
  if (p_params ? 'current_stage_code') and nullif(v_input_stage_code, '') is null then
    return public.platform_json_response(false, 'APPLICATION_STAGE_REQUIRED', 'current_stage_code is required.', '{}'::jsonb);
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');

  if v_application_id is not null then
    execute format(
      'select requisition_id, candidate_id, current_stage_code, application_status, applied_on, application_metadata
       from %I.rcm_job_application
       where application_id = $1',
      v_schema_name
    )
    into v_existing_requisition_id, v_existing_candidate_id, v_existing_stage_code, v_existing_status, v_existing_applied_on, v_existing_metadata
    using v_application_id;

    if v_existing_requisition_id is null then
      return public.platform_json_response(false, 'APPLICATION_NOT_FOUND', 'Application not found.', jsonb_build_object('application_id', v_application_id));
    end if;

    v_operation_kind := 'updated';
  else
    v_operation_kind := 'created';
  end if;

  v_input_requisition_id := coalesce(v_input_requisition_id, v_existing_requisition_id);
  v_input_candidate_id := coalesce(v_input_candidate_id, v_existing_candidate_id);
  v_input_stage_code := coalesce(v_input_stage_code, v_existing_stage_code, 'applied');
  v_input_status := coalesce(v_input_status, v_existing_status, 'active');
  v_input_applied_on := coalesce(v_input_applied_on, v_existing_applied_on, current_date);
  v_input_metadata := coalesce(v_input_metadata, v_existing_metadata, '{}'::jsonb);

  if v_input_requisition_id is null then
    return public.platform_json_response(false, 'REQUISITION_ID_REQUIRED', 'requisition_id is required.', '{}'::jsonb);
  end if;
  if v_input_candidate_id is null then
    return public.platform_json_response(false, 'CANDIDATE_ID_REQUIRED', 'candidate_id is required.', '{}'::jsonb);
  end if;

  execute format('select requisition_id from %I.rcm_requisition where requisition_id = $1', v_schema_name)
  into v_existing_requisition_id
  using v_input_requisition_id;
  if v_existing_requisition_id is null then
    return public.platform_json_response(false, 'REQUISITION_NOT_FOUND', 'requisition_id was not found in the tenant.', jsonb_build_object('requisition_id', v_input_requisition_id));
  end if;

  execute format('select candidate_id from %I.rcm_candidate where candidate_id = $1', v_schema_name)
  into v_existing_candidate_id
  using v_input_candidate_id;
  if v_existing_candidate_id is null then
    return public.platform_json_response(false, 'CANDIDATE_NOT_FOUND', 'candidate_id was not found in the tenant.', jsonb_build_object('candidate_id', v_input_candidate_id));
  end if;

  execute format('select application_id from %I.rcm_job_application where requisition_id = $1 and candidate_id = $2 limit 1', v_schema_name)
  into v_duplicate_id
  using v_input_requisition_id, v_input_candidate_id;
  if v_duplicate_id is not null and (v_application_id is null or v_duplicate_id <> v_application_id) then
    return public.platform_json_response(false, 'APPLICATION_ALREADY_EXISTS', 'The candidate already has an application for this requisition.', jsonb_build_object('requisition_id', v_input_requisition_id, 'candidate_id', v_input_candidate_id));
  end if;

  if v_operation_kind = 'created' then
    execute format(
      'insert into %I.rcm_job_application (requisition_id, candidate_id, current_stage_code, application_status, applied_on, application_metadata)
       values ($1, $2, $3, $4, $5, $6)
       returning application_id',
      v_schema_name
    )
    into v_application_id
    using v_input_requisition_id, v_input_candidate_id, v_input_stage_code, v_input_status, v_input_applied_on, v_input_metadata;

    execute format(
      'insert into %I.rcm_application_stage_event (application_id, prior_stage_code, new_stage_code, stage_outcome, event_reason, event_details, actor_user_id)
       values ($1, null, $2, ''progressed'', ''application_created'', jsonb_build_object(''source'', ''platform_register_rcm_job_application''), $3)',
      v_schema_name
    )
    using v_application_id, v_input_stage_code, v_actor_user_id;

    execute format(
      'update %I.rcm_candidate
       set candidate_status = case when candidate_status = ''prospect'' then ''active'' else candidate_status end,
           updated_at = timezone(''utc'', now())
       where candidate_id = $1',
      v_schema_name
    )
    using v_input_candidate_id;
  else
    execute format(
      'update %I.rcm_job_application
       set requisition_id = $1,
           candidate_id = $2,
           current_stage_code = $3,
           application_status = $4,
           applied_on = $5,
           application_metadata = $6,
           updated_at = timezone(''utc'', now())
       where application_id = $7',
      v_schema_name
    )
    using v_input_requisition_id, v_input_candidate_id, v_input_stage_code, v_input_status, v_input_applied_on, v_input_metadata, v_application_id;
  end if;

  return public.platform_json_response(true,'OK','Recruitment application registered.',jsonb_build_object('tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),'application_id', v_application_id,'operation_kind', v_operation_kind,'requisition_id', v_input_requisition_id,'candidate_id', v_input_candidate_id,'current_stage_code', v_input_stage_code,'application_status', v_input_status));
exception
  when others then
    return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_rcm_job_application.',jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
