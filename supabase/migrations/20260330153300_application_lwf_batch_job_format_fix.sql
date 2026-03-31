
create or replace function public.platform_process_lwf_batch_job(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context(p_params);
  v_schema_name text;
  v_tenant_id uuid;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_batch_id bigint := nullif(p_params->>'batch_id', '')::bigint;
  v_batch record;
  v_employee_id uuid;
  v_requested_count integer := 0;
  v_processed_count integer := 0;
  v_synced_count integer := 0;
  v_error_count integer := 0;
  v_calc_result jsonb;
  v_details jsonb;
  v_ledger_id uuid;
  v_sync_result jsonb;
  v_final_employee numeric;
  v_final_employer numeric;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  if v_batch_id is null then return public.platform_json_response(false,'BATCH_ID_REQUIRED','batch_id is required.','{}'::jsonb); end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');

  execute format('select * from %I.wcm_lwf_processing_batch where batch_id = $1', v_schema_name) into v_batch using v_batch_id;
  if v_batch.batch_id is null then
    return public.platform_json_response(false,'BATCH_NOT_FOUND','LWF batch was not found.',jsonb_build_object('batch_id', v_batch_id));
  end if;
  if v_batch.batch_status not in ('REQUESTED','FAILED') then
    return public.platform_json_response(false,'BATCH_NOT_PROCESSABLE','Only REQUESTED or FAILED batches can be processed.',jsonb_build_object('batch_id', v_batch_id, 'batch_status', v_batch.batch_status));
  end if;

  execute format('update %I.wcm_lwf_processing_batch set batch_status = ''PROCESSING'', process_started_at = timezone(''utc'', now()), process_completed_at = null, error_payload = ''{}''::jsonb, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
    using v_batch_id;

  if jsonb_array_length(coalesce(v_batch.requested_employee_ids, '[]'::jsonb)) > 0 then
    for v_employee_id in
      select public.platform_try_uuid(value)
      from jsonb_array_elements_text(v_batch.requested_employee_ids)
    loop
      continue when v_employee_id is null;
      v_requested_count := v_requested_count + 1;
      v_calc_result := public.platform_lwf_calculate_contribution_internal(v_schema_name, v_employee_id, v_batch.payroll_period, v_batch.batch_source = 'FNF');
      if coalesce((v_calc_result->>'success')::boolean, false) is not true then
        v_error_count := v_error_count + 1;
        execute format(
          'insert into %I.wcm_lwf_dead_letter_entry (batch_id, employee_id, error_code, error_message, payload)
           values ($1,$2,$3,$4,$5)',
          v_schema_name
        ) using v_batch_id, v_employee_id, coalesce(v_calc_result->>'code', 'CALCULATION_FAILED'), coalesce(v_calc_result->>'message', 'LWF calculation failed.'), coalesce(v_calc_result->'details', '{}'::jsonb);
        continue;
      end if;

      v_details := coalesce(v_calc_result->'details', '{}'::jsonb);
      if coalesce(v_details->>'state_code', '') <> v_batch.state_code then
        v_error_count := v_error_count + 1;
        execute format(
          'insert into %I.wcm_lwf_dead_letter_entry (batch_id, employee_id, error_code, error_message, payload)
           values ($1,$2,''STATE_MISMATCH'',''Resolved state did not match the requested batch state.'',$3)',
          v_schema_name
        ) using v_batch_id, v_employee_id, v_details;
        continue;
      end if;

      execute format(
        'insert into %I.wcm_lwf_period_ledger (
           batch_id, employee_id, payroll_period, state_code, eligible_wages,
           system_employee_contribution, system_employer_contribution,
           final_employee_contribution, final_employer_contribution,
           override_status, sync_status, calculation_payload, sync_payload, ledger_metadata
         ) values (
           $1,$2,$3,$4,$5,$6,$7,$6,$7,''NONE'',''PENDING'',$8,''{}''::jsonb,jsonb_build_object(''batch_source'', $9))
         on conflict (employee_id, payroll_period, batch_id) do update
           set state_code = excluded.state_code,
               eligible_wages = excluded.eligible_wages,
               system_employee_contribution = excluded.system_employee_contribution,
               system_employer_contribution = excluded.system_employer_contribution,
               final_employee_contribution = case when %I.wcm_lwf_period_ledger.override_status = ''MANUAL'' then %I.wcm_lwf_period_ledger.final_employee_contribution else excluded.final_employee_contribution end,
               final_employer_contribution = case when %I.wcm_lwf_period_ledger.override_status = ''MANUAL'' then %I.wcm_lwf_period_ledger.final_employer_contribution else excluded.final_employer_contribution end,
               calculation_payload = excluded.calculation_payload,
               ledger_metadata = excluded.ledger_metadata,
               updated_at = timezone(''utc'', now())
         returning contribution_ledger_id, final_employee_contribution, final_employer_contribution',
        v_schema_name, v_schema_name, v_schema_name, v_schema_name, v_schema_name
      ) into v_ledger_id, v_final_employee, v_final_employer using
        v_batch_id,
        v_employee_id,
        v_batch.payroll_period,
        v_batch.state_code,
        round(coalesce(public.platform_lwf_try_numeric(v_details->>'eligible_wages'), 0), 2),
        round(coalesce(public.platform_lwf_try_numeric(v_details->>'employee_contribution'), 0), 2),
        round(coalesce(public.platform_lwf_try_numeric(v_details->>'employer_contribution'), 0), 2),
        v_details,
        v_batch.batch_source;

      v_sync_result := public.platform_lwf_sync_to_payroll_internal(v_schema_name, v_tenant_id, v_employee_id, v_batch.payroll_period, v_batch_id, v_ledger_id::text, v_final_employee, v_final_employer);
      if coalesce((v_sync_result->>'success')::boolean, false) is not true then
        v_error_count := v_error_count + 1;
        execute format(
          'update %I.wcm_lwf_period_ledger
              set sync_status = ''ERROR'',
                  sync_payload = $2,
                  updated_at = timezone(''utc'', now())
            where contribution_ledger_id = $1',
          v_schema_name
        ) using v_ledger_id, coalesce(v_sync_result->'details', '{}'::jsonb);
        execute format(
          'insert into %I.wcm_lwf_dead_letter_entry (batch_id, employee_id, error_code, error_message, payload)
           values ($1,$2,''PAYROLL_SYNC_FAILED'',''LWF payroll sync failed.'',$3)',
          v_schema_name
        ) using v_batch_id, v_employee_id, coalesce(v_sync_result->'details', '{}'::jsonb);
        continue;
      end if;

      execute format(
        'update %I.wcm_lwf_period_ledger
            set sync_status = ''SYNCED'',
                sync_payload = $2,
                updated_at = timezone(''utc'', now())
          where contribution_ledger_id = $1',
        v_schema_name
      ) using v_ledger_id, coalesce(v_sync_result->'details', '{}'::jsonb);

      v_processed_count := v_processed_count + 1;
      v_synced_count := v_synced_count + 1;
    end loop;
  end if;

  execute format(
    'update %I.wcm_lwf_processing_batch
        set batch_status = $2,
            process_completed_at = timezone(''utc'', now()),
            summary_payload = jsonb_build_object(''requested_count'', $3, ''processed_count'', $4, ''synced_count'', $5, ''error_count'', $6),
            error_payload = case when $6 > 0 then jsonb_build_object(''error_count'', $6) else ''{}''::jsonb end,
            updated_at = timezone(''utc'', now())
      where batch_id = $1',
    v_schema_name
  ) using v_batch_id, case when v_error_count > 0 then 'FAILED' else 'SYNCED' end, v_requested_count, v_processed_count, v_synced_count, v_error_count;

  perform public.platform_refresh_lwf_compliance_summary_internal(v_schema_name, v_batch.payroll_period, v_batch.state_code);
  perform public.platform_lwf_append_audit(v_schema_name, 'BATCH_PROCESSED', case when v_error_count > 0 then 'PARTIAL_FAILURE' else 'SUCCESS' end, 'wcm_lwf_processing_batch', v_batch_id::text, jsonb_build_object('requested_count', v_requested_count, 'processed_count', v_processed_count, 'synced_count', v_synced_count, 'error_count', v_error_count), v_actor_user_id, null, v_batch_id);

  return public.platform_json_response(true,'OK','LWF batch processed.',jsonb_build_object('batch_id', v_batch_id, 'processed_count', v_processed_count, 'synced_count', v_synced_count, 'error_count', v_error_count, 'batch_status', case when v_error_count > 0 then 'FAILED' else 'SYNCED' end));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_process_lwf_batch_job.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm,'batch_id', v_batch_id));
end;
$function$;



;
