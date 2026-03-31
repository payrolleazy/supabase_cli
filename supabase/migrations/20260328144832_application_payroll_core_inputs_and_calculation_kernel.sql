set search_path = public, pg_temp;

create or replace function public.platform_upsert_payroll_input_entry(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_payroll_period date := date_trunc('month', public.platform_payroll_core_try_date(p_params->>'payroll_period')::timestamp)::date;
  v_component_code text := upper(nullif(btrim(coalesce(p_params->>'component_code', '')), ''));
  v_input_source text := upper(coalesce(nullif(btrim(p_params->>'input_source'), ''), 'MANUAL'));
  v_source_record_id text := coalesce(p_params->>'source_record_id', '');
  v_source_batch_id bigint := public.platform_payroll_core_try_integer(p_params->>'source_batch_id');
  v_numeric_value numeric := public.platform_payroll_core_try_numeric(p_params->>'numeric_value');
  v_text_value text := p_params->>'text_value';
  v_json_value jsonb := p_params->'json_value';
  v_source_metadata jsonb := coalesce(p_params->'source_metadata', '{}'::jsonb);
  v_input_status text := upper(coalesce(nullif(btrim(p_params->>'input_status'), ''), 'VALIDATED'));
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_employee_id is null then return public.platform_json_response(false,'EMPLOYEE_ID_REQUIRED','employee_id is required.', '{}'::jsonb); end if;
  if v_payroll_period is null then return public.platform_json_response(false,'PAYROLL_PERIOD_REQUIRED','payroll_period is required.', '{}'::jsonb); end if;
  if v_component_code is null then return public.platform_json_response(false,'COMPONENT_CODE_REQUIRED','component_code is required.', '{}'::jsonb); end if;
  if jsonb_typeof(v_source_metadata) <> 'object' then return public.platform_json_response(false,'SOURCE_METADATA_INVALID','source_metadata must be a JSON object.', '{}'::jsonb); end if;

  perform public.platform_payroll_core_write_input_entry(v_schema_name, v_employee_id, v_payroll_period, v_component_code, v_input_source, v_source_record_id, v_source_batch_id, v_numeric_value, v_text_value, v_json_value, v_source_metadata, v_input_status);
  return public.platform_json_response(true,'OK','Payroll input entry upserted.',jsonb_build_object('employee_id', v_employee_id,'payroll_period', v_payroll_period,'component_code', v_component_code,'input_source', v_input_source));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_upsert_payroll_input_entry.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_payroll_core_sync_tps_inputs(
  p_schema_name text,
  p_employee_id uuid,
  p_payroll_period date,
  p_batch_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_summary record;
  v_source_record_id text;
begin
  execute format(
    'select s.batch_id,
            s.total_days_in_month,
            s.payable_days,
            s.lop_days,
            s.paid_leave_days,
            s.total_overtime_hours
       from %I.tps_employee_period_summary s
      where s.employee_id = $1
        and s.payroll_period = $2
        and s.is_stale = false
        and (case when $3 is null then true else s.batch_id = $3 end)
      order by s.batch_id desc
      limit 1',
    p_schema_name
  ) into v_summary using p_employee_id, p_payroll_period, p_batch_id;

  if v_summary.batch_id is null then
    return public.platform_json_response(false,'TPS_SUMMARY_NOT_FOUND','TPS summary was not found for the employee and payroll period.',jsonb_build_object('employee_id', p_employee_id,'payroll_period', p_payroll_period));
  end if;

  v_source_record_id := coalesce(v_summary.batch_id::text, '');
  perform public.platform_payroll_core_write_input_entry(p_schema_name, p_employee_id, p_payroll_period, 'TOTAL_DAYS_IN_MONTH', 'TPS', v_source_record_id, v_summary.batch_id, v_summary.total_days_in_month, null, null, jsonb_build_object('source_batch_id', v_summary.batch_id), 'VALIDATED');
  perform public.platform_payroll_core_write_input_entry(p_schema_name, p_employee_id, p_payroll_period, 'PAYABLE_DAYS', 'TPS', v_source_record_id, v_summary.batch_id, v_summary.payable_days, null, null, jsonb_build_object('source_batch_id', v_summary.batch_id), 'VALIDATED');
  perform public.platform_payroll_core_write_input_entry(p_schema_name, p_employee_id, p_payroll_period, 'LOP_DAYS', 'TPS', v_source_record_id, v_summary.batch_id, v_summary.lop_days, null, null, jsonb_build_object('source_batch_id', v_summary.batch_id), 'VALIDATED');
  perform public.platform_payroll_core_write_input_entry(p_schema_name, p_employee_id, p_payroll_period, 'PAID_LEAVE_DAYS', 'TPS', v_source_record_id, v_summary.batch_id, v_summary.paid_leave_days, null, null, jsonb_build_object('source_batch_id', v_summary.batch_id), 'VALIDATED');
  perform public.platform_payroll_core_write_input_entry(p_schema_name, p_employee_id, p_payroll_period, 'OVERTIME_HOURS', 'TPS', v_source_record_id, v_summary.batch_id, v_summary.total_overtime_hours, null, null, jsonb_build_object('source_batch_id', v_summary.batch_id), 'VALIDATED');

  return public.platform_json_response(true,'OK','TPS inputs synced into payroll input.',jsonb_build_object('employee_id', p_employee_id,'payroll_period', p_payroll_period,'source_batch_id', v_summary.batch_id));
end;
$function$;

create or replace function public.platform_payroll_core_input_map(
  p_schema_name text,
  p_employee_id uuid,
  p_payroll_period date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_input_map jsonb;
begin
  execute format(
    'with ranked as (
       select component_code,
              numeric_value,
              row_number() over (partition by component_code order by updated_at desc, payroll_input_entry_id desc) as rn
         from %I.wcm_payroll_input_entry
        where employee_id = $1
          and payroll_period = $2
          and input_status in (''VALIDATED'', ''APPLIED'')
     )
     select coalesce(jsonb_object_agg(component_code, coalesce(numeric_value, 0)), ''{}''::jsonb)
       from ranked
      where rn = 1',
    p_schema_name
  ) into v_input_map using p_employee_id, p_payroll_period;

  return coalesce(v_input_map, '{}'::jsonb);
end;
$function$;

create or replace function public.platform_payroll_core_result_snapshot(
  p_schema_name text,
  p_payroll_batch_id uuid,
  p_employee_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_components jsonb := '[]'::jsonb;
  v_gross numeric := 0;
  v_deductions numeric := 0;
  v_employer numeric := 0;
  v_net numeric := 0;
begin
  execute format(
    'select coalesce(jsonb_agg(jsonb_build_object(
        ''component_code'', component_code,
        ''component_name'', component_name,
        ''component_kind'', component_kind,
        ''calculation_method'', calculation_method,
        ''display_order'', display_order,
        ''calculated_amount'', calculated_amount,
        ''result_status'', result_status,
        ''source_lineage'', source_lineage
      ) order by display_order, component_code), ''[]''::jsonb),
      coalesce(sum(case when component_kind = ''EARNING'' then calculated_amount else 0 end), 0),
      coalesce(sum(case when component_kind = ''DEDUCTION'' then calculated_amount else 0 end), 0),
      coalesce(sum(case when component_kind = ''EMPLOYER_CONTRIBUTION'' then calculated_amount else 0 end), 0),
      coalesce(max(case when component_code = ''NET_PAY'' then calculated_amount end), 0)
       from %I.wcm_component_calculation_result
      where payroll_batch_id = $1
        and employee_id = $2',
    p_schema_name
  ) into v_components, v_gross, v_deductions, v_employer, v_net using p_payroll_batch_id, p_employee_id;

  if v_net = 0 then v_net := v_gross - v_deductions; end if;

  return jsonb_build_object(
    'components', coalesce(v_components, '[]'::jsonb),
    'gross_earnings', v_gross,
    'total_deductions', v_deductions,
    'employer_contributions', v_employer,
    'net_pay', v_net
  );
end;
$function$;

create or replace function public.platform_payroll_core_calculate_employee_batch(
  p_schema_name text,
  p_employee_id uuid,
  p_payroll_batch_id uuid,
  p_payroll_period date,
  p_override_inputs jsonb default '{}'::jsonb,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_sync_result jsonb;
  v_assignment record;
  v_components jsonb;
  v_component jsonb;
  v_input_map jsonb;
  v_results_map jsonb := '{}'::jsonb;
  v_requested_pay_structure_id uuid := public.platform_try_uuid(p_override_inputs->>'__preview_pay_structure_id');
  v_runtime_override_inputs jsonb := coalesce(p_override_inputs, '{}'::jsonb) - '__preview_pay_structure_id';
  v_payable_days numeric := 0;
  v_total_days numeric := 0;
  v_proration_factor numeric := 1;
  v_amount numeric := 0;
  v_component_code text;
  v_component_name text;
  v_component_kind text;
  v_calculation_method text;
  v_rule jsonb;
  v_display_order integer;
  v_base_component_code text;
  v_percentage numeric;
  v_derive_code text;
  v_gross numeric := 0;
  v_deductions numeric := 0;
  v_employer numeric := 0;
  v_result_status text := 'CALCULATED';
  v_current_payload jsonb;
begin
  v_sync_result := public.platform_payroll_core_sync_tps_inputs(p_schema_name, p_employee_id, p_payroll_period, null);
  if coalesce((v_sync_result->>'success')::boolean, false) is not true then return v_sync_result; end if;

  if v_requested_pay_structure_id is null then
    execute format(
      'select a.employee_pay_structure_assignment_id,
              a.pay_structure_id,
              a.pay_structure_version_id,
              a.override_inputs,
              psv.version_snapshot
         from %I.wcm_employee_pay_structure_assignment a
         join %I.wcm_pay_structure_version psv on psv.pay_structure_version_id = a.pay_structure_version_id
        where a.employee_id = $1
          and a.assignment_status = ''ACTIVE''
          and a.effective_from <= $2
          and (a.effective_to is null or a.effective_to >= $2)
        order by a.effective_from desc, a.created_at desc
        limit 1',
      p_schema_name,
      p_schema_name
    ) into v_assignment using p_employee_id, p_payroll_period;
  else
    execute format(
      'select a.employee_pay_structure_assignment_id,
              ps.pay_structure_id,
              psv.pay_structure_version_id,
              coalesce(a.override_inputs, ''{}''::jsonb) as override_inputs,
              psv.version_snapshot
         from %I.wcm_pay_structure ps
         join %I.wcm_pay_structure_version psv
           on psv.pay_structure_id = ps.pay_structure_id
          and psv.version_status = ''ACTIVE''
         left join %I.wcm_employee_pay_structure_assignment a
           on a.employee_id = $1
          and a.pay_structure_id = ps.pay_structure_id
          and a.assignment_status = ''ACTIVE''
          and a.effective_from <= $2
          and (a.effective_to is null or a.effective_to >= $2)
        where ps.pay_structure_id = $3
          and ps.structure_status = ''ACTIVE''
        order by a.effective_from desc nulls last, a.created_at desc nulls last
        limit 1',
      p_schema_name,
      p_schema_name,
      p_schema_name
    ) into v_assignment using p_employee_id, p_payroll_period, v_requested_pay_structure_id;
  end if;

  if v_assignment.pay_structure_id is null then
    if v_requested_pay_structure_id is null then
      return public.platform_json_response(false,'PAY_STRUCTURE_ASSIGNMENT_NOT_FOUND','No active pay-structure assignment exists for payroll calculation.',jsonb_build_object('employee_id', p_employee_id,'payroll_period', p_payroll_period));
    end if;
    return public.platform_json_response(false,'PAY_STRUCTURE_NOT_FOUND','Requested pay structure was not found or is not active for preview.',jsonb_build_object('employee_id', p_employee_id,'payroll_period', p_payroll_period,'pay_structure_id', v_requested_pay_structure_id));
  end if;

  v_components := coalesce(v_assignment.version_snapshot->'components', '[]'::jsonb);
  v_input_map := public.platform_payroll_core_input_map(p_schema_name, p_employee_id, p_payroll_period)
                 || coalesce(v_assignment.override_inputs, '{}'::jsonb)
                 || v_runtime_override_inputs;

  v_payable_days := coalesce((v_input_map->>'PAYABLE_DAYS')::numeric, 0);
  v_total_days := coalesce((v_input_map->>'TOTAL_DAYS_IN_MONTH')::numeric, 0);
  if v_total_days > 0 then v_proration_factor := greatest(0, least(1, v_payable_days / v_total_days)); end if;

  execute format('delete from %I.wcm_component_calculation_result where payroll_batch_id = $1 and employee_id = $2', p_schema_name) using p_payroll_batch_id, p_employee_id;

  for v_component in
    select value
    from jsonb_array_elements(v_components)
    order by coalesce((value->>'display_order')::integer, 100), value->>'component_code'
  loop
    v_component_code := upper(coalesce(v_component->>'component_code', ''));
    v_component_name := coalesce(v_component->>'component_name', v_component_code);
    v_component_kind := upper(coalesce(v_component->>'component_kind', 'INFO'));
    v_calculation_method := upper(coalesce(v_component->>'calculation_method', 'INPUT'));
    v_rule := coalesce(v_component->'rule_definition', '{}'::jsonb);
    v_display_order := coalesce((v_component->>'display_order')::integer, 100);
    v_amount := 0;
    v_result_status := case when v_runtime_override_inputs <> '{}'::jsonb or v_requested_pay_structure_id is not null then 'PREVIEW' else 'CALCULATED' end;

    if v_calculation_method = 'FIXED' then
      v_amount := coalesce((v_rule->>'fixed_amount')::numeric, 0);
      if lower(coalesce(v_rule->>'proration_mode', '')) = 'payable_days_fraction' then
        v_amount := round(v_amount * v_proration_factor, 2);
      end if;
    elsif v_calculation_method = 'INPUT' then
      v_base_component_code := upper(coalesce(nullif(v_rule->>'source_component_code', ''), v_component_code));
      v_amount := coalesce((v_input_map->>v_base_component_code)::numeric, 0);
    elsif v_calculation_method = 'PERCENTAGE' then
      v_base_component_code := upper(coalesce(v_rule->>'base_component_code', ''));
      v_percentage := coalesce((v_rule->>'percentage')::numeric, 0);
      if v_base_component_code = '' then
        return public.platform_json_response(false,'BASE_COMPONENT_REQUIRED','percentage components require base_component_code.',jsonb_build_object('component_code', v_component_code));
      end if;
      v_amount := round(coalesce((v_results_map->>v_base_component_code)::numeric, 0) * v_percentage / 100.0, 2);
    else
      v_derive_code := lower(coalesce(v_rule->>'derive_code', v_rule->>'formula_code', ''));
      if v_derive_code = 'gross_earnings' then
        v_amount := v_gross;
      elsif v_derive_code = 'total_deductions' then
        v_amount := v_deductions;
      elsif v_derive_code = 'net_pay' then
        v_amount := v_gross - v_deductions;
      elsif v_derive_code = 'ctc' then
        v_amount := v_gross + v_employer;
      else
        return public.platform_json_response(false,'UNSUPPORTED_COMPONENT_METHOD','Unsupported calculation method for the first payroll slice.',jsonb_build_object('component_code', v_component_code,'calculation_method', v_calculation_method,'derive_code', v_derive_code));
      end if;
    end if;

    if v_component_kind = 'EARNING' then
      v_gross := v_gross + v_amount;
    elsif v_component_kind = 'DEDUCTION' then
      v_deductions := v_deductions + v_amount;
    elsif v_component_kind = 'EMPLOYER_CONTRIBUTION' then
      v_employer := v_employer + v_amount;
    end if;

    v_results_map := v_results_map || jsonb_build_object(v_component_code, v_amount);
    v_current_payload := jsonb_build_object('input_map', v_input_map, 'rule_definition', v_rule, 'proration_factor', v_proration_factor, 'preview_pay_structure_id', v_requested_pay_structure_id);

    execute format('insert into %I.wcm_component_calculation_result (payroll_batch_id, employee_id, payroll_period, component_id, component_code, component_name, component_kind, calculation_method, display_order, calculated_amount, result_status, source_lineage) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)', p_schema_name)
      using p_payroll_batch_id, p_employee_id, p_payroll_period, (v_component->>'component_id')::bigint, v_component_code, v_component_name, v_component_kind, v_calculation_method, v_display_order, v_amount, v_result_status, v_current_payload;
  end loop;

  return public.platform_json_response(true,'OK','Employee payroll calculated.',jsonb_build_object('employee_id', p_employee_id,'payroll_period', p_payroll_period,'gross_earnings', v_gross,'total_deductions', v_deductions,'employer_contributions', v_employer,'net_pay', v_gross - v_deductions));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_payroll_core_calculate_employee_batch.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm,'employee_id', p_employee_id,'payroll_period', p_payroll_period));
end;
$function$;;
