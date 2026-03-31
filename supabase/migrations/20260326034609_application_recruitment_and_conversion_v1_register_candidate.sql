create or replace function public.platform_register_rcm_candidate(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context_result jsonb;
  v_context_details jsonb;
  v_schema_name text;
  v_candidate_id uuid := public.platform_try_uuid(p_params->>'candidate_id');
  v_input_code text := nullif(lower(btrim(coalesce(p_params->>'candidate_code', ''))), '');
  v_input_first_name text := nullif(btrim(coalesce(p_params->>'first_name', '')), '');
  v_input_middle_name text := nullif(btrim(coalesce(p_params->>'middle_name', '')), '');
  v_input_last_name text := nullif(btrim(coalesce(p_params->>'last_name', '')), '');
  v_input_primary_email text := nullif(lower(btrim(coalesce(p_params->>'primary_email', ''))), '');
  v_input_primary_phone text := nullif(btrim(coalesce(p_params->>'primary_phone', '')), '');
  v_input_source_code text := nullif(lower(btrim(coalesce(p_params->>'source_code', ''))), '');
  v_input_status text := nullif(lower(btrim(coalesce(p_params->>'candidate_status', ''))), '');
  v_existing_code text;
  v_existing_first_name text;
  v_existing_middle_name text;
  v_existing_last_name text;
  v_existing_primary_email text;
  v_existing_primary_phone text;
  v_existing_source_code text;
  v_existing_status text;
  v_duplicate_id uuid;
  v_operation_kind text;
begin
  v_context_result := public.platform_rcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  if v_input_status not in ('prospect', 'active', 'withdrawn', 'rejected', 'converted', 'archived') then
    return public.platform_json_response(false, 'INVALID_CANDIDATE_STATUS', 'candidate_status is invalid.', '{}'::jsonb);
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');

  if v_candidate_id is not null then
    execute format(
      'select candidate_code, first_name, middle_name, last_name, primary_email, primary_phone, source_code, candidate_status
       from %I.rcm_candidate
       where candidate_id = $1',
      v_schema_name
    )
    into v_existing_code, v_existing_first_name, v_existing_middle_name, v_existing_last_name, v_existing_primary_email, v_existing_primary_phone, v_existing_source_code, v_existing_status
    using v_candidate_id;

    if v_existing_code is null then
      return public.platform_json_response(false, 'CANDIDATE_NOT_FOUND', 'Candidate not found.', jsonb_build_object('candidate_id', v_candidate_id));
    end if;

    v_operation_kind := 'updated';
  else
    v_operation_kind := 'created';
  end if;

  v_input_code := coalesce(v_input_code, v_existing_code);
  v_input_first_name := coalesce(v_input_first_name, v_existing_first_name);
  v_input_middle_name := coalesce(v_input_middle_name, v_existing_middle_name);
  v_input_last_name := coalesce(v_input_last_name, v_existing_last_name);
  v_input_primary_email := coalesce(v_input_primary_email, v_existing_primary_email);
  v_input_primary_phone := coalesce(v_input_primary_phone, v_existing_primary_phone);
  v_input_source_code := coalesce(v_input_source_code, v_existing_source_code);
  v_input_status := coalesce(v_input_status, v_existing_status, 'active');

  if v_input_code is null then
    return public.platform_json_response(false, 'CANDIDATE_CODE_REQUIRED', 'candidate_code is required.', '{}'::jsonb);
  end if;
  if v_input_first_name is null or v_input_last_name is null then
    return public.platform_json_response(false, 'CANDIDATE_NAME_REQUIRED', 'first_name and last_name are required.', '{}'::jsonb);
  end if;
  if v_input_primary_email is null then
    return public.platform_json_response(false, 'CANDIDATE_EMAIL_REQUIRED', 'primary_email is required.', '{}'::jsonb);
  end if;

  execute format('select candidate_id from %I.rcm_candidate where lower(candidate_code) = $1 limit 1', v_schema_name)
  into v_duplicate_id
  using lower(v_input_code);
  if v_duplicate_id is not null and (v_candidate_id is null or v_duplicate_id <> v_candidate_id) then
    return public.platform_json_response(false, 'CANDIDATE_CODE_EXISTS', 'candidate_code already exists in the tenant.', jsonb_build_object('candidate_code', v_input_code));
  end if;

  execute format('select candidate_id from %I.rcm_candidate where lower(primary_email) = $1 limit 1', v_schema_name)
  into v_duplicate_id
  using lower(v_input_primary_email);
  if v_duplicate_id is not null and (v_candidate_id is null or v_duplicate_id <> v_candidate_id) then
    return public.platform_json_response(false, 'CANDIDATE_EMAIL_EXISTS', 'primary_email already exists in the tenant.', jsonb_build_object('primary_email', v_input_primary_email));
  end if;

  if v_operation_kind = 'created' then
    execute format(
      'insert into %I.rcm_candidate (candidate_code, first_name, middle_name, last_name, primary_email, primary_phone, source_code, candidate_status)
       values ($1, $2, $3, $4, $5, $6, $7, $8)
       returning candidate_id',
      v_schema_name
    )
    into v_candidate_id
    using v_input_code, v_input_first_name, v_input_middle_name, v_input_last_name, v_input_primary_email, v_input_primary_phone, v_input_source_code, v_input_status;
  else
    execute format(
      'update %I.rcm_candidate
       set candidate_code = $1,
           first_name = $2,
           middle_name = $3,
           last_name = $4,
           primary_email = $5,
           primary_phone = $6,
           source_code = $7,
           candidate_status = $8,
           updated_at = timezone(''utc'', now())
       where candidate_id = $9',
      v_schema_name
    )
    using v_input_code, v_input_first_name, v_input_middle_name, v_input_last_name, v_input_primary_email, v_input_primary_phone, v_input_source_code, v_input_status, v_candidate_id;
  end if;

  return public.platform_json_response(true,'OK','Recruitment candidate registered.',jsonb_build_object('tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),'candidate_id', v_candidate_id,'operation_kind', v_operation_kind,'candidate_code', v_input_code,'candidate_status', v_input_status,'primary_email', v_input_primary_email));
exception
  when others then
    return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_rcm_candidate.',jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
