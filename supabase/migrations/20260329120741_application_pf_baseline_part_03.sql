create or replace function public.platform_request_pf_batch(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context(p_params);
  v_schema_name text;
  v_tenant_id uuid;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_establishment_id uuid := public.platform_try_uuid(p_params->>'establishment_id');
  v_period date := date_trunc('month', coalesce(public.platform_pf_try_date(p_params->>'payroll_period'), current_date)::timestamp)::date;
  v_batch record;
  v_enqueue_result jsonb;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  if v_establishment_id is null then return public.platform_json_response(false,'ESTABLISHMENT_ID_REQUIRED','establishment_id is required.','{}'::jsonb); end if;

  execute format(
    'insert into %I.wcm_pf_processing_batch (establishment_id, payroll_period, batch_status, requested_by_actor_user_id)
     values ($1,$2,''REQUESTED'',$3)
     on conflict (establishment_id, payroll_period) do update
     set requested_by_actor_user_id = excluded.requested_by_actor_user_id,
         updated_at = timezone(''utc'', now())
     returning batch_id, establishment_id, payroll_period, batch_status',
    v_schema_name
  ) into v_batch using v_establishment_id, v_period, v_actor_user_id;

  v_enqueue_result := public.platform_async_enqueue_job(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'worker_code', 'pf_monthly_worker',
    'job_type', 'process_pf_batch',
    'priority', 70,
    'payload', jsonb_build_object('tenant_id', v_tenant_id, 'batch_id', v_batch.batch_id, 'establishment_id', v_establishment_id, 'payroll_period', v_period, 'actor_user_id', v_actor_user_id),
    'deduplication_key', format('pf:%s:%s:%s', v_tenant_id::text, v_establishment_id::text, v_period::text),
    'origin_source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_request_pf_batch'),
    'metadata', jsonb_build_object('slice', 'PF', 'reason', 'monthly_compute')
  ));
  if coalesce((v_enqueue_result->>'success')::boolean, false) is not true then return v_enqueue_result; end if;

  execute format('update %I.wcm_pf_processing_batch set worker_job_id = $2, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
    using v_batch.batch_id, public.platform_try_uuid(v_enqueue_result->'details'->>'job_id');

  perform public.platform_pf_append_audit(v_schema_name, 'BATCH_REQUEST', 'OK', 'BATCH', v_batch.batch_id::text, jsonb_build_object('payroll_period', v_period), v_actor_user_id, null, v_batch.batch_id);
  return public.platform_json_response(true,'OK','PF batch requested.',jsonb_build_object('batch_id', v_batch.batch_id,'payroll_period', v_period,'job_id', v_enqueue_result->'details'->>'job_id'));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_request_pf_batch.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_process_pf_batch_job(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context(p_params);
  v_schema_name text;
  v_tenant_id uuid;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_batch_id bigint := nullif(p_params->>'batch_id', '')::bigint;
  v_batch record;
  v_row record;
  v_ledger_id uuid;
  v_employee_share numeric;
  v_employer_share numeric;
  v_eps_share numeric;
  v_epf_share numeric;
  v_admin_charge numeric;
  v_edli_charge numeric;
  v_sync_result jsonb;
  v_processed integer := 0;
  v_anomalies integer := 0;
  v_skipped integer := 0;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  if v_batch_id is null then return public.platform_json_response(false,'BATCH_ID_REQUIRED','batch_id is required.','{}'::jsonb); end if;

  execute format('select * from %I.wcm_pf_processing_batch where batch_id = $1', v_schema_name) into v_batch using v_batch_id;
  if not found then return public.platform_json_response(false,'BATCH_NOT_FOUND','PF batch was not found.',jsonb_build_object('batch_id', v_batch_id)); end if;

  execute format('update %I.wcm_pf_processing_batch set batch_status = ''PROCESSING'', process_started_at = timezone(''utc'', now()), error_payload = ''{}''::jsonb, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
    using v_batch_id;

  perform public.platform_process_pf_arrear_job(jsonb_build_object('tenant_id', v_tenant_id,'establishment_id', v_batch.establishment_id,'payroll_period', v_batch.payroll_period,'actor_user_id', v_actor_user_id));

  for v_row in execute format(
    'select e.enrollment_id,
            e.employee_id,
            e.uan,
            e.pf_member_id,
            coalesce(e.wage_basis_override, s.wage_ceiling) as wage_basis_override,
            coalesce(e.voluntary_pf_rate, s.employee_pf_rate) as employee_pf_rate,
            s.employer_pf_rate,
            s.eps_rate,
            s.admin_charge_rate,
            s.edli_rate,
            s.wage_ceiling,
            e.eps_eligible,
            coalesce(a.wage_delta, 0) as arrear_wage_delta,
            coalesce(a.employee_share_delta, null) as arrear_employee_share_delta,
            coalesce(a.employer_share_delta, null) as arrear_employer_share_delta,
            ss.service_state,
            ss.last_billable
       from %I.wcm_pf_employee_enrollment e
       join %I.wcm_pf_establishment s on s.establishment_id = e.establishment_id
       join %I.wcm_employee_service_state ss on ss.employee_id = e.employee_id
       left join lateral (
         select sum(wage_delta) as wage_delta,
                sum(employee_share_delta) as employee_share_delta,
                sum(employer_share_delta) as employer_share_delta
           from %I.wcm_pf_arrear_case a
          where a.employee_id = e.employee_id
            and a.establishment_id = e.establishment_id
            and a.effective_period <= $2
            and a.arrear_status in (''APPROVED'',''READY_FOR_BATCH'')
       ) a on true
      where e.establishment_id = $1
        and e.enrollment_status = ''ACTIVE''
        and e.effective_from <= $2
        and (e.effective_to is null or e.effective_to >= $2)
      order by e.created_at, e.enrollment_id',
    v_schema_name, v_schema_name, v_schema_name, v_schema_name
  ) using v_batch.establishment_id, v_batch.payroll_period
  loop
    if v_row.uan is null or btrim(coalesce(v_row.uan, '')) = '' or v_row.pf_member_id is null or btrim(coalesce(v_row.pf_member_id, '')) = '' then
      execute format(
        'insert into %I.wcm_pf_anomaly (batch_id, employee_id, anomaly_code, severity, anomaly_message, anomaly_status, anomaly_payload)
         values ($1,$2,''MISSING_REGISTRATION'',''ERROR'',''PF enrollment is missing UAN or PF member id.'',''OPEN'',$3)
         on conflict (batch_id, employee_id, anomaly_code) do update
         set anomaly_message = excluded.anomaly_message,
             anomaly_status = ''OPEN'',
             anomaly_payload = excluded.anomaly_payload,
             updated_at = timezone(''utc'', now())',
        v_schema_name
      ) using v_batch_id, v_row.employee_id, jsonb_build_object('uan', v_row.uan, 'pf_member_id', v_row.pf_member_id);
      v_anomalies := v_anomalies + 1;
      continue;
    end if;

    if coalesce(v_row.service_state, '') <> 'active' or coalesce(v_row.last_billable, false) is not true then
      execute format(
        'insert into %I.wcm_pf_anomaly (batch_id, employee_id, anomaly_code, severity, anomaly_message, anomaly_status, anomaly_payload)
         values ($1,$2,''INACTIVE_EMPLOYEE'',''WARNING'',''Employee is not billable for PF processing.'',''OPEN'',$3)
         on conflict (batch_id, employee_id, anomaly_code) do update
         set anomaly_message = excluded.anomaly_message,
             anomaly_status = ''OPEN'',
             anomaly_payload = excluded.anomaly_payload,
             updated_at = timezone(''utc'', now())',
        v_schema_name
      ) using v_batch_id, v_row.employee_id, jsonb_build_object('service_state', v_row.service_state, 'last_billable', v_row.last_billable);
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_employee_share := round((least(coalesce(v_row.wage_basis_override, v_row.wage_ceiling), v_row.wage_ceiling) * coalesce(v_row.employee_pf_rate, 12.00)) / 100.00, 2)
      + coalesce(v_row.arrear_employee_share_delta, round((coalesce(v_row.arrear_wage_delta, 0) * coalesce(v_row.employee_pf_rate, 12.00)) / 100.00, 2), 0);
    v_employer_share := round((least(coalesce(v_row.wage_basis_override, v_row.wage_ceiling), v_row.wage_ceiling) * coalesce(v_row.employer_pf_rate, 12.00)) / 100.00, 2)
      + coalesce(v_row.arrear_employer_share_delta, round((coalesce(v_row.arrear_wage_delta, 0) * coalesce(v_row.employer_pf_rate, 12.00)) / 100.00, 2), 0);
    v_eps_share := case when coalesce(v_row.eps_eligible, true) then round((least(coalesce(v_row.wage_basis_override, v_row.wage_ceiling), v_row.wage_ceiling) * coalesce(v_row.eps_rate, 8.33)) / 100.00, 2) else 0 end;
    v_epf_share := greatest(v_employer_share - v_eps_share, 0);
    v_admin_charge := round((least(coalesce(v_row.wage_basis_override, v_row.wage_ceiling), v_row.wage_ceiling) * coalesce(v_row.admin_charge_rate, 0.50)) / 100.00, 2);
    v_edli_charge := round((least(coalesce(v_row.wage_basis_override, v_row.wage_ceiling), v_row.wage_ceiling) * coalesce(v_row.edli_rate, 0.50)) / 100.00, 2);

    execute format(
      'insert into %I.wcm_pf_contribution_ledger (batch_id, employee_id, enrollment_id, payroll_period, wage_basis, arrear_wage_basis, employee_share, employer_share, eps_share, epf_share, admin_charge, edli_charge, sync_status, sync_payload, ledger_metadata)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,''PENDING'',''{}''::jsonb,$13)
       on conflict (employee_id, payroll_period, batch_id) do update
       set enrollment_id = excluded.enrollment_id,
           wage_basis = excluded.wage_basis,
           arrear_wage_basis = excluded.arrear_wage_basis,
           employee_share = excluded.employee_share,
           employer_share = excluded.employer_share,
           eps_share = excluded.eps_share,
           epf_share = excluded.epf_share,
           admin_charge = excluded.admin_charge,
           edli_charge = excluded.edli_charge,
           sync_status = ''PENDING'',
           sync_payload = ''{}''::jsonb,
           ledger_metadata = excluded.ledger_metadata,
           updated_at = timezone(''utc'', now())
       returning contribution_ledger_id',
      v_schema_name
    ) into v_ledger_id using
      v_batch_id,
      v_row.employee_id,
      v_row.enrollment_id,
      v_batch.payroll_period,
      least(coalesce(v_row.wage_basis_override, v_row.wage_ceiling), v_row.wage_ceiling),
      coalesce(v_row.arrear_wage_delta, 0),
      v_employee_share,
      v_employer_share,
      v_eps_share,
      v_epf_share,
      v_admin_charge,
      v_edli_charge,
      jsonb_build_object('module', 'PF', 'establishment_id', v_batch.establishment_id, 'employee_id', v_row.employee_id);

    v_sync_result := public.platform_pf_sync_deduction_to_payroll_internal(v_schema_name, v_tenant_id, v_row.employee_id, v_batch.payroll_period, v_batch_id, v_ledger_id::text, v_employee_share, v_employer_share, v_eps_share, v_admin_charge, v_edli_charge);
    if coalesce((v_sync_result->>'success')::boolean, false) is not true then
      execute format('update %I.wcm_pf_contribution_ledger set sync_status = ''ERROR'', sync_payload = $2, updated_at = timezone(''utc'', now()) where contribution_ledger_id = $1', v_schema_name)
        using v_ledger_id, jsonb_build_object('error', v_sync_result);
      execute format('update %I.wcm_pf_processing_batch set batch_status = ''FAILED'', error_payload = $2, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
        using v_batch_id, jsonb_build_object('sync_error', v_sync_result, 'employee_id', v_row.employee_id);
      return v_sync_result;
    end if;

    execute format('update %I.wcm_pf_contribution_ledger set sync_status = ''SYNCED'', sync_payload = $2, updated_at = timezone(''utc'', now()) where contribution_ledger_id = $1', v_schema_name)
      using v_ledger_id, jsonb_build_object('synced_at', timezone('utc', now()));

    execute format('update %I.wcm_pf_arrear_case set arrear_status = ''SETTLED'', settled_batch_id = $2, updated_at = timezone(''utc'', now()) where employee_id = $1 and establishment_id = $3 and effective_period <= $4 and arrear_status in (''APPROVED'',''READY_FOR_BATCH'')', v_schema_name)
      using v_row.employee_id, v_batch_id, v_batch.establishment_id, v_batch.payroll_period;

    execute format('update %I.wcm_pf_anomaly set anomaly_status = ''RESOLVED'', resolution_notes = ''Auto-resolved after successful PF batch processing.'', updated_at = timezone(''utc'', now()) where batch_id = $1 and employee_id = $2 and anomaly_status = ''OPEN'' and anomaly_code in (''MISSING_REGISTRATION'',''INACTIVE_EMPLOYEE'')', v_schema_name)
      using v_batch_id, v_row.employee_id;

    v_processed := v_processed + 1;
  end loop;

  execute format(
    'update %I.wcm_pf_processing_batch
        set batch_status = case when $2 > 0 then ''SYNCED'' else ''PROCESSED'' end,
            process_completed_at = timezone(''utc'', now()),
            summary_payload = $1,
            updated_at = timezone(''utc'', now())
      where batch_id = $3',
    v_schema_name
  ) using jsonb_build_object('processed_count', v_processed, 'anomaly_count', v_anomalies, 'skipped_count', v_skipped), v_processed, v_batch_id;

  perform public.platform_pf_append_audit(v_schema_name, 'BATCH_PROCESS', 'OK', 'BATCH', v_batch_id::text, jsonb_build_object('processed_count', v_processed,'anomaly_count', v_anomalies,'skipped_count', v_skipped), v_actor_user_id, null, v_batch_id);
  return public.platform_json_response(true,'OK','PF batch processed.',jsonb_build_object('batch_id', v_batch_id,'processed_count', v_processed,'anomaly_count', v_anomalies,'skipped_count', v_skipped));
exception when others then
  if v_context is not null and coalesce((v_context->>'success')::boolean, false) is true then
    v_schema_name := v_context->'details'->>'tenant_schema';
    if v_schema_name is not null then
      execute format('update %I.wcm_pf_processing_batch set batch_status = ''FAILED'', error_payload = $2, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
        using v_batch_id, jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm);
    end if;
  end if;
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_process_pf_batch_job.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_review_pf_anomaly(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_anomaly_id uuid := public.platform_try_uuid(p_params->>'anomaly_id');
  v_action text := upper(coalesce(nullif(btrim(p_params->>'action'), ''), 'RESOLVE'));
  v_count integer;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_anomaly_id is null then return public.platform_json_response(false,'ANOMALY_ID_REQUIRED','anomaly_id is required.','{}'::jsonb); end if;
  if v_action not in ('RESOLVE','IGNORE','REOPEN') then return public.platform_json_response(false,'ANOMALY_ACTION_INVALID','action must be RESOLVE, IGNORE, or REOPEN.','{}'::jsonb); end if;

  execute format(
    'update %I.wcm_pf_anomaly
        set anomaly_status = $2,
            resolution_notes = $3,
            reviewed_by_actor_user_id = $4,
            updated_at = timezone(''utc'', now())
      where anomaly_id = $1',
    v_schema_name
  ) using v_anomaly_id,
          case v_action when 'RESOLVE' then 'RESOLVED' when 'IGNORE' then 'IGNORED' else 'OPEN' end,
          nullif(btrim(p_params->>'resolution_notes'), ''),
          v_actor_user_id;
  get diagnostics v_count = row_count;
  if v_count <> 1 then return public.platform_json_response(false,'ANOMALY_NOT_FOUND','PF anomaly was not found.',jsonb_build_object('anomaly_id', v_anomaly_id)); end if;

  perform public.platform_pf_append_audit(v_schema_name, 'ANOMALY_REVIEW', 'OK', 'ANOMALY', v_anomaly_id::text, jsonb_build_object('action', v_action), v_actor_user_id, null, null);
  return public.platform_json_response(true,'OK','PF anomaly reviewed.',jsonb_build_object('anomaly_id', v_anomaly_id,'action', v_action));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_review_pf_anomaly.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_request_pf_ecr_run(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context(p_params);
  v_schema_name text;
  v_tenant_id uuid;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_batch_id bigint := nullif(p_params->>'batch_id', '')::bigint;
  v_template_document_id uuid := public.platform_try_uuid(p_params->>'template_document_id');
  v_batch record;
  v_run_id uuid;
  v_enqueue_result jsonb;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  if v_batch_id is null then return public.platform_json_response(false,'BATCH_ID_REQUIRED','batch_id is required.','{}'::jsonb); end if;

  if v_template_document_id is not null and not exists (
    select 1 from public.platform_document_record where document_id = v_template_document_id and tenant_id = v_tenant_id and document_status = 'active'
  ) then
    return public.platform_json_response(false,'TEMPLATE_DOCUMENT_NOT_FOUND','template_document_id was not found as an active governed document.',jsonb_build_object('template_document_id', v_template_document_id));
  end if;

  execute format('select * from %I.wcm_pf_processing_batch where batch_id = $1', v_schema_name) into v_batch using v_batch_id;
  if not found then return public.platform_json_response(false,'BATCH_NOT_FOUND','PF batch was not found.',jsonb_build_object('batch_id', v_batch_id)); end if;
  if v_batch.batch_status not in ('SYNCED','FINALIZED') then
    return public.platform_json_response(false,'BATCH_NOT_READY_FOR_ECR','PF batch must be SYNCED or FINALIZED before ECR generation can be requested.',jsonb_build_object('batch_id', v_batch_id, 'batch_status', v_batch.batch_status));
  end if;

  execute format(
    'insert into %I.wcm_pf_ecr_run (batch_id, establishment_id, payroll_period, template_document_id, run_status, created_by_actor_user_id)
     values ($1,$2,$3,$4,''REQUESTED'',$5)
     returning ecr_run_id',
    v_schema_name
  ) into v_run_id using v_batch.batch_id, v_batch.establishment_id, v_batch.payroll_period, v_template_document_id, v_actor_user_id;

  v_enqueue_result := public.platform_async_enqueue_job(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'worker_code', 'pf_ecr_generation_worker',
    'job_type', 'generate_pf_ecr',
    'priority', 65,
    'payload', jsonb_build_object('tenant_id', v_tenant_id, 'ecr_run_id', v_run_id, 'batch_id', v_batch_id, 'actor_user_id', v_actor_user_id),
    'deduplication_key', format('pf_ecr:%s:%s', v_tenant_id::text, v_run_id::text),
    'origin_source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_request_pf_ecr_run'),
    'metadata', jsonb_build_object('slice', 'PF', 'reason', 'ecr_generation')
  ));
  if coalesce((v_enqueue_result->>'success')::boolean, false) is not true then return v_enqueue_result; end if;

  execute format('update %I.wcm_pf_ecr_run set worker_job_id = $2, updated_at = timezone(''utc'', now()) where ecr_run_id = $1', v_schema_name)
    using v_run_id, public.platform_try_uuid(v_enqueue_result->'details'->>'job_id');

  perform public.platform_pf_append_audit(v_schema_name, 'ECR_REQUEST', 'OK', 'ECR_RUN', v_run_id::text, jsonb_build_object('batch_id', v_batch_id), v_actor_user_id, null, v_batch_id);
  return public.platform_json_response(true,'OK','PF ECR run requested.',jsonb_build_object('ecr_run_id', v_run_id,'batch_id', v_batch_id,'job_id', v_enqueue_result->'details'->>'job_id'));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_request_pf_ecr_run.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_process_pf_ecr_run_job(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_run_id uuid := public.platform_try_uuid(p_params->>'ecr_run_id');
  v_run record;
  v_row_count integer;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_run_id is null then return public.platform_json_response(false,'ECR_RUN_ID_REQUIRED','ecr_run_id is required.','{}'::jsonb); end if;

  execute format('select * from %I.wcm_pf_ecr_run where ecr_run_id = $1', v_schema_name) into v_run using v_run_id;
  if not found then return public.platform_json_response(false,'ECR_RUN_NOT_FOUND','PF ECR run was not found.',jsonb_build_object('ecr_run_id', v_run_id)); end if;

  execute format('update %I.wcm_pf_ecr_run set run_status = ''GENERATING'', updated_at = timezone(''utc'', now()) where ecr_run_id = $1', v_schema_name)
    using v_run_id;

  execute format('select count(*)::integer from %I.wcm_pf_contribution_ledger where batch_id = $1', v_schema_name) into v_row_count using v_run.batch_id;

  execute format(
    'update %I.wcm_pf_ecr_run
        set run_status = ''GENERATED'',
            row_count = $2,
            artifact_payload = $3,
            error_payload = ''{}''::jsonb,
            updated_at = timezone(''utc'', now())
      where ecr_run_id = $1',
    v_schema_name
  ) using v_run_id,
          coalesce(v_row_count, 0),
          jsonb_build_object('module', 'PF', 'format', 'ECR', 'generated_at', timezone('utc', now()), 'row_count', coalesce(v_row_count, 0));

  perform public.platform_pf_append_audit(v_schema_name, 'ECR_GENERATE', 'OK', 'ECR_RUN', v_run_id::text, jsonb_build_object('row_count', v_row_count), v_actor_user_id, null, v_run.batch_id);
  return public.platform_json_response(true,'OK','PF ECR run processed.',jsonb_build_object('ecr_run_id', v_run_id,'row_count', coalesce(v_row_count, 0),'run_status', 'GENERATED'));
exception when others then
  if v_context is not null and coalesce((v_context->>'success')::boolean, false) is true then
    v_schema_name := v_context->'details'->>'tenant_schema';
    if v_schema_name is not null and v_run_id is not null then
      execute format('update %I.wcm_pf_ecr_run set run_status = ''FAILED'', error_payload = $2, updated_at = timezone(''utc'', now()) where ecr_run_id = $1', v_schema_name)
        using v_run_id, jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm);
    end if;
  end if;
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_process_pf_ecr_run_job.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
