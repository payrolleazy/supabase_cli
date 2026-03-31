create or replace function public.platform_process_payroll_batch_job(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_tenant_id uuid;
  v_payroll_batch_id uuid := public.platform_try_uuid(p_params->>'payroll_batch_id');
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_batch record;
  v_employee_id uuid;
  v_override_inputs jsonb := '{}'::jsonb;
  v_result jsonb;
  v_processed integer := 0;
  v_failed integer := 0;
  v_total integer := 0;
  v_summary jsonb := '{}'::jsonb;
  v_preview_id uuid;
  v_preview_pay_structure_id uuid;
  v_has_employee_filter boolean;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  if v_payroll_batch_id is null then return public.platform_json_response(false,'PAYROLL_BATCH_ID_REQUIRED','payroll_batch_id is required.', '{}'::jsonb); end if;

  execute format('select payroll_batch_id, payroll_period, payroll_area_id, processing_type, batch_status, request_scope from %I.wcm_payroll_batch where payroll_batch_id = $1 for update', v_schema_name)
    into v_batch using v_payroll_batch_id;
  if v_batch.payroll_batch_id is null then return public.platform_json_response(false,'PAYROLL_BATCH_NOT_FOUND','Payroll batch not found.',jsonb_build_object('payroll_batch_id', v_payroll_batch_id)); end if;
  if v_batch.batch_status not in ('PROCESSING', 'FAILED') then return public.platform_json_response(false,'PAYROLL_BATCH_NOT_PROCESSABLE','Payroll batch must be PROCESSING or FAILED before worker execution.',jsonb_build_object('payroll_batch_id', v_payroll_batch_id,'batch_status', v_batch.batch_status)); end if;

  execute format('delete from %I.wcm_component_calculation_result where payroll_batch_id = $1', v_schema_name) using v_payroll_batch_id;

  if v_batch.processing_type = 'PREVIEW_SIMULATION' then
    v_preview_id := public.platform_try_uuid(v_batch.request_scope->>'preview_simulation_id');
    execute format('select employee_id, pay_structure_id, request_payload from %I.wcm_preview_simulation where preview_simulation_id = $1', v_schema_name) into v_employee_id, v_preview_pay_structure_id, v_summary using v_preview_id;
    v_override_inputs := coalesce(v_summary->'override_inputs', '{}'::jsonb);
    if v_preview_pay_structure_id is not null then
      v_override_inputs := v_override_inputs || jsonb_build_object('__preview_pay_structure_id', v_preview_pay_structure_id::text);
    end if;
    v_result := public.platform_payroll_core_calculate_employee_batch(v_schema_name, v_employee_id, v_payroll_batch_id, v_batch.payroll_period, v_override_inputs, v_actor_user_id);
    if coalesce((v_result->>'success')::boolean, false) is not true then
      execute format('update %I.wcm_payroll_batch set batch_status = ''FAILED'', failed_employees = 1, last_error = $2, updated_at = timezone(''utc'', now()) where payroll_batch_id = $1', v_schema_name) using v_payroll_batch_id, v_result::text;
      execute format('update %I.wcm_preview_simulation set preview_status = ''FAILED'', result_snapshot = $2, updated_at = timezone(''utc'', now()) where preview_simulation_id = $1', v_schema_name) using v_preview_id, jsonb_build_object('error', v_result);
      return v_result;
    end if;
    v_processed := 1;
    v_total := 1;
    execute format('update %I.wcm_preview_simulation set preview_status = ''COMPLETED'', result_snapshot = $2, completed_at = timezone(''utc'', now()), updated_at = timezone(''utc'', now()) where preview_simulation_id = $1', v_schema_name) using v_preview_id, public.platform_payroll_core_result_snapshot(v_schema_name, v_payroll_batch_id, v_employee_id);
  else
    v_has_employee_filter := coalesce(jsonb_typeof(v_batch.request_scope->'employee_ids') = 'array', false) and jsonb_array_length(v_batch.request_scope->'employee_ids') > 0;
    for v_employee_id in execute format(
      'select distinct s.employee_id
         from %I.tps_employee_period_summary s
         join %I.wcm_employee_pay_structure_assignment a
           on a.employee_id = s.employee_id
          and a.assignment_status = ''ACTIVE''
          and a.effective_from <= $1
          and (a.effective_to is null or a.effective_to >= $1)
         join %I.wcm_pay_structure ps
           on ps.pay_structure_id = a.pay_structure_id
          and ps.payroll_area_id = $4
        where s.payroll_period = $1
          and s.is_stale = false
          and (not $2 or s.employee_id in (select public.platform_try_uuid(e.value) from jsonb_array_elements_text($3->''employee_ids'') as e(value)))
        order by s.employee_id',
      v_schema_name,
      v_schema_name,
      v_schema_name
    ) using v_batch.payroll_period, v_has_employee_filter, v_batch.request_scope, v_batch.payroll_area_id
    loop
      v_total := v_total + 1;
      v_result := public.platform_payroll_core_calculate_employee_batch(v_schema_name, v_employee_id, v_payroll_batch_id, v_batch.payroll_period, '{}'::jsonb, v_actor_user_id);
      if coalesce((v_result->>'success')::boolean, false) is not true then
        v_failed := v_failed + 1;
      else
        v_processed := v_processed + 1;
      end if;
    end loop;
  end if;

  v_summary := jsonb_build_object(
    'gross_earnings', coalesce((select sum(gross_earnings) from public.platform_rm_payroll_result_summary where payroll_batch_id = v_payroll_batch_id), 0),
    'total_deductions', coalesce((select sum(total_deductions) from public.platform_rm_payroll_result_summary where payroll_batch_id = v_payroll_batch_id), 0),
    'employer_contributions', coalesce((select sum(employer_contributions) from public.platform_rm_payroll_result_summary where payroll_batch_id = v_payroll_batch_id), 0),
    'net_pay', coalesce((select sum(net_pay) from public.platform_rm_payroll_result_summary where payroll_batch_id = v_payroll_batch_id), 0),
    'tenant_id', v_tenant_id
  );

  execute format('update %I.wcm_payroll_batch set batch_status = case when $2 > 0 then ''FAILED'' else ''PROCESSED'' end, total_employees = $1, processed_employees = $3, failed_employees = $2, summary_metrics = $4, processed_by_actor_user_id = $5, processed_at = timezone(''utc'', now()), updated_at = timezone(''utc'', now()) where payroll_batch_id = $6', v_schema_name)
    using v_total, v_failed, v_processed, v_summary, v_actor_user_id, v_payroll_batch_id;

  return public.platform_json_response(true,'OK','Payroll batch processed.',jsonb_build_object('payroll_batch_id', v_payroll_batch_id,'total_employees', v_total,'processed_employees', v_processed,'failed_employees', v_failed,'batch_status', case when v_failed > 0 then 'FAILED' else 'PROCESSED' end));
exception when others then
  if v_schema_name is not null and v_payroll_batch_id is not null then
    execute format('update %I.wcm_payroll_batch set batch_status = ''FAILED'', last_error = $2, updated_at = timezone(''utc'', now()) where payroll_batch_id = $1', v_schema_name) using v_payroll_batch_id, sqlerrm;
  end if;
  if v_schema_name is not null and v_preview_id is not null then
    execute format('update %I.wcm_preview_simulation set preview_status = ''FAILED'', result_snapshot = jsonb_build_object(''error'', $2), updated_at = timezone(''utc'', now()) where preview_simulation_id = $1', v_schema_name) using v_preview_id, sqlerrm;
  end if;
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_process_payroll_batch_job.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
