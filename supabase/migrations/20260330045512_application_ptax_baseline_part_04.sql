create or replace function public.platform_process_ptax_batch_job(p_params jsonb)
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
  v_batch_id bigint := nullif(p_params->>'batch_id', '')::bigint;
  v_batch record;
  v_config record;
  v_row record;
  v_ledger_id uuid;
  v_calc jsonb;
  v_sync_result jsonb;
  v_taxable_wages numeric;
  v_deduction numeric;
  v_processed integer := 0;
  v_synced integer := 0;
  v_skipped integer := 0;
  v_errors integer := 0;
  v_should_apply boolean;
  v_frequency_month integer := extract(month from current_date)::integer;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');

  if v_batch_id is null then
    return public.platform_json_response(false,'BATCH_ID_REQUIRED','batch_id is required.','{}'::jsonb);
  end if;

  execute format('select * from %I.wcm_ptax_processing_batch where batch_id = $1', v_schema_name)
    into v_batch using v_batch_id;
  if v_batch.batch_id is null then
    return public.platform_json_response(false,'BATCH_NOT_FOUND','PTAX batch was not found.',jsonb_build_object('batch_id', v_batch_id));
  end if;

  if v_batch.batch_status not in ('REQUESTED','FAILED') then
    return public.platform_json_response(false,'BATCH_NOT_READY','Only REQUESTED or FAILED PTAX batches can be processed.',jsonb_build_object('batch_id', v_batch_id, 'batch_status', v_batch.batch_status));
  end if;

  execute format(
    'select configuration_id, slabs, deduction_frequency, frequency_months
       from %I.wcm_ptax_configuration
      where state_code = $1
        and configuration_status = ''ACTIVE''
        and effective_from <= $2
        and (effective_to is null or effective_to >= $2)
      order by effective_from desc, configuration_version desc
      limit 1',
    v_schema_name
  ) into v_config using v_batch.state_code, v_batch.payroll_period;

  if v_config.configuration_id is null then
    execute format('update %I.wcm_ptax_processing_batch set batch_status = ''FAILED'', error_payload = $2, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
      using v_batch_id, jsonb_build_object('code', 'CONFIGURATION_NOT_FOUND', 'state_code', v_batch.state_code, 'payroll_period', v_batch.payroll_period);
    return public.platform_json_response(false,'CONFIGURATION_NOT_FOUND','No active PTAX configuration exists for this batch.',jsonb_build_object('batch_id', v_batch_id));
  end if;

  execute format('update %I.wcm_ptax_processing_batch set batch_status = ''PROCESSING'', process_started_at = timezone(''utc'', now()), process_completed_at = null, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
    using v_batch_id;

  v_frequency_month := extract(month from v_batch.payroll_period)::integer;

  for v_row in execute format(
    'select e.employee_id
       from %I.wcm_employee e
       join %I.wcm_employee_service_state s on s.employee_id = e.employee_id
      where s.service_state = ''active''
        and exists (
          select 1
            from %I.wcm_ptax_employee_state_profile p
           where p.employee_id = e.employee_id
             and p.state_code = $1
             and p.profile_status = ''ACTIVE''
             and p.effective_from <= $2
             and (p.effective_to is null or p.effective_to >= $2)
        )
        and (jsonb_array_length($3) = 0 or e.employee_id in (select value::uuid from jsonb_array_elements_text($3) as value))
      order by e.employee_code',
    v_schema_name, v_schema_name, v_schema_name
  ) using v_batch.state_code, v_batch.payroll_period, coalesce(v_batch.requested_employee_ids, '[]'::jsonb)
  loop
    v_taxable_wages := public.platform_ptax_get_employee_ptax_wages_internal(v_schema_name, v_row.employee_id, v_batch.payroll_period, v_batch.state_code);
    v_calc := public.platform_ptax_calculate_from_slabs(v_taxable_wages, v_config.slabs, v_batch.payroll_period);

    v_should_apply := public.platform_ptax_frequency_applies(v_config.deduction_frequency, v_config.frequency_months, v_batch.payroll_period);

    v_deduction := case when v_should_apply then coalesce(public.platform_ptax_try_numeric(v_calc->>'deduction_amount'), 0) else 0 end;

    execute format(
      'insert into %I.wcm_ptax_monthly_ledger (batch_id, employee_id, payroll_period, state_code, deduction_frequency, taxable_wages, deduction_amount, sync_status, slab_details, sync_payload, ledger_metadata)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       on conflict (employee_id, payroll_period, batch_id) do update
       set state_code = excluded.state_code,
           deduction_frequency = excluded.deduction_frequency,
           taxable_wages = excluded.taxable_wages,
           deduction_amount = excluded.deduction_amount,
           sync_status = excluded.sync_status,
           slab_details = excluded.slab_details,
           sync_payload = excluded.sync_payload,
           ledger_metadata = excluded.ledger_metadata,
           updated_at = timezone(''utc'', now())
       returning contribution_ledger_id',
      v_schema_name
    ) into v_ledger_id using
      v_batch_id,
      v_row.employee_id,
      v_batch.payroll_period,
      v_batch.state_code,
      upper(v_config.deduction_frequency),
      coalesce(v_taxable_wages, 0),
      round(coalesce(v_deduction, 0), 2),
      case when coalesce(v_deduction, 0) > 0 then 'PENDING' else 'SKIPPED' end,
      coalesce(v_calc->'slab', '{}'::jsonb),
      '{}'::jsonb,
      jsonb_build_object('frequency_applied', v_should_apply, 'matched', coalesce((v_calc->>'matched')::boolean, false));

    if coalesce(v_deduction, 0) > 0 then
      v_sync_result := public.platform_ptax_sync_deduction_to_payroll_internal(v_schema_name, v_tenant_id, v_row.employee_id, v_batch.payroll_period, v_batch_id, v_ledger_id::text, v_deduction, 0);
      if coalesce((v_sync_result->>'success')::boolean, false) is not true then
        execute format('update %I.wcm_ptax_monthly_ledger set sync_status = ''ERROR'', sync_payload = $2, updated_at = timezone(''utc'', now()) where contribution_ledger_id = $1', v_schema_name)
          using v_ledger_id, jsonb_build_object('error', v_sync_result);
        v_errors := v_errors + 1;
      else
        execute format('update %I.wcm_ptax_monthly_ledger set sync_status = ''SYNCED'', sync_payload = $2, updated_at = timezone(''utc'', now()) where contribution_ledger_id = $1', v_schema_name)
          using v_ledger_id, jsonb_build_object('synced_at', timezone('utc', now()));
        v_synced := v_synced + 1;
      end if;
    else
      v_skipped := v_skipped + 1;
    end if;

    v_processed := v_processed + 1;
  end loop;

  execute format(
    'update %I.wcm_ptax_processing_batch
        set batch_status = case when $2 > 0 then ''FAILED'' when $3 > 0 then ''SYNCED'' else ''PROCESSED'' end,
            process_completed_at = timezone(''utc'', now()),
            summary_payload = jsonb_build_object(''processed_count'', $1, ''synced_count'', $3, ''skipped_count'', $4, ''error_count'', $2),
            error_payload = case when $2 > 0 then jsonb_build_object(''error_count'', $2) else ''{}''::jsonb end,
            updated_at = timezone(''utc'', now())
      where batch_id = $5',
    v_schema_name
  ) using v_processed, v_errors, v_synced, v_skipped, v_batch_id;

  perform public.platform_ptax_append_audit(v_schema_name, 'BATCH_PROCESSED', case when v_errors > 0 then 'PARTIAL' else 'SUCCESS' end, 'wcm_ptax_processing_batch', v_batch_id::text, jsonb_build_object('processed_count', v_processed, 'synced_count', v_synced, 'skipped_count', v_skipped, 'error_count', v_errors), v_actor_user_id, null, v_batch_id);

  return public.platform_json_response(v_errors = 0,'OK','PTAX batch processed.',jsonb_build_object('batch_id', v_batch_id, 'processed_count', v_processed, 'synced_count', v_synced, 'skipped_count', v_skipped, 'error_count', v_errors));
exception when others then
  if v_batch_id is not null then
    execute format('update %I.wcm_ptax_processing_batch set batch_status = ''FAILED'', error_payload = $2, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
      using v_batch_id, jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm);
  end if;
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_process_ptax_batch_job.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_request_ptax_retry_batch(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_ptax_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_batch_id bigint := nullif(p_params->>'batch_id', '')::bigint;
  v_exists boolean;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  if v_batch_id is null then
    return public.platform_json_response(false,'BATCH_ID_REQUIRED','batch_id is required.','{}'::jsonb);
  end if;

  execute format('select exists(select 1 from %I.wcm_ptax_processing_batch where batch_id = $1)', v_schema_name)
    into v_exists using v_batch_id;
  if not coalesce(v_exists, false) then
    return public.platform_json_response(false,'BATCH_NOT_FOUND','PTAX batch was not found.',jsonb_build_object('batch_id', v_batch_id));
  end if;

  execute format('update %I.wcm_ptax_processing_batch set batch_status = ''REQUESTED'', process_started_at = null, process_completed_at = null, error_payload = ''{}''::jsonb, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
    using v_batch_id;
  execute format('update %I.wcm_ptax_monthly_ledger set sync_status = ''PENDING'', sync_payload = ''{}''::jsonb, updated_at = timezone(''utc'', now()) where batch_id = $1 and sync_status = ''ERROR''', v_schema_name)
    using v_batch_id;

  perform public.platform_ptax_append_audit(v_schema_name, 'BATCH_RETRY_REQUESTED', 'SUCCESS', 'wcm_ptax_processing_batch', v_batch_id::text, '{}'::jsonb, v_actor_user_id, null, v_batch_id);
  return public.platform_json_response(true,'OK','PTAX batch reset for retry.',jsonb_build_object('batch_id', v_batch_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_request_ptax_retry_batch.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
