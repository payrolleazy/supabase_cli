create or replace function public.platform_register_rcm_requisition(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context_result jsonb;
  v_context_details jsonb;
  v_schema_name text;
  v_requisition_id uuid := public.platform_try_uuid(p_params->>'requisition_id');
  v_input_code text := nullif(lower(btrim(coalesce(p_params->>'requisition_code', ''))), '');
  v_input_title text := nullif(btrim(coalesce(p_params->>'requisition_title', '')), '');
  v_input_position_id bigint := public.platform_hierarchy_try_bigint(p_params->>'position_id');
  v_input_status text := nullif(lower(btrim(coalesce(p_params->>'requisition_status', ''))), '');
  v_input_openings_count integer := case when p_params ? 'openings_count' then public.platform_rcm_try_integer(p_params->>'openings_count') else null end;
  v_input_priority_code text := nullif(lower(btrim(coalesce(p_params->>'priority_code', ''))), '');
  v_input_target_start_date date := public.platform_rcm_try_date(p_params->>'target_start_date');
  v_input_description text := nullif(btrim(coalesce(p_params->>'description', '')), '');
  v_existing_code text;
  v_existing_title text;
  v_existing_position_id bigint;
  v_existing_status text;
  v_existing_openings_count integer;
  v_existing_priority_code text;
  v_existing_target_start_date date;
  v_existing_description text;
  v_duplicate_id uuid;
  v_position_status text;
  v_operation_kind text;
begin
  v_context_result := public.platform_rcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  if v_input_status not in ('draft', 'open', 'on_hold', 'closed', 'cancelled', 'filled') then
    return public.platform_json_response(false, 'INVALID_REQUISITION_STATUS', 'requisition_status is invalid.', '{}'::jsonb);
  end if;

  if v_input_openings_count is not null and v_input_openings_count <= 0 then
    return public.platform_json_response(false, 'INVALID_OPENINGS_COUNT', 'openings_count must be greater than zero.', '{}'::jsonb);
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');

  if v_requisition_id is not null then
    execute format(
      'select requisition_code, requisition_title, position_id, requisition_status, openings_count, priority_code, target_start_date, description
       from %I.rcm_requisition
       where requisition_id = $1',
      v_schema_name
    )
    into v_existing_code, v_existing_title, v_existing_position_id, v_existing_status, v_existing_openings_count, v_existing_priority_code, v_existing_target_start_date, v_existing_description
    using v_requisition_id;

    if v_existing_code is null then
      return public.platform_json_response(false, 'REQUISITION_NOT_FOUND', 'Requisition not found.', jsonb_build_object('requisition_id', v_requisition_id));
    end if;

    v_operation_kind := 'updated';
  else
    v_operation_kind := 'created';
  end if;

  v_input_code := coalesce(v_input_code, v_existing_code);
  v_input_title := coalesce(v_input_title, v_existing_title);
  v_input_position_id := coalesce(v_input_position_id, v_existing_position_id);
  v_input_status := coalesce(v_input_status, v_existing_status, 'open');
  v_input_openings_count := coalesce(v_input_openings_count, v_existing_openings_count, 1);
  v_input_priority_code := coalesce(v_input_priority_code, v_existing_priority_code);
  v_input_target_start_date := coalesce(v_input_target_start_date, v_existing_target_start_date);
  v_input_description := coalesce(v_input_description, v_existing_description);

  if v_input_code is null then
    return public.platform_json_response(false, 'REQUISITION_CODE_REQUIRED', 'requisition_code is required.', '{}'::jsonb);
  end if;

  if v_input_title is null then
    return public.platform_json_response(false, 'REQUISITION_TITLE_REQUIRED', 'requisition_title is required.', '{}'::jsonb);
  end if;

  if v_input_position_id is null then
    return public.platform_json_response(false, 'POSITION_ID_REQUIRED', 'position_id is required.', '{}'::jsonb);
  end if;

  execute format('select position_status from %I.hierarchy_position where position_id = $1', v_schema_name)
  into v_position_status
  using v_input_position_id;

  if v_position_status is null then
    return public.platform_json_response(false, 'POSITION_NOT_FOUND', 'position_id was not found in the tenant.', jsonb_build_object('position_id', v_input_position_id));
  end if;

  if v_position_status = 'inactive' then
    return public.platform_json_response(false, 'POSITION_NOT_AVAILABLE', 'Inactive positions cannot receive requisitions.', jsonb_build_object('position_id', v_input_position_id));
  end if;

  execute format('select requisition_id from %I.rcm_requisition where lower(requisition_code) = $1 limit 1', v_schema_name)
  into v_duplicate_id
  using lower(v_input_code);

  if v_duplicate_id is not null and (v_requisition_id is null or v_duplicate_id <> v_requisition_id) then
    return public.platform_json_response(false, 'REQUISITION_CODE_EXISTS', 'requisition_code already exists in the tenant.', jsonb_build_object('requisition_code', v_input_code));
  end if;

  if v_operation_kind = 'created' then
    execute format(
      'insert into %I.rcm_requisition (requisition_code, requisition_title, position_id, requisition_status, openings_count, priority_code, target_start_date, description)
       values ($1, $2, $3, $4, $5, $6, $7, $8)
       returning requisition_id',
      v_schema_name
    )
    into v_requisition_id
    using v_input_code, v_input_title, v_input_position_id, v_input_status, v_input_openings_count, v_input_priority_code, v_input_target_start_date, v_input_description;
  else
    execute format(
      'update %I.rcm_requisition
       set requisition_code = $1,
           requisition_title = $2,
           position_id = $3,
           requisition_status = $4,
           openings_count = $5,
           priority_code = $6,
           target_start_date = $7,
           description = $8,
           updated_at = timezone(''utc'', now())
       where requisition_id = $9',
      v_schema_name
    )
    using v_input_code, v_input_title, v_input_position_id, v_input_status, v_input_openings_count, v_input_priority_code, v_input_target_start_date, v_input_description, v_requisition_id;
  end if;

  return public.platform_json_response(true,'OK','Recruitment requisition registered.',jsonb_build_object('tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),'requisition_id', v_requisition_id,'operation_kind', v_operation_kind,'requisition_code', v_input_code,'position_id', v_input_position_id,'requisition_status', v_input_status,'openings_count', v_input_openings_count));
exception
  when others then
    return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_rcm_requisition.',jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
