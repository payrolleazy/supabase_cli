create or replace function public.platform_record_ptax_arrear_case(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_ptax_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_arrear_case_id uuid;
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_state_code text := upper(nullif(btrim(coalesce(p_params->>'state_code', '')), ''));
  v_from_period date := date_trunc('month', public.platform_ptax_try_date(p_params->>'from_period')::timestamp)::date;
  v_to_period date := date_trunc('month', public.platform_ptax_try_date(p_params->>'to_period')::timestamp)::date;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  if v_employee_id is null then return public.platform_json_response(false,'EMPLOYEE_ID_REQUIRED','employee_id is required.','{}'::jsonb); end if;
  if v_state_code is null then return public.platform_json_response(false,'STATE_CODE_REQUIRED','state_code is required.','{}'::jsonb); end if;
  if v_from_period is null or v_to_period is null then return public.platform_json_response(false,'ARREAR_PERIOD_REQUIRED','from_period and to_period are required.','{}'::jsonb); end if;
  if v_to_period < v_from_period then return public.platform_json_response(false,'INVALID_PERIOD_RANGE','to_period cannot be earlier than from_period.','{}'::jsonb); end if;

  execute format(
    'insert into %I.wcm_ptax_arrear_case (employee_id, state_code, from_period, to_period, revised_state_code, override_amount, arrear_status, review_notes, target_payroll_period, case_metadata, created_by_actor_user_id, updated_by_actor_user_id)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$11)
     returning arrear_case_id',
    v_schema_name
  ) into v_arrear_case_id using
    v_employee_id,
    v_state_code,
    v_from_period,
    v_to_period,
    upper(nullif(btrim(p_params->>'revised_state_code'), '')),
    public.platform_ptax_try_numeric(p_params->>'override_amount'),
    upper(coalesce(nullif(btrim(p_params->>'arrear_status'), ''), 'PENDING_REVIEW')),
    nullif(btrim(p_params->>'review_notes'), ''),
    date_trunc('month', public.platform_ptax_try_date(p_params->>'target_payroll_period')::timestamp)::date,
    coalesce(p_params->'case_metadata', '{}'::jsonb),
    v_actor_user_id;

  perform public.platform_ptax_append_audit(v_schema_name, 'ARREAR_CASE_RECORDED', 'SUCCESS', 'wcm_ptax_arrear_case', v_arrear_case_id::text, jsonb_build_object('employee_id', v_employee_id, 'state_code', v_state_code), v_actor_user_id, v_employee_id);

  return public.platform_json_response(true,'OK','PTAX arrear case recorded.',jsonb_build_object('arrear_case_id', v_arrear_case_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_record_ptax_arrear_case.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_review_ptax_arrear(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_ptax_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_arrear_case_id uuid := public.platform_try_uuid(p_params->>'arrear_case_id');
  v_action text := upper(nullif(btrim(coalesce(p_params->>'action', '')), ''));
  v_status text;
  v_case record;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  if v_arrear_case_id is null then return public.platform_json_response(false,'ARREAR_CASE_ID_REQUIRED','arrear_case_id is required.','{}'::jsonb); end if;
  if v_action is null then return public.platform_json_response(false,'ACTION_REQUIRED','action is required.','{}'::jsonb); end if;

  v_status := case v_action when 'APPROVE' then 'APPROVED' when 'REJECT' then 'REJECTED' when 'CANCEL' then 'CANCELLED' else null end;
  if v_status is null then return public.platform_json_response(false,'ACTION_INVALID','action must be APPROVE, REJECT, or CANCEL.','{}'::jsonb); end if;

  execute format('select arrear_case_id, arrear_status from %I.wcm_ptax_arrear_case where arrear_case_id = $1', v_schema_name)
    into v_case using v_arrear_case_id;
  if v_case.arrear_case_id is null then return public.platform_json_response(false,'ARREAR_CASE_NOT_FOUND','PTAX arrear case was not found.',jsonb_build_object('arrear_case_id', v_arrear_case_id)); end if;

  if v_action in ('APPROVE','REJECT') and coalesce(v_case.arrear_status, '') <> 'PENDING_APPROVAL' then
    return public.platform_json_response(false,'ARREAR_CASE_NOT_READY','Only PENDING_APPROVAL PTAX arrear cases can be approved or rejected.',jsonb_build_object('arrear_case_id', v_arrear_case_id, 'arrear_status', v_case.arrear_status));
  end if;

  if v_action = 'CANCEL' and coalesce(v_case.arrear_status, '') not in ('PENDING_REVIEW','PENDING_APPROVAL','REJECTED','FAILED') then
    return public.platform_json_response(false,'ARREAR_CASE_NOT_READY','Only pending, failed, or rejected PTAX arrear cases can be cancelled.',jsonb_build_object('arrear_case_id', v_arrear_case_id, 'arrear_status', v_case.arrear_status));
  end if;

  execute format(
    'update %I.wcm_ptax_arrear_case
        set arrear_status = $2,
            override_amount = coalesce($3, override_amount),
            review_notes = coalesce($4, review_notes),
            target_payroll_period = coalesce($5, target_payroll_period),
            reviewed_by_actor_user_id = $6,
            updated_by_actor_user_id = $6,
            updated_at = timezone(''utc'', now())
      where arrear_case_id = $1',
    v_schema_name
  ) using v_arrear_case_id, v_status, public.platform_ptax_try_numeric(p_params->>'override_amount'), nullif(btrim(p_params->>'review_notes'), ''), date_trunc('month', public.platform_ptax_try_date(p_params->>'target_payroll_period')::timestamp)::date, v_actor_user_id;

  perform public.platform_ptax_append_audit(v_schema_name, 'ARREAR_CASE_REVIEWED', 'SUCCESS', 'wcm_ptax_arrear_case', v_arrear_case_id::text, jsonb_build_object('action', v_action, 'new_status', v_status), v_actor_user_id);
  return public.platform_json_response(true,'OK','PTAX arrear case reviewed.',jsonb_build_object('arrear_case_id', v_arrear_case_id, 'arrear_status', v_status));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_review_ptax_arrear.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_process_ptax_arrear_job(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_ptax_resolve_context(p_params);
  v_schema_name text;
  v_tenant_id uuid;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_arrear_case_id uuid := public.platform_try_uuid(p_params->>'arrear_case_id');
  v_case record;
  v_period_row record;
  v_original_state text;
  v_revised_state text;
  v_original_wages numeric;
  v_revised_wages numeric;
  v_original_config record;
  v_revised_config record;
  v_original_calc jsonb;
  v_revised_calc jsonb;
  v_original_deduction numeric := 0;
  v_revised_deduction numeric := 0;
  v_original_should_apply boolean := false;
  v_revised_should_apply boolean := false;
  v_delta numeric := 0;
  v_total_delta numeric := 0;
  v_source_key text;
  v_sync_result jsonb;
  v_target_payroll_period date;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');

  if v_arrear_case_id is null then
    return public.platform_json_response(false,'ARREAR_CASE_ID_REQUIRED','arrear_case_id is required.','{}'::jsonb);
  end if;

  execute format('select * from %I.wcm_ptax_arrear_case where arrear_case_id = $1', v_schema_name)
    into v_case using v_arrear_case_id;
  if v_case.arrear_case_id is null then
    return public.platform_json_response(false,'ARREAR_CASE_NOT_FOUND','PTAX arrear case was not found.',jsonb_build_object('arrear_case_id', v_arrear_case_id));
  end if;

  if v_case.arrear_status not in ('APPROVED','PENDING_REVIEW') then
    return public.platform_json_response(false,'ARREAR_CASE_NOT_READY','Only APPROVED or PENDING_REVIEW PTAX arrear cases can be processed.',jsonb_build_object('arrear_case_id', v_arrear_case_id, 'arrear_status', v_case.arrear_status));
  end if;

  execute format('delete from %I.wcm_ptax_arrear_computation where arrear_case_id = $1', v_schema_name)
    using v_arrear_case_id;

  for v_period_row in
    select generate_series(
      date_trunc('month', v_case.from_period::timestamp)::date,
      date_trunc('month', v_case.to_period::timestamp)::date,
      interval '1 month'
    )::date as payroll_period
  loop
    v_source_key := to_char(v_period_row.payroll_period, 'YYYY-MM');
    v_original_state := coalesce(public.platform_ptax_resolve_employee_state_internal(v_schema_name, v_case.employee_id, v_period_row.payroll_period), v_case.state_code);
    v_revised_state := coalesce(v_case.revised_state_code, v_original_state);
    v_original_wages := coalesce(public.platform_ptax_try_numeric(v_case.case_metadata->'original_wages_by_period'->>v_source_key), public.platform_ptax_get_employee_ptax_wages_internal(v_schema_name, v_case.employee_id, v_period_row.payroll_period, v_original_state));
    v_revised_wages := coalesce(public.platform_ptax_try_numeric(v_case.case_metadata->'revised_wages_by_period'->>v_source_key), v_original_wages);

    execute format(
      'select slabs, deduction_frequency, frequency_months
         from %I.wcm_ptax_configuration
        where state_code = $1
          and configuration_status = ''ACTIVE''
          and effective_from <= $2
          and (effective_to is null or effective_to >= $2)
        order by effective_from desc, configuration_version desc
        limit 1',
      v_schema_name
    ) into v_original_config using v_original_state, v_period_row.payroll_period;

    execute format(
      'select slabs, deduction_frequency, frequency_months
         from %I.wcm_ptax_configuration
        where state_code = $1
          and configuration_status = ''ACTIVE''
          and effective_from <= $2
          and (effective_to is null or effective_to >= $2)
        order by effective_from desc, configuration_version desc
        limit 1',
      v_schema_name
    ) into v_revised_config using v_revised_state, v_period_row.payroll_period;

    if v_original_config.slabs is null or v_revised_config.slabs is null then
      execute format(
        'update %I.wcm_ptax_arrear_case
            set arrear_status = ''FAILED'',
                review_notes = coalesce(review_notes, '''') || case when coalesce(review_notes, '''') = '''' then '''' else E''\n'' end || ''Configuration missing for one or more arrear periods.'',
                updated_by_actor_user_id = $2,
                updated_at = timezone(''utc'', now())
          where arrear_case_id = $1',
        v_schema_name
      ) using v_arrear_case_id, v_actor_user_id;

      return public.platform_json_response(false,'CONFIGURATION_NOT_FOUND','PTAX arrear computation requires active configuration for each affected period.',jsonb_build_object('arrear_case_id', v_arrear_case_id,'payroll_period', v_period_row.payroll_period,'original_state_code', v_original_state,'revised_state_code', v_revised_state));
    end if;

    v_original_calc := public.platform_ptax_calculate_from_slabs(v_original_wages, coalesce(v_original_config.slabs, '[]'::jsonb), v_period_row.payroll_period);
    v_revised_calc := public.platform_ptax_calculate_from_slabs(v_revised_wages, coalesce(v_revised_config.slabs, '[]'::jsonb), v_period_row.payroll_period);
    v_original_should_apply := public.platform_ptax_frequency_applies(v_original_config.deduction_frequency, v_original_config.frequency_months, v_period_row.payroll_period);
    v_revised_should_apply := public.platform_ptax_frequency_applies(v_revised_config.deduction_frequency, v_revised_config.frequency_months, v_period_row.payroll_period);
    v_original_deduction := case when v_original_should_apply then coalesce(public.platform_ptax_try_numeric(v_original_calc->>'deduction_amount'), 0) else 0 end;
    v_revised_deduction := case when v_revised_should_apply then coalesce(public.platform_ptax_try_numeric(v_revised_calc->>'deduction_amount'), 0) else 0 end;
    v_delta := round(v_revised_deduction - v_original_deduction, 2);
    v_total_delta := v_total_delta + v_delta;

    execute format(
      'insert into %I.wcm_ptax_arrear_computation (arrear_case_id, payroll_period, state_code, original_taxable_wages, revised_taxable_wages, original_deduction, revised_deduction, delta_deduction, computation_payload)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9)
       on conflict (arrear_case_id, payroll_period) do update
       set state_code = excluded.state_code,
           original_taxable_wages = excluded.original_taxable_wages,
           revised_taxable_wages = excluded.revised_taxable_wages,
           original_deduction = excluded.original_deduction,
           revised_deduction = excluded.revised_deduction,
           delta_deduction = excluded.delta_deduction,
           computation_payload = excluded.computation_payload,
           updated_at = timezone(''utc'', now())',
      v_schema_name
    ) using
      v_arrear_case_id,
      v_period_row.payroll_period,
      v_revised_state,
      round(coalesce(v_original_wages, 0), 2),
      round(coalesce(v_revised_wages, 0), 2),
      round(v_original_deduction, 2),
      round(v_revised_deduction, 2),
      v_delta,
      jsonb_build_object('original_state_code', v_original_state, 'revised_state_code', v_revised_state, 'original_slab', v_original_calc->'slab', 'revised_slab', v_revised_calc->'slab', 'original_frequency_applied', v_original_should_apply, 'revised_frequency_applied', v_revised_should_apply);
  end loop;

  v_target_payroll_period := coalesce(v_case.target_payroll_period, date_trunc('month', current_date::timestamp)::date);
  if v_case.arrear_status = 'APPROVED' then
    v_sync_result := public.platform_ptax_sync_deduction_to_payroll_internal(v_schema_name, v_tenant_id, v_case.employee_id, v_target_payroll_period, null, v_arrear_case_id::text, 0, coalesce(v_case.override_amount, v_total_delta));
    if coalesce((v_sync_result->>'success')::boolean, false) is not true then
      return v_sync_result;
    end if;
  end if;

  execute format(
    'update %I.wcm_ptax_arrear_case
        set arrear_status = case when arrear_status = ''APPROVED'' then ''PROCESSED'' else ''PENDING_APPROVAL'' end,
            target_payroll_period = $2,
            updated_by_actor_user_id = $3,
            updated_at = timezone(''utc'', now())
      where arrear_case_id = $1',
    v_schema_name
  ) using v_arrear_case_id, v_target_payroll_period, v_actor_user_id;

  perform public.platform_ptax_append_audit(v_schema_name, 'ARREAR_CASE_PROCESSED', 'SUCCESS', 'wcm_ptax_arrear_case', v_arrear_case_id::text, jsonb_build_object('total_delta', v_total_delta, 'target_payroll_period', v_target_payroll_period), v_actor_user_id, v_case.employee_id);

  return public.platform_json_response(true,'OK','PTAX arrear case processed.',jsonb_build_object('arrear_case_id', v_arrear_case_id, 'total_delta', coalesce(v_case.override_amount, v_total_delta), 'target_payroll_period', v_target_payroll_period));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_process_ptax_arrear_job.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
