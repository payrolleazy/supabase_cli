create or replace function public.platform_process_esic_batch_job(p_params jsonb)
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
  v_batch_id bigint := nullif(p_params->>'batch_id', '')::bigint;
  v_batch record;
  v_row record;
  v_ledger_id uuid;
  v_gross_wages numeric;
  v_eligible_wages numeric;
  v_employee_contribution numeric;
  v_employer_contribution numeric;
  v_total_contribution numeric;
  v_calendar_days integer;
  v_worked_days numeric;
  v_sync_result jsonb;
  v_processed integer := 0;
  v_skipped integer := 0;
  v_bounds jsonb;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  if v_batch_id is null then return public.platform_json_response(false,'BATCH_ID_REQUIRED','batch_id is required.','{}'::jsonb); end if;

  execute format('select * from %I.wcm_esic_processing_batch where batch_id = $1', v_schema_name) into v_batch using v_batch_id;
  if v_batch.batch_id is null then return public.platform_json_response(false,'BATCH_NOT_FOUND','ESIC batch was not found.',jsonb_build_object('batch_id', v_batch_id)); end if;

  execute format('update %I.wcm_esic_processing_batch set batch_status = ''PROCESSING'', process_started_at = timezone(''utc'', now()), error_payload = ''{}''::jsonb, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
    using v_batch_id;

  for v_row in execute format(
    'select r.registration_id,
            r.employee_id,
            r.ip_number,
            r.wage_basis_override,
            r.registration_status,
            e.establishment_id,
            e.state_code,
            cfg.configuration_id,
            cfg.wage_ceiling,
            cfg.employee_contribution_rate,
            cfg.employer_contribution_rate,
            ss.service_state,
            ss.last_billable,
            coalesce(inp.eligible_input_wages, 0) as eligible_input_wages
       from %I.wcm_esic_employee_registration r
       join %I.wcm_esic_establishment e on e.establishment_id = r.establishment_id
       join %I.wcm_employee_service_state ss on ss.employee_id = r.employee_id
       left join lateral (
         select c.configuration_id, c.wage_ceiling, c.employee_contribution_rate, c.employer_contribution_rate
           from %I.wcm_esic_configuration c
          where c.state_code = e.state_code
            and c.configuration_status = ''ACTIVE''
            and c.effective_from <= $2
            and (c.effective_to is null or c.effective_to >= $2)
          order by c.effective_from desc
          limit 1
       ) cfg on true
       left join lateral (
         select coalesce(sum(pie.numeric_value), 0) as eligible_input_wages
           from %I.wcm_payroll_input_entry pie
           join %I.wcm_esic_wage_component_mapping m
             on m.component_code = pie.component_code
            and m.is_esic_eligible = true
            and m.effective_from <= $2
            and (m.effective_to is null or m.effective_to >= $2)
          where pie.employee_id = r.employee_id
            and pie.payroll_period = $2
            and pie.input_status in (''VALIDATED'',''LOCKED'')
       ) inp on true
      where r.establishment_id = $1
        and r.registration_status in (''ACTIVE'',''PENDING'')
        and r.effective_from <= $2
        and (r.effective_to is null or r.effective_to >= $2)
      order by r.created_at, r.registration_id',
    v_schema_name, v_schema_name, v_schema_name, v_schema_name, v_schema_name, v_schema_name
  ) using v_batch.establishment_id, v_batch.payroll_period
  loop
    if v_row.configuration_id is null then
      v_skipped := v_skipped + 1;
      perform public.platform_esic_append_audit(v_schema_name, 'BATCH_SKIP', 'WARNING', 'REGISTRATION', v_row.registration_id::text, jsonb_build_object('reason', 'MISSING_ACTIVE_CONFIGURATION', 'state_code', v_row.state_code), v_actor_user_id, v_row.employee_id, v_batch_id);
      continue;
    end if;

    if coalesce(v_row.registration_status, '') <> 'ACTIVE' then
      v_skipped := v_skipped + 1;
      perform public.platform_esic_append_audit(v_schema_name, 'BATCH_SKIP', 'WARNING', 'REGISTRATION', v_row.registration_id::text, jsonb_build_object('reason', 'REGISTRATION_NOT_ACTIVE', 'registration_status', v_row.registration_status), v_actor_user_id, v_row.employee_id, v_batch_id);
      continue;
    end if;

    if v_row.ip_number is null or btrim(coalesce(v_row.ip_number, '')) = '' then
      v_skipped := v_skipped + 1;
      perform public.platform_esic_append_audit(v_schema_name, 'BATCH_SKIP', 'WARNING', 'REGISTRATION', v_row.registration_id::text, jsonb_build_object('reason', 'MISSING_IP_NUMBER'), v_actor_user_id, v_row.employee_id, v_batch_id);
      continue;
    end if;

    if coalesce(v_row.service_state, '') <> 'active' or coalesce(v_row.last_billable, false) is not true then
      v_skipped := v_skipped + 1;
      perform public.platform_esic_append_audit(v_schema_name, 'BATCH_SKIP', 'WARNING', 'REGISTRATION', v_row.registration_id::text, jsonb_build_object('reason', 'INACTIVE_EMPLOYEE', 'service_state', v_row.service_state, 'last_billable', v_row.last_billable), v_actor_user_id, v_row.employee_id, v_batch_id);
      continue;
    end if;

    v_gross_wages := coalesce(nullif(v_row.eligible_input_wages, 0), v_row.wage_basis_override, v_row.wage_ceiling);
    if coalesce(v_gross_wages, 0) <= 0 then
      v_skipped := v_skipped + 1;
      perform public.platform_esic_append_audit(v_schema_name, 'BATCH_SKIP', 'WARNING', 'REGISTRATION', v_row.registration_id::text, jsonb_build_object('reason', 'NON_POSITIVE_WAGES'), v_actor_user_id, v_row.employee_id, v_batch_id);
      continue;
    end if;

    v_eligible_wages := least(v_gross_wages, coalesce(v_row.wage_ceiling, v_gross_wages));
    v_employee_contribution := round((v_eligible_wages * coalesce(v_row.employee_contribution_rate, 0.75)) / 100.00, 2);
    v_employer_contribution := round((v_eligible_wages * coalesce(v_row.employer_contribution_rate, 3.25)) / 100.00, 2);
    v_total_contribution := coalesce(v_employee_contribution, 0) + coalesce(v_employer_contribution, 0);
    v_calendar_days := extract(day from ((date_trunc('month', v_batch.payroll_period::timestamp) + interval '1 month - 1 day')))::integer;
    v_worked_days := v_calendar_days::numeric;
    v_bounds := public.platform_esic_benefit_period_window(v_batch.payroll_period);

    execute format(
      'insert into %I.wcm_esic_contribution_ledger (batch_id, employee_id, registration_id, payroll_period, ip_number, gross_wages, eligible_wages, arrear_wages_included, employee_contribution, employer_contribution, total_contribution, calendar_days, worked_days, absent_days, benefit_period_start, benefit_period_end, sync_status, sync_payload, warning_messages, ledger_metadata)
       values ($1,$2,$3,$4,$5,$6,$7,0,$8,$9,$10,$11,$12,0,$13,$14,''PENDING'',''{}''::jsonb,$15,$16)
       on conflict (employee_id, payroll_period, batch_id) do update
       set registration_id = excluded.registration_id,
           ip_number = excluded.ip_number,
           gross_wages = excluded.gross_wages,
           eligible_wages = excluded.eligible_wages,
           employee_contribution = excluded.employee_contribution,
           employer_contribution = excluded.employer_contribution,
           total_contribution = excluded.total_contribution,
           calendar_days = excluded.calendar_days,
           worked_days = excluded.worked_days,
           absent_days = excluded.absent_days,
           benefit_period_start = excluded.benefit_period_start,
           benefit_period_end = excluded.benefit_period_end,
           sync_status = ''PENDING'',
           sync_payload = ''{}''::jsonb,
           warning_messages = excluded.warning_messages,
           ledger_metadata = excluded.ledger_metadata,
           updated_at = timezone(''utc'', now())
       returning contribution_ledger_id',
      v_schema_name
    ) into v_ledger_id using
      v_batch_id,
      v_row.employee_id,
      v_row.registration_id,
      v_batch.payroll_period,
      v_row.ip_number,
      v_gross_wages,
      v_eligible_wages,
      v_employee_contribution,
      v_employer_contribution,
      v_total_contribution,
      v_calendar_days,
      v_worked_days,
      public.platform_esic_try_date(v_bounds->>'benefit_period_start'),
      public.platform_esic_try_date(v_bounds->>'benefit_period_end'),
      case when v_gross_wages > v_eligible_wages then array['WAGE_CEILING_APPLIED']::text[] else '{}'::text[] end,
      jsonb_build_object('module', 'ESIC', 'establishment_id', v_batch.establishment_id, 'configuration_id', v_row.configuration_id, 'input_wages', v_row.eligible_input_wages);

    v_sync_result := public.platform_esic_sync_deduction_to_payroll_internal(v_schema_name, v_tenant_id, v_row.employee_id, v_batch.payroll_period, v_batch_id, v_ledger_id::text, v_employee_contribution, v_employer_contribution);
    if coalesce((v_sync_result->>'success')::boolean, false) is not true then
      execute format('update %I.wcm_esic_contribution_ledger set sync_status = ''ERROR'', sync_payload = $2, updated_at = timezone(''utc'', now()) where contribution_ledger_id = $1', v_schema_name)
        using v_ledger_id, jsonb_build_object('error', v_sync_result);
      execute format('update %I.wcm_esic_processing_batch set batch_status = ''FAILED'', error_payload = $2, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
        using v_batch_id, jsonb_build_object('sync_error', v_sync_result, 'employee_id', v_row.employee_id);
      return v_sync_result;
    end if;

    execute format('update %I.wcm_esic_contribution_ledger set sync_status = ''SYNCED'', sync_payload = $2, updated_at = timezone(''utc'', now()) where contribution_ledger_id = $1', v_schema_name)
      using v_ledger_id, jsonb_build_object('synced_at', timezone('utc', now()));

    perform public.platform_esic_refresh_benefit_period_internal(v_schema_name, v_row.employee_id, v_batch.payroll_period, v_actor_user_id);
    v_processed := v_processed + 1;
  end loop;

  execute format(
    'update %I.wcm_esic_processing_batch
        set batch_status = case when $2 > 0 then ''SYNCED'' else ''PROCESSED'' end,
            process_completed_at = timezone(''utc'', now()),
            summary_payload = $1,
            updated_at = timezone(''utc'', now())
      where batch_id = $3',
    v_schema_name
  ) using jsonb_build_object('processed_count', v_processed, 'skipped_count', v_skipped), v_processed, v_batch_id;

  perform public.platform_esic_append_audit(v_schema_name, 'BATCH_PROCESS', 'OK', 'BATCH', v_batch_id::text, jsonb_build_object('processed_count', v_processed,'skipped_count', v_skipped), v_actor_user_id, null, v_batch_id);
  return public.platform_json_response(true,'OK','ESIC batch processed.',jsonb_build_object('batch_id', v_batch_id,'processed_count', v_processed,'skipped_count', v_skipped));
exception when others then
  if v_context is not null and coalesce((v_context->>'success')::boolean, false) is true then
    v_schema_name := v_context->'details'->>'tenant_schema';
    if v_schema_name is not null then
      execute format('update %I.wcm_esic_processing_batch set batch_status = ''FAILED'', error_payload = $2, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
        using v_batch_id, jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm);
    end if;
  end if;
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_process_esic_batch_job.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
