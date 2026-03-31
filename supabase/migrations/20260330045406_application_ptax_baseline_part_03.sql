create or replace function public.platform_upsert_ptax_configuration(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_ptax_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_configuration_id uuid;
  v_state_code text := upper(nullif(btrim(coalesce(p_params->>'state_code', '')), ''));
  v_effective_from date := public.platform_ptax_try_date(p_params->>'effective_from');
  v_effective_to date := public.platform_ptax_try_date(p_params->>'effective_to');
  v_slabs jsonb := coalesce(p_params->'slabs', '[]'::jsonb);
  v_frequency text := upper(coalesce(nullif(btrim(p_params->>'deduction_frequency'), ''), 'MONTHLY'));
  v_frequency_months integer[] := coalesce((select array_agg(value::integer) from jsonb_array_elements_text(coalesce(p_params->'frequency_months', '[]'::jsonb)) value), '{}'::integer[]);
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  if v_state_code is null then return public.platform_json_response(false,'STATE_CODE_REQUIRED','state_code is required.','{}'::jsonb); end if;
  if v_effective_from is null then return public.platform_json_response(false,'EFFECTIVE_FROM_REQUIRED','effective_from is required.','{}'::jsonb); end if;
  if v_effective_to is not null and v_effective_to < v_effective_from then return public.platform_json_response(false,'INVALID_EFFECTIVE_WINDOW','effective_to cannot be earlier than effective_from.','{}'::jsonb); end if;
  if jsonb_typeof(v_slabs) <> 'array' then return public.platform_json_response(false,'SLABS_INVALID','slabs must be a JSON array.','{}'::jsonb); end if;

  execute format(
    'insert into %I.wcm_ptax_configuration (state_code, effective_from, effective_to, slabs, deduction_frequency, frequency_months, configuration_status, configuration_version, statutory_reference, version_notes, config_metadata, created_by_actor_user_id, updated_by_actor_user_id)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$12)
     on conflict (state_code, effective_from) do update
     set effective_to = excluded.effective_to,
         slabs = excluded.slabs,
         deduction_frequency = excluded.deduction_frequency,
         frequency_months = excluded.frequency_months,
         configuration_status = excluded.configuration_status,
         configuration_version = excluded.configuration_version,
         statutory_reference = excluded.statutory_reference,
         version_notes = excluded.version_notes,
         config_metadata = excluded.config_metadata,
         updated_by_actor_user_id = excluded.updated_by_actor_user_id,
         updated_at = timezone(''utc'', now())
     returning configuration_id',
    v_schema_name
  ) into v_configuration_id using
    v_state_code,
    v_effective_from,
    v_effective_to,
    v_slabs,
    v_frequency,
    v_frequency_months,
    upper(coalesce(nullif(btrim(p_params->>'configuration_status'), ''), 'ACTIVE')),
    coalesce(nullif(p_params->>'configuration_version', '')::integer, 1),
    nullif(btrim(p_params->>'statutory_reference'), ''),
    nullif(btrim(p_params->>'version_notes'), ''),
    coalesce(p_params->'config_metadata', '{}'::jsonb),
    v_actor_user_id;

  perform public.platform_ptax_append_audit(v_schema_name, 'CONFIGURATION_UPSERTED', 'SUCCESS', 'wcm_ptax_configuration', v_configuration_id::text, jsonb_build_object('state_code', v_state_code, 'effective_from', v_effective_from), v_actor_user_id);

  return public.platform_json_response(true,'OK','PTAX configuration upserted.',jsonb_build_object('configuration_id', v_configuration_id, 'state_code', v_state_code));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_upsert_ptax_configuration.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_upsert_ptax_employee_state_profile(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_ptax_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_state_profile_id uuid;
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_state_code text := upper(nullif(btrim(coalesce(p_params->>'state_code', '')), ''));
  v_effective_from date := public.platform_ptax_try_date(p_params->>'effective_from');
  v_effective_to date := public.platform_ptax_try_date(p_params->>'effective_to');
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  if v_employee_id is null then return public.platform_json_response(false,'EMPLOYEE_ID_REQUIRED','employee_id is required.','{}'::jsonb); end if;
  if v_state_code is null then return public.platform_json_response(false,'STATE_CODE_REQUIRED','state_code is required.','{}'::jsonb); end if;
  if v_effective_from is null then return public.platform_json_response(false,'EFFECTIVE_FROM_REQUIRED','effective_from is required.','{}'::jsonb); end if;
  if v_effective_to is not null and v_effective_to < v_effective_from then return public.platform_json_response(false,'INVALID_EFFECTIVE_WINDOW','effective_to cannot be earlier than effective_from.','{}'::jsonb); end if;

  execute format(
    'insert into %I.wcm_ptax_employee_state_profile (employee_id, state_code, resident_state_code, work_state_code, source_kind, effective_from, effective_to, profile_status, notes, profile_metadata, created_by_actor_user_id, updated_by_actor_user_id)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$11)
     on conflict (employee_id, effective_from) do update
     set state_code = excluded.state_code,
         resident_state_code = excluded.resident_state_code,
         work_state_code = excluded.work_state_code,
         source_kind = excluded.source_kind,
         effective_to = excluded.effective_to,
         profile_status = excluded.profile_status,
         notes = excluded.notes,
         profile_metadata = excluded.profile_metadata,
         updated_by_actor_user_id = excluded.updated_by_actor_user_id,
         updated_at = timezone(''utc'', now())
     returning state_profile_id',
    v_schema_name
  ) into v_state_profile_id using
    v_employee_id,
    v_state_code,
    upper(nullif(btrim(p_params->>'resident_state_code'), '')),
    upper(nullif(btrim(p_params->>'work_state_code'), '')),
    upper(coalesce(nullif(btrim(p_params->>'source_kind'), ''), 'MANUAL')),
    v_effective_from,
    v_effective_to,
    upper(coalesce(nullif(btrim(p_params->>'profile_status'), ''), 'ACTIVE')),
    nullif(btrim(p_params->>'notes'), ''),
    coalesce(p_params->'profile_metadata', '{}'::jsonb),
    v_actor_user_id;

  perform public.platform_ptax_append_audit(v_schema_name, 'STATE_PROFILE_UPSERTED', 'SUCCESS', 'wcm_ptax_employee_state_profile', v_state_profile_id::text, jsonb_build_object('employee_id', v_employee_id, 'state_code', v_state_code), v_actor_user_id, v_employee_id);

  return public.platform_json_response(true,'OK','PTAX employee state profile upserted.',jsonb_build_object('state_profile_id', v_state_profile_id, 'employee_id', v_employee_id, 'state_code', v_state_code));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_upsert_ptax_employee_state_profile.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_upsert_ptax_wage_component_mapping(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_ptax_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_mapping_id uuid;
  v_state_code text := upper(nullif(btrim(coalesce(p_params->>'state_code', '')), ''));
  v_component_code text := upper(nullif(btrim(coalesce(p_params->>'component_code', '')), ''));
  v_effective_from date := public.platform_ptax_try_date(p_params->>'effective_from');
  v_effective_to date := public.platform_ptax_try_date(p_params->>'effective_to');
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  if v_state_code is null then return public.platform_json_response(false,'STATE_CODE_REQUIRED','state_code is required.','{}'::jsonb); end if;
  if v_component_code is null then return public.platform_json_response(false,'COMPONENT_CODE_REQUIRED','component_code is required.','{}'::jsonb); end if;
  if v_effective_from is null then return public.platform_json_response(false,'EFFECTIVE_FROM_REQUIRED','effective_from is required.','{}'::jsonb); end if;
  if v_effective_to is not null and v_effective_to < v_effective_from then return public.platform_json_response(false,'INVALID_EFFECTIVE_WINDOW','effective_to cannot be earlier than effective_from.','{}'::jsonb); end if;

  execute format(
    'insert into %I.wcm_ptax_wage_component_mapping (state_code, component_code, is_ptax_eligible, effective_from, effective_to, mapping_metadata, created_by_actor_user_id, updated_by_actor_user_id)
     values ($1,$2,$3,$4,$5,$6,$7,$7)
     on conflict (state_code, component_code, effective_from) do update
     set is_ptax_eligible = excluded.is_ptax_eligible,
         effective_to = excluded.effective_to,
         mapping_metadata = excluded.mapping_metadata,
         updated_by_actor_user_id = excluded.updated_by_actor_user_id,
         updated_at = timezone(''utc'', now())
     returning wage_component_mapping_id',
    v_schema_name
  ) into v_mapping_id using
    v_state_code,
    v_component_code,
    coalesce((p_params->>'is_ptax_eligible')::boolean, true),
    v_effective_from,
    v_effective_to,
    coalesce(p_params->'mapping_metadata', '{}'::jsonb),
    v_actor_user_id;

  perform public.platform_ptax_append_audit(v_schema_name, 'WAGE_MAPPING_UPSERTED', 'SUCCESS', 'wcm_ptax_wage_component_mapping', v_mapping_id::text, jsonb_build_object('state_code', v_state_code, 'component_code', v_component_code), v_actor_user_id);

  return public.platform_json_response(true,'OK','PTAX wage component mapping upserted.',jsonb_build_object('wage_component_mapping_id', v_mapping_id, 'state_code', v_state_code, 'component_code', v_component_code));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_upsert_ptax_wage_component_mapping.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_request_ptax_batch(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_ptax_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_state_code text := upper(nullif(btrim(coalesce(p_params->>'state_code', '')), ''));
  v_payroll_period date := date_trunc('month', public.platform_ptax_try_date(p_params->>'payroll_period')::timestamp)::date;
  v_batch_id bigint;
  v_requested_employee_ids jsonb := coalesce(p_params->'employee_ids', '[]'::jsonb);
  v_exists boolean;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  if v_state_code is null then return public.platform_json_response(false,'STATE_CODE_REQUIRED','state_code is required.','{}'::jsonb); end if;
  if v_payroll_PERIOD is null then return public.platform_json_response(false,'PAYROLL_PERIOD_REQUIRED','payroll_period is required.','{}'::jsonb); end if;
  if jsonb_typeof(v_requested_employee_ids) <> 'array' then return public.platform_json_response(false,'EMPLOYEE_IDS_INVALID','employee_ids must be a JSON array.','{}'::jsonb); end if;

  execute format(
    'select exists(
       select 1
         from %I.wcm_ptax_configuration
        where state_code = $1
          and configuration_status = ''ACTIVE''
          and effective_from <= $2
          and (effective_to is null or effective_to >= $2)
     )',
    v_schema_name
  ) into v_exists using v_state_code, v_payroll_period;

  if not coalesce(v_exists, false) then
    return public.platform_json_response(false,'CONFIGURATION_NOT_FOUND','No active PTAX configuration exists for the requested state and payroll period.',jsonb_build_object('state_code', v_state_code, 'payroll_period', v_payroll_period));
  end if;

  execute format(
    'insert into %I.wcm_ptax_processing_batch (state_code, payroll_period, batch_status, requested_employee_ids, requested_by_actor_user_id, summary_payload, error_payload)
     values ($1,$2,''REQUESTED'',$3,$4,''{}''::jsonb,''{}''::jsonb)
     on conflict (state_code, payroll_period) do update
     set batch_status = ''REQUESTED'',
         requested_employee_ids = excluded.requested_employee_ids,
         requested_by_actor_user_id = excluded.requested_by_actor_user_id,
         process_started_at = null,
         process_completed_at = null,
         error_payload = ''{}''::jsonb,
         updated_at = timezone(''utc'', now())
     returning batch_id',
    v_schema_name
  ) into v_batch_id using v_state_code, v_payroll_period, v_requested_employee_ids, v_actor_user_id;

  perform public.platform_ptax_append_audit(v_schema_name, 'BATCH_REQUESTED', 'SUCCESS', 'wcm_ptax_processing_batch', v_batch_id::text, jsonb_build_object('state_code', v_state_code, 'payroll_period', v_payroll_period), v_actor_user_id, null, v_batch_id);

  return public.platform_json_response(true,'OK','PTAX batch requested.',jsonb_build_object('batch_id', v_batch_id, 'state_code', v_state_code, 'payroll_period', v_payroll_period));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_request_ptax_batch.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
