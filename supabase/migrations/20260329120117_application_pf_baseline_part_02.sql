create or replace function public.platform_register_pf_establishment(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_establishment_id uuid;
  v_code text := lower(nullif(btrim(coalesce(p_params->>'establishment_code', '')), ''));
  v_name text := nullif(btrim(coalesce(p_params->>'establishment_name', '')), '');
  v_office text := upper(nullif(btrim(coalesce(p_params->>'pf_office_code', '')), ''));
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  if v_code is null then return public.platform_json_response(false,'ESTABLISHMENT_CODE_REQUIRED','establishment_code is required.','{}'::jsonb); end if;
  if v_name is null then return public.platform_json_response(false,'ESTABLISHMENT_NAME_REQUIRED','establishment_name is required.','{}'::jsonb); end if;
  if v_office is null then return public.platform_json_response(false,'PF_OFFICE_CODE_REQUIRED','pf_office_code is required.','{}'::jsonb); end if;

  execute format(
    'insert into %I.wcm_pf_establishment (establishment_code, establishment_name, legal_entity_name, pf_office_code, employer_pf_rate, employee_pf_rate, eps_rate, epf_rate, admin_charge_rate, edli_rate, wage_ceiling, calc_policy, establishment_status, created_by_actor_user_id, updated_by_actor_user_id)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$14)
     on conflict (establishment_code) do update
     set establishment_name = excluded.establishment_name,
         legal_entity_name = excluded.legal_entity_name,
         pf_office_code = excluded.pf_office_code,
         employer_pf_rate = excluded.employer_pf_rate,
         employee_pf_rate = excluded.employee_pf_rate,
         eps_rate = excluded.eps_rate,
         epf_rate = excluded.epf_rate,
         admin_charge_rate = excluded.admin_charge_rate,
         edli_rate = excluded.edli_rate,
         wage_ceiling = excluded.wage_ceiling,
         calc_policy = excluded.calc_policy,
         establishment_status = excluded.establishment_status,
         updated_by_actor_user_id = excluded.updated_by_actor_user_id,
         updated_at = timezone(''utc'', now())
     returning establishment_id',
    v_schema_name
  ) into v_establishment_id using
    v_code,
    v_name,
    nullif(btrim(p_params->>'legal_entity_name'), ''),
    v_office,
    coalesce(public.platform_pf_try_numeric(p_params->>'employer_pf_rate'), 12.00),
    coalesce(public.platform_pf_try_numeric(p_params->>'employee_pf_rate'), 12.00),
    coalesce(public.platform_pf_try_numeric(p_params->>'eps_rate'), 8.33),
    coalesce(public.platform_pf_try_numeric(p_params->>'epf_rate'), 3.67),
    coalesce(public.platform_pf_try_numeric(p_params->>'admin_charge_rate'), 0.50),
    coalesce(public.platform_pf_try_numeric(p_params->>'edli_rate'), 0.50),
    coalesce(public.platform_pf_try_numeric(p_params->>'wage_ceiling'), 15000.00),
    coalesce(p_params->'calc_policy', '{}'::jsonb),
    upper(coalesce(nullif(btrim(p_params->>'establishment_status'), ''), 'ACTIVE')),
    v_actor_user_id;

  perform public.platform_pf_append_audit(v_schema_name, 'ESTABLISHMENT_UPSERT', 'OK', 'ESTABLISHMENT', v_establishment_id::text, jsonb_build_object('establishment_code', v_code), v_actor_user_id, null, null);
  return public.platform_json_response(true,'OK','PF establishment registered.',jsonb_build_object('establishment_id', v_establishment_id,'establishment_code', v_code));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_pf_establishment.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_pf_employee_enrollment(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_establishment_id uuid := public.platform_try_uuid(p_params->>'establishment_id');
  v_effective_from date := coalesce(public.platform_pf_try_date(p_params->>'effective_from'), current_date);
  v_enrollment_id uuid;
  v_exists boolean := false;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_employee_id is null then return public.platform_json_response(false,'EMPLOYEE_ID_REQUIRED','employee_id is required.','{}'::jsonb); end if;
  if v_establishment_id is null then return public.platform_json_response(false,'ESTABLISHMENT_ID_REQUIRED','establishment_id is required.','{}'::jsonb); end if;

  execute format('select exists(select 1 from %I.wcm_employee where employee_id = $1)', v_schema_name) into v_exists using v_employee_id;
  if not coalesce(v_exists, false) then
    return public.platform_json_response(false,'EMPLOYEE_NOT_FOUND','employee_id was not found in tenant WCM truth.',jsonb_build_object('employee_id', v_employee_id));
  end if;

  execute format(
    'insert into %I.wcm_pf_employee_enrollment (employee_id, establishment_id, uan, pf_member_id, payroll_area_id, wage_basis_override, voluntary_pf_rate, eps_eligible, enrollment_status, effective_from, effective_to, exit_reason, enrollment_metadata, created_by_actor_user_id, updated_by_actor_user_id)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$14)
     on conflict (employee_id, establishment_id, effective_from) do update
     set uan = excluded.uan,
         pf_member_id = excluded.pf_member_id,
         payroll_area_id = excluded.payroll_area_id,
         wage_basis_override = excluded.wage_basis_override,
         voluntary_pf_rate = excluded.voluntary_pf_rate,
         eps_eligible = excluded.eps_eligible,
         enrollment_status = excluded.enrollment_status,
         effective_to = excluded.effective_to,
         exit_reason = excluded.exit_reason,
         enrollment_metadata = excluded.enrollment_metadata,
         updated_by_actor_user_id = excluded.updated_by_actor_user_id,
         updated_at = timezone(''utc'', now())
     returning enrollment_id',
    v_schema_name
  ) into v_enrollment_id using
    v_employee_id,
    v_establishment_id,
    nullif(btrim(p_params->>'uan'), ''),
    nullif(btrim(p_params->>'pf_member_id'), ''),
    public.platform_try_uuid(p_params->>'payroll_area_id'),
    public.platform_pf_try_numeric(p_params->>'wage_basis_override'),
    public.platform_pf_try_numeric(p_params->>'voluntary_pf_rate'),
    coalesce((p_params->>'eps_eligible')::boolean, true),
    upper(coalesce(nullif(btrim(p_params->>'enrollment_status'), ''), 'ACTIVE')),
    v_effective_from,
    public.platform_pf_try_date(p_params->>'effective_to'),
    nullif(btrim(p_params->>'exit_reason'), ''),
    coalesce(p_params->'enrollment_metadata', '{}'::jsonb),
    v_actor_user_id;

  perform public.platform_pf_append_audit(v_schema_name, 'ENROLLMENT_UPSERT', 'OK', 'ENROLLMENT', v_enrollment_id::text, jsonb_build_object('employee_id', v_employee_id,'establishment_id', v_establishment_id), v_actor_user_id, v_employee_id, null);
  return public.platform_json_response(true,'OK','PF employee enrollment registered.',jsonb_build_object('enrollment_id', v_enrollment_id,'employee_id', v_employee_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_pf_employee_enrollment.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_record_pf_arrear_case(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_establishment_id uuid := public.platform_try_uuid(p_params->>'establishment_id');
  v_arrear_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_employee_id is null then return public.platform_json_response(false,'EMPLOYEE_ID_REQUIRED','employee_id is required.','{}'::jsonb); end if;
  if v_establishment_id is null then return public.platform_json_response(false,'ESTABLISHMENT_ID_REQUIRED','establishment_id is required.','{}'::jsonb); end if;

  execute format(
    'insert into %I.wcm_pf_arrear_case (employee_id, establishment_id, effective_period, wage_delta, employee_share_delta, employer_share_delta, arrear_status, review_notes, reviewed_by_actor_user_id, arrear_metadata)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
     returning arrear_case_id',
    v_schema_name
  ) into v_arrear_id using
    v_employee_id,
    v_establishment_id,
    date_trunc('month', coalesce(public.platform_pf_try_date(p_params->>'effective_period'), current_date)::timestamp)::date,
    coalesce(public.platform_pf_try_numeric(p_params->>'wage_delta'), 0),
    public.platform_pf_try_numeric(p_params->>'employee_share_delta'),
    public.platform_pf_try_numeric(p_params->>'employer_share_delta'),
    upper(coalesce(nullif(btrim(p_params->>'arrear_status'), ''), 'PENDING_REVIEW')),
    nullif(btrim(p_params->>'review_notes'), ''),
    case when p_params ? 'reviewed_by_actor_user_id' then public.platform_try_uuid(p_params->>'reviewed_by_actor_user_id') else v_actor_user_id end,
    coalesce(p_params->'arrear_metadata', '{}'::jsonb);

  perform public.platform_pf_append_audit(v_schema_name, 'ARREAR_CASE_UPSERT', 'OK', 'ARREAR_CASE', v_arrear_id::text, jsonb_build_object('employee_id', v_employee_id), v_actor_user_id, v_employee_id, null);
  return public.platform_json_response(true,'OK','PF arrear case recorded.',jsonb_build_object('arrear_case_id', v_arrear_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_record_pf_arrear_case.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_process_pf_arrear_job(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_establishment_id uuid := public.platform_try_uuid(p_params->>'establishment_id');
  v_period date := date_trunc('month', coalesce(public.platform_pf_try_date(p_params->>'payroll_period'), current_date)::timestamp)::date;
  v_count integer;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_establishment_id is null then return public.platform_json_response(false,'ESTABLISHMENT_ID_REQUIRED','establishment_id is required.','{}'::jsonb); end if;

  execute format(
    'update %I.wcm_pf_arrear_case
        set arrear_status = ''READY_FOR_BATCH'',
            updated_at = timezone(''utc'', now())
      where establishment_id = $1
        and effective_period <= $2
        and arrear_status = ''APPROVED''',
    v_schema_name
  ) using v_establishment_id, v_period;
  get diagnostics v_count = row_count;

  perform public.platform_pf_append_audit(v_schema_name, 'ARREAR_JOB', 'OK', 'ESTABLISHMENT', v_establishment_id::text, jsonb_build_object('payroll_period', v_period,'updated_count', v_count), v_actor_user_id, null, null);
  return public.platform_json_response(true,'OK','PF arrear job processed.',jsonb_build_object('updated_cases', v_count,'payroll_period', v_period));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_process_pf_arrear_job.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_pf_sync_deduction_to_payroll_internal(
  p_schema_name text,
  p_tenant_id uuid,
  p_employee_id uuid,
  p_payroll_period date,
  p_batch_id bigint,
  p_source_record_id text,
  p_employee_share numeric,
  p_employer_share numeric,
  p_eps_share numeric,
  p_admin_charge numeric,
  p_edli_charge numeric
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_result jsonb;
  v_components jsonb := jsonb_build_array(
    jsonb_build_object('component_code', 'PF_EMPLOYEE_SHARE', 'numeric_value', coalesce(p_employee_share, 0)),
    jsonb_build_object('component_code', 'PF_EMPLOYER_SHARE', 'numeric_value', coalesce(p_employer_share, 0)),
    jsonb_build_object('component_code', 'PF_EPS_SHARE', 'numeric_value', coalesce(p_eps_share, 0)),
    jsonb_build_object('component_code', 'PF_ADMIN_CHARGE', 'numeric_value', coalesce(p_admin_charge, 0)),
    jsonb_build_object('component_code', 'PF_EDLI_CHARGE', 'numeric_value', coalesce(p_edli_charge, 0))
  );
  v_component jsonb;
begin
  for v_component in select * from jsonb_array_elements(v_components)
  loop
    v_result := public.platform_upsert_payroll_input_entry(jsonb_build_object(
      'tenant_id', p_tenant_id,
      'employee_id', p_employee_id,
      'payroll_period', p_payroll_period,
      'component_code', v_component->>'component_code',
      'input_source', 'STATUTORY',
      'source_record_id', p_source_record_id,
      'source_batch_id', p_batch_id,
      'numeric_value', public.platform_pf_try_numeric(v_component->>'numeric_value'),
      'source_metadata', jsonb_build_object('module', 'PF', 'tenant_schema', p_schema_name, 'batch_id', p_batch_id),
      'input_status', 'VALIDATED'
    ));
    if coalesce((v_result->>'success')::boolean, false) is not true then
      return v_result;
    end if;
  end loop;

  return public.platform_json_response(true,'OK','PF deductions synced to payroll input.',jsonb_build_object('employee_id', p_employee_id,'payroll_period', p_payroll_period,'batch_id', p_batch_id));
end;
$function$;;
