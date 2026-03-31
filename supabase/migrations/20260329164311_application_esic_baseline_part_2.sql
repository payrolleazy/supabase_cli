create or replace function public.platform_upsert_esic_configuration(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_esic_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_state_code text := upper(nullif(btrim(coalesce(p_params->>'state_code', '')), ''));
  v_effective_from date := coalesce(public.platform_esic_try_date(p_params->>'effective_from'), current_date);
  v_effective_to date := public.platform_esic_try_date(p_params->>'effective_to');
  v_configuration_id uuid;
  v_overlap_count integer;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_state_code is null then return public.platform_json_response(false,'STATE_CODE_REQUIRED','state_code is required.','{}'::jsonb); end if;

  execute format(
    'select count(*)
       from %I.wcm_esic_configuration
      where state_code = $1
        and configuration_status = ''ACTIVE''
        and effective_from <> $2
        and daterange(effective_from, coalesce(effective_to, ''9999-12-31''::date), ''[]'') && daterange($2, coalesce($3, ''9999-12-31''::date), ''[]'')',
    v_schema_name
  ) into v_overlap_count using v_state_code, v_effective_from, v_effective_to;

  if coalesce(v_overlap_count, 0) > 0 then
    return public.platform_json_response(false,'CONFIG_OVERLAP','ESIC configuration windows overlap for the given state.',jsonb_build_object('state_code', v_state_code,'effective_from', v_effective_from,'effective_to', v_effective_to));
  end if;

  execute format(
    'insert into %I.wcm_esic_configuration (state_code, effective_from, effective_to, wage_ceiling, employee_contribution_rate, employer_contribution_rate, configuration_status, statutory_reference, version_notes, config_metadata, created_by_actor_user_id, updated_by_actor_user_id)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$11)
     on conflict (state_code, effective_from) do update
     set effective_to = excluded.effective_to,
         wage_ceiling = excluded.wage_ceiling,
         employee_contribution_rate = excluded.employee_contribution_rate,
         employer_contribution_rate = excluded.employer_contribution_rate,
         configuration_status = excluded.configuration_status,
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
    coalesce(public.platform_esic_try_numeric(p_params->>'wage_ceiling'), 21000.00),
    coalesce(public.platform_esic_try_numeric(p_params->>'employee_contribution_rate'), 0.75),
    coalesce(public.platform_esic_try_numeric(p_params->>'employer_contribution_rate'), 3.25),
    upper(coalesce(nullif(btrim(p_params->>'configuration_status'), ''), 'ACTIVE')),
    nullif(btrim(p_params->>'statutory_reference'), ''),
    nullif(btrim(p_params->>'version_notes'), ''),
    coalesce(p_params->'config_metadata', '{}'::jsonb),
    v_actor_user_id;

  perform public.platform_esic_append_audit(v_schema_name, 'CONFIG_UPSERT', 'OK', 'CONFIGURATION', v_configuration_id::text, jsonb_build_object('state_code', v_state_code), v_actor_user_id, null, null);
  return public.platform_json_response(true,'OK','ESIC configuration upserted.',jsonb_build_object('configuration_id', v_configuration_id,'state_code', v_state_code));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_upsert_esic_configuration.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_esic_establishment(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_esic_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_establishment_id uuid;
  v_code text := lower(nullif(btrim(coalesce(p_params->>'establishment_code', '')), ''));
  v_name text := nullif(btrim(coalesce(p_params->>'establishment_name', '')), '');
  v_registration_code text := upper(nullif(btrim(coalesce(p_params->>'registration_code', '')), ''));
  v_state_code text := upper(nullif(btrim(coalesce(p_params->>'state_code', '')), ''));
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_code is null then return public.platform_json_response(false,'ESTABLISHMENT_CODE_REQUIRED','establishment_code is required.','{}'::jsonb); end if;
  if v_name is null then return public.platform_json_response(false,'ESTABLISHMENT_NAME_REQUIRED','establishment_name is required.','{}'::jsonb); end if;
  if v_registration_code is null then return public.platform_json_response(false,'REGISTRATION_CODE_REQUIRED','registration_code is required.','{}'::jsonb); end if;
  if v_state_code is null then return public.platform_json_response(false,'STATE_CODE_REQUIRED','state_code is required.','{}'::jsonb); end if;

  execute format(
    'insert into %I.wcm_esic_establishment (establishment_code, establishment_name, registration_code, state_code, address_payload, contact_person, contact_email, contact_phone, registration_date, coverage_start_date, establishment_status, establishment_metadata, created_by_actor_user_id, updated_by_actor_user_id)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13)
     on conflict (establishment_code) do update
     set establishment_name = excluded.establishment_name,
         registration_code = excluded.registration_code,
         state_code = excluded.state_code,
         address_payload = excluded.address_payload,
         contact_person = excluded.contact_person,
         contact_email = excluded.contact_email,
         contact_phone = excluded.contact_phone,
         registration_date = excluded.registration_date,
         coverage_start_date = excluded.coverage_start_date,
         establishment_status = excluded.establishment_status,
         establishment_metadata = excluded.establishment_metadata,
         updated_by_actor_user_id = excluded.updated_by_actor_user_id,
         updated_at = timezone(''utc'', now())
     returning establishment_id',
    v_schema_name
  ) into v_establishment_id using
    v_code,
    v_name,
    v_registration_code,
    v_state_code,
    coalesce(p_params->'address_payload', '{}'::jsonb),
    nullif(btrim(p_params->>'contact_person'), ''),
    nullif(btrim(p_params->>'contact_email'), ''),
    nullif(btrim(p_params->>'contact_phone'), ''),
    public.platform_esic_try_date(p_params->>'registration_date'),
    public.platform_esic_try_date(p_params->>'coverage_start_date'),
    upper(coalesce(nullif(btrim(p_params->>'establishment_status'), ''), 'ACTIVE')),
    coalesce(p_params->'establishment_metadata', '{}'::jsonb),
    v_actor_user_id;

  perform public.platform_esic_append_audit(v_schema_name, 'ESTABLISHMENT_UPSERT', 'OK', 'ESTABLISHMENT', v_establishment_id::text, jsonb_build_object('establishment_code', v_code), v_actor_user_id, null, null);
  return public.platform_json_response(true,'OK','ESIC establishment registered.',jsonb_build_object('establishment_id', v_establishment_id,'establishment_code', v_code));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_esic_establishment.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_esic_employee_registration(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_esic_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_establishment_id uuid := public.platform_try_uuid(p_params->>'establishment_id');
  v_registration_date date := coalesce(public.platform_esic_try_date(p_params->>'registration_date'), current_date);
  v_registration_id uuid;
  v_establishment record;
  v_exists boolean := false;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_employee_id is null then return public.platform_json_response(false,'EMPLOYEE_ID_REQUIRED','employee_id is required.','{}'::jsonb); end if;
  if v_establishment_id is null then return public.platform_json_response(false,'ESTABLISHMENT_ID_REQUIRED','establishment_id is required.','{}'::jsonb); end if;

  execute format(
    'select establishment_id, state_code, establishment_status
       from %I.wcm_esic_establishment
      where establishment_id = $1',
    v_schema_name
  ) into v_establishment using v_establishment_id;

  if v_establishment.establishment_id is null then
    return public.platform_json_response(false,'ESTABLISHMENT_NOT_FOUND','ESIC establishment was not found.',jsonb_build_object('establishment_id', v_establishment_id));
  end if;

  if coalesce(v_establishment.establishment_status, '') <> 'ACTIVE' then
    return public.platform_json_response(false,'ESTABLISHMENT_NOT_ACTIVE','ESIC establishment must be ACTIVE before employee registration.',jsonb_build_object('establishment_id', v_establishment_id,'establishment_status', v_establishment.establishment_status));
  end if;

  execute format('select exists(select 1 from %I.wcm_employee where employee_id = $1)', v_schema_name) into v_exists using v_employee_id;
  if not coalesce(v_exists, false) then
    return public.platform_json_response(false,'EMPLOYEE_NOT_FOUND','employee_id was not found in tenant WCM truth.',jsonb_build_object('employee_id', v_employee_id));
  end if;

  execute format(
    'insert into %I.wcm_esic_employee_registration (employee_id, establishment_id, ip_number, registration_date, effective_from, effective_to, exit_date, wage_basis_override, registration_status, previous_status, status_changed_at, status_changed_by_actor_user_id, exemption_reason, nominee_details, family_details, registration_metadata, created_by_actor_user_id, updated_by_actor_user_id)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,null,timezone(''utc'', now()),$10,$11,$12,$13,$14,$10,$10)
     on conflict (employee_id, establishment_id, registration_date) do update
     set ip_number = excluded.ip_number,
         effective_from = excluded.effective_from,
         effective_to = excluded.effective_to,
         exit_date = excluded.exit_date,
         wage_basis_override = excluded.wage_basis_override,
         previous_status = %I.wcm_esic_employee_registration.registration_status,
         registration_status = excluded.registration_status,
         status_changed_at = timezone(''utc'', now()),
         status_changed_by_actor_user_id = excluded.status_changed_by_actor_user_id,
         exemption_reason = excluded.exemption_reason,
         nominee_details = excluded.nominee_details,
         family_details = excluded.family_details,
         registration_metadata = excluded.registration_metadata,
         updated_by_actor_user_id = excluded.updated_by_actor_user_id,
         updated_at = timezone(''utc'', now())
     returning registration_id',
    v_schema_name, v_schema_name
  ) into v_registration_id using
    v_employee_id,
    v_establishment_id,
    nullif(btrim(p_params->>'ip_number'), ''),
    v_registration_date,
    coalesce(public.platform_esic_try_date(p_params->>'effective_from'), v_registration_date),
    public.platform_esic_try_date(p_params->>'effective_to'),
    public.platform_esic_try_date(p_params->>'exit_date'),
    public.platform_esic_try_numeric(p_params->>'wage_basis_override'),
    upper(coalesce(nullif(btrim(p_params->>'registration_status'), ''), 'ACTIVE')),
    v_actor_user_id,
    nullif(btrim(p_params->>'exemption_reason'), ''),
    coalesce(p_params->'nominee_details', '[]'::jsonb),
    coalesce(p_params->'family_details', '[]'::jsonb),
    coalesce(p_params->'registration_metadata', '{}'::jsonb);

  perform public.platform_esic_append_audit(v_schema_name, 'REGISTRATION_UPSERT', 'OK', 'REGISTRATION', v_registration_id::text, jsonb_build_object('employee_id', v_employee_id,'establishment_id', v_establishment_id), v_actor_user_id, v_employee_id, null);
  return public.platform_json_response(true,'OK','ESIC employee registration saved.',jsonb_build_object('registration_id', v_registration_id,'employee_id', v_employee_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_esic_employee_registration.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_upsert_esic_wage_component_mapping(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_esic_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_component_code text := upper(nullif(btrim(coalesce(p_params->>'component_code', '')), ''));
  v_mapping_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_component_code is null then return public.platform_json_response(false,'COMPONENT_CODE_REQUIRED','component_code is required.','{}'::jsonb); end if;

  execute format(
    'insert into %I.wcm_esic_wage_component_mapping (component_code, is_esic_eligible, component_category, inclusion_reason, effective_from, effective_to, mapping_metadata, created_by_actor_user_id, updated_by_actor_user_id)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$8)
     on conflict (component_code, effective_from) do update
     set is_esic_eligible = excluded.is_esic_eligible,
         component_category = excluded.component_category,
         inclusion_reason = excluded.inclusion_reason,
         effective_to = excluded.effective_to,
         mapping_metadata = excluded.mapping_metadata,
         updated_by_actor_user_id = excluded.updated_by_actor_user_id,
         updated_at = timezone(''utc'', now())
     returning wage_component_mapping_id',
    v_schema_name
  ) into v_mapping_id using
    v_component_code,
    coalesce((p_params->>'is_esic_eligible')::boolean, true),
    nullif(btrim(p_params->>'component_category'), ''),
    nullif(btrim(p_params->>'inclusion_reason'), ''),
    coalesce(public.platform_esic_try_date(p_params->>'effective_from'), current_date),
    public.platform_esic_try_date(p_params->>'effective_to'),
    coalesce(p_params->'mapping_metadata', '{}'::jsonb),
    v_actor_user_id;

  perform public.platform_esic_append_audit(v_schema_name, 'WAGE_MAPPING_UPSERT', 'OK', 'WAGE_MAPPING', v_mapping_id::text, jsonb_build_object('component_code', v_component_code), v_actor_user_id, null, null);
  return public.platform_json_response(true,'OK','ESIC wage component mapping saved.',jsonb_build_object('wage_component_mapping_id', v_mapping_id,'component_code', v_component_code));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_upsert_esic_wage_component_mapping.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_esic_sync_deduction_to_payroll_internal(
  p_schema_name text,
  p_tenant_id uuid,
  p_employee_id uuid,
  p_payroll_period date,
  p_batch_id bigint,
  p_source_record_id text,
  p_employee_contribution numeric,
  p_employer_contribution numeric
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_result jsonb;
  v_component jsonb;
begin
  for v_component in
    select *
    from jsonb_array_elements(jsonb_build_array(
      jsonb_build_object('component_code', 'ESIC_EMPLOYEE_SHARE', 'numeric_value', coalesce(p_employee_contribution, 0)),
      jsonb_build_object('component_code', 'ESIC_EMPLOYER_SHARE', 'numeric_value', coalesce(p_employer_contribution, 0))
    ))
  loop
    v_result := public.platform_upsert_payroll_input_entry(jsonb_build_object(
      'tenant_id', p_tenant_id,
      'employee_id', p_employee_id,
      'payroll_period', p_payroll_period,
      'component_code', v_component->>'component_code',
      'input_source', 'STATUTORY',
      'source_record_id', p_source_record_id,
      'source_batch_id', p_batch_id,
      'numeric_value', public.platform_esic_try_numeric(v_component->>'numeric_value'),
      'source_metadata', jsonb_build_object('module', 'ESIC', 'tenant_schema', p_schema_name, 'batch_id', p_batch_id),
      'input_status', 'VALIDATED'
    ));
    if coalesce((v_result->>'success')::boolean, false) is not true then
      return v_result;
    end if;
  end loop;

  return public.platform_json_response(true,'OK','ESIC deductions synced to payroll input.',jsonb_build_object('employee_id', p_employee_id,'payroll_period', p_payroll_period,'batch_id', p_batch_id));
end;
$function$;

create or replace function public.platform_esic_refresh_benefit_period_internal(
  p_schema_name text,
  p_employee_id uuid,
  p_payroll_period date,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_window jsonb := public.platform_esic_benefit_period_window(p_payroll_period);
  v_contribution_start date := public.platform_esic_try_date(v_window->>'contribution_period_start');
  v_contribution_end date := public.platform_esic_try_date(v_window->>'contribution_period_end');
  v_benefit_start date := public.platform_esic_try_date(v_window->>'benefit_period_start');
  v_benefit_end date := public.platform_esic_try_date(v_window->>'benefit_period_end');
  v_total_days numeric(10,2);
  v_total_wages numeric(14,2);
  v_benefit_period_id uuid;
begin
  execute format(
    'select coalesce(sum(worked_days), 0), coalesce(sum(eligible_wages), 0)
       from %I.wcm_esic_contribution_ledger
      where employee_id = $1
        and payroll_period between $2 and $3',
    p_schema_name
  ) into v_total_days, v_total_wages using p_employee_id, v_contribution_start, v_contribution_end;

  execute format(
    'insert into %I.wcm_esic_employee_benefit_period (employee_id, contribution_period_start, contribution_period_end, benefit_period_start, benefit_period_end, total_days_worked, total_wages_paid, minimum_days_required, is_eligible, eligibility_details, last_calculated_at, calculated_by_actor_user_id, calculation_version)
     values ($1,$2,$3,$4,$5,$6,$7,78,$8,$9,timezone(''utc'', now()),$10,''esic_v1'')
     on conflict (employee_id, contribution_period_start) do update
     set contribution_period_end = excluded.contribution_period_end,
         benefit_period_start = excluded.benefit_period_start,
         benefit_period_end = excluded.benefit_period_end,
         total_days_worked = excluded.total_days_worked,
         total_wages_paid = excluded.total_wages_paid,
         minimum_days_required = excluded.minimum_days_required,
         is_eligible = excluded.is_eligible,
         eligibility_details = excluded.eligibility_details,
         last_calculated_at = excluded.last_calculated_at,
         calculated_by_actor_user_id = excluded.calculated_by_actor_user_id,
         calculation_version = excluded.calculation_version,
         updated_at = timezone(''utc'', now())
     returning benefit_period_id',
    p_schema_name
  ) into v_benefit_period_id using
    p_employee_id,
    v_contribution_start,
    v_contribution_end,
    v_benefit_start,
    v_benefit_end,
    coalesce(v_total_days, 0),
    coalesce(v_total_wages, 0),
    coalesce(v_total_days, 0) >= 78 and coalesce(v_total_wages, 0) > 0,
    jsonb_build_object('total_days_worked', coalesce(v_totalDays, 0), 'total_wages_paid', coalesce(v_total_wages, 0), 'minimum_days_required', 78),
    p_actor_user_id;

  return public.platform_json_response(true,'OK','ESIC benefit period refreshed.',jsonb_build_object('benefit_period_id', v_benefit_period_id,'employee_id', p_employee_id));
end;
$function$;

create or replace function public.platform_request_esic_batch(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_esic_resolve_context(p_params);
  v_schema_name text;
  v_tenant_id uuid;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_establishment_id uuid := public.platform_try_uuid(p_params->>'establishment_id');
  v_period date := date_trunc('month', coalesce(public.platform_esic_try_date(p_params->>'payroll_period'), current_date)::timestamp)::date;
  v_batch record;
  v_establishment record;
  v_config_exists boolean := false;
  v_enqueue_result jsonb;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  if v_establishment_id is null then return public.platform_json_response(false,'ESTABLISHMENT_ID_REQUIRED','establishment_id is required.','{}'::jsonb); end if;

  execute format(
    'select establishment_id, state_code, establishment_status
       from %I.wcm_esic_establishment
      where establishment_id = $1',
    v_schema_name
  ) into v_establishment using v_establishment_id;

  if v_establishment.establishment_id is null then
    return public.platform_json_response(false,'ESTABLISHMENT_NOT_FOUND','ESIC establishment was not found.',jsonb_build_object('establishment_id', v_establishment_id));
  end if;

  if coalesce(v_establishment.establishment_status, '') <> 'ACTIVE' then
    return public.platform_json_response(false,'ESTABLISHMENT_NOT_ACTIVE','ESIC establishment must be ACTIVE before batch request.',jsonb_build_object('establishment_id', v_establishment_id,'establishment_status', v_establishment.establishment_status));
  end if;

  execute format(
    'select exists(
       select 1
         from %I.wcm_esic_configuration
        where state_code = $1
          and configuration_status = ''ACTIVE''
          and effective_from <= $2
          and (effective_to is null or effective_to >= $2)
     )',
    v_schema_name
  ) into v_config_exists using v_establishment.state_code, v_period;

  if coalesce(v_config_exists, false) is not true then
    return public.platform_json_response(false,'ACTIVE_CONFIGURATION_REQUIRED','No active ESIC configuration exists for the establishment state and payroll period.',jsonb_build_object('establishment_id', v_establishment_id,'state_code', v_establishment.state_code,'payroll_period', v_period));
  end if;

  execute format(
    'insert into %I.wcm_esic_processing_batch (establishment_id, payroll_period, return_period, batch_status, requested_by_actor_user_id)
     values ($1,$2,$3,''REQUESTED'',$4)
     on conflict (establishment_id, payroll_period) do update
     set requested_by_actor_user_id = excluded.requested_by_actor_user_id,
         updated_at = timezone(''utc'', now())
     returning batch_id, establishment_id, payroll_period, batch_status, return_period',
    v_schema_name
  ) into v_batch using v_establishment_id, v_period, to_char(v_period, 'MM/YYYY'), v_actor_user_id;

  v_enqueue_result := public.platform_async_enqueue_job(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'worker_code', 'esic_monthly_worker',
    'job_type', 'process_esic_batch',
    'priority', 70,
    'payload', jsonb_build_object('tenant_id', v_tenant_id, 'batch_id', v_batch.batch_id, 'establishment_id', v_establishment_id, 'payroll_period', v_period, 'actor_user_id', v_actor_user_id),
    'deduplication_key', format('esic:%s:%s:%s', v_tenant_id::text, v_establishment_id::text, v_period::text),
    'origin_source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_request_esic_batch'),
    'metadata', jsonb_build_object('slice', 'ESIC', 'reason', 'monthly_compute')
  ));
  if coalesce((v_enqueue_result->>'success')::boolean, false) is not true then return v_enqueue_result; end if;

  execute format('update %I.wcm_esic_processing_batch set worker_job_id = $2, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
    using v_batch.batch_id, public.platform_try_uuid(v_enqueue_result->'details'->>'job_id');

  perform public.platform_esic_append_audit(v_schema_name, 'BATCH_REQUEST', 'OK', 'BATCH', v_batch.batch_id::text, jsonb_build_object('payroll_period', v_period), v_actor_user_id, null, v_batch.batch_id);
  return public.platform_json_response(true,'OK','ESIC batch requested.',jsonb_build_object('batch_id', v_batch.batch_id,'payroll_period', v_period,'job_id', v_enqueue_result->'details'->>'job_id'));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_request_esic_batch.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
