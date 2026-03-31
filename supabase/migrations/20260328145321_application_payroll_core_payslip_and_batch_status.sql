set search_path = public, pg_temp;

create or replace function public.platform_request_payslip_run(p_params jsonb)
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
  v_payslip_run_id uuid;
  v_enqueue_result jsonb;
  v_item_count integer := 0;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  if v_payroll_batch_id is null then return public.platform_json_response(false,'PAYROLL_BATCH_ID_REQUIRED','payroll_batch_id is required.', '{}'::jsonb); end if;

  execute format('select payroll_batch_id, payroll_period, batch_status from %I.wcm_payroll_batch where payroll_batch_id = $1', v_schema_name) into v_batch using v_payroll_batch_id;
  if v_batch.payroll_batch_id is null then return public.platform_json_response(false,'PAYROLL_BATCH_NOT_FOUND','Payroll batch not found.',jsonb_build_object('payroll_batch_id', v_payroll_batch_id)); end if;
  if v_batch.batch_status <> 'FINALIZED' then return public.platform_json_response(false,'PAYROLL_BATCH_NOT_FINALIZED','Payslips can only be requested for FINALIZED payroll batches.',jsonb_build_object('payroll_batch_id', v_payroll_batch_id,'batch_status', v_batch.batch_status)); end if;

  execute format('insert into %I.wcm_payslip_run (payroll_batch_id, payroll_period, run_status, requested_by_actor_user_id) values ($1,$2,''QUEUED'',$3) returning payslip_run_id', v_schema_name)
    into v_payslip_run_id using v_payroll_batch_id, v_batch.payroll_period, v_actor_user_id;

  execute format(
    'insert into %I.wcm_payslip_item (payslip_run_id, payroll_batch_id, employee_id, item_status, artifact_status)
     select $1, $2, employee_id, ''QUEUED'', ''PENDING_GENERATION''
       from (select distinct employee_id from %I.wcm_component_calculation_result where payroll_batch_id = $2) q',
    v_schema_name,
    v_schema_name
  ) using v_payslip_run_id, v_payroll_batch_id;

  execute format('select count(*) from %I.wcm_payslip_item where payslip_run_id = $1', v_schema_name) into v_item_count using v_payslip_run_id;
  if coalesce(v_item_count, 0) = 0 then
    execute format('update %I.wcm_payslip_run set run_status = ''FAILED'', run_metadata = jsonb_build_object(''error'', ''NO_PAYROLL_RESULTS_FOUND''), updated_at = timezone(''utc'', now()) where payslip_run_id = $1', v_schema_name)
      using v_payslip_run_id;
    return public.platform_json_response(false,'NO_PAYROLL_RESULTS_FOUND','No payroll calculation results were found for the finalized batch.',jsonb_build_object('payroll_batch_id', v_payroll_batch_id));
  end if;

  v_enqueue_result := public.platform_async_enqueue_job(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'worker_code', 'payslip_generation_worker',
    'job_type', 'generate_payslip_payloads',
    'priority', 80,
    'payload', jsonb_build_object('tenant_id', v_tenant_id, 'payslip_run_id', v_payslip_run_id, 'actor_user_id', v_actor_user_id),
    'deduplication_key', format('payslip:%s:%s', v_tenant_id::text, v_payslip_run_id::text),
    'origin_source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_request_payslip_run'),
    'metadata', jsonb_build_object('slice', 'PAYROLL_CORE', 'reason', 'payslip_generation')
  ));
  if coalesce((v_enqueue_result->>'success')::boolean, false) is not true then
    execute format('update %I.wcm_payslip_run set run_status = ''FAILED'', run_metadata = jsonb_build_object(''error'', $2), updated_at = timezone(''utc'', now()) where payslip_run_id = $1', v_schema_name)
      using v_payslip_run_id, coalesce(v_enqueue_result->>'message', v_enqueue_result::text);
    execute format('update %I.wcm_payslip_item set item_status = ''FAILED'', artifact_status = ''FAILED'', last_error = $2, updated_at = timezone(''utc'', now()) where payslip_run_id = $1 and item_status = ''QUEUED''', v_schema_name)
      using v_payslip_run_id, coalesce(v_enqueue_result->>'message', v_enqueue_result::text);
    return v_enqueue_result;
  end if;

  execute format('update %I.wcm_payslip_run set run_status = ''PROCESSING'', updated_at = timezone(''utc'', now()) where payslip_run_id = $1', v_schema_name)
    using v_payslip_run_id;

  perform public.platform_payroll_core_append_audit(v_schema_name, 'PAYSLIP_RUN_REQUESTED', 'PAYROLL_CORE', jsonb_build_object('payslip_run_id', v_payslip_run_id,'item_count', v_item_count), v_payslip_run_id, null, v_payroll_batch_id, null, v_actor_user_id);

  return public.platform_json_response(true,'OK','Payslip run queued.',jsonb_build_object('payslip_run_id', v_payslip_run_id,'item_count', v_item_count,'enqueued_job_id', v_enqueue_result->'details'->>'job_id'));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_request_payslip_run.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_process_payslip_run_job(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_payslip_run_id uuid := public.platform_try_uuid(p_params->>'payslip_run_id');
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_run record;
  v_item record;
  v_snapshot jsonb;
  v_render_payload jsonb;
  v_completed integer := 0;
  v_failed integer := 0;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_payslip_run_id is null then return public.platform_json_response(false,'PAYSLIP_RUN_ID_REQUIRED','payslip_run_id is required.', '{}'::jsonb); end if;

  execute format('select payslip_run_id, payroll_batch_id, payroll_period, run_status from %I.wcm_payslip_run where payslip_run_id = $1 for update', v_schema_name) into v_run using v_payslip_run_id;
  if v_run.payslip_run_id is null then return public.platform_json_response(false,'PAYSLIP_RUN_NOT_FOUND','Payslip run not found.',jsonb_build_object('payslip_run_id', v_payslip_run_id)); end if;
  if v_run.run_status not in ('PROCESSING', 'FAILED') then return public.platform_json_response(false,'PAYSLIP_RUN_NOT_PROCESSABLE','Payslip run must be PROCESSING or FAILED before worker execution.',jsonb_build_object('payslip_run_id', v_payslip_run_id,'run_status', v_run.run_status)); end if;

  for v_item in execute format('select payslip_item_id, employee_id from %I.wcm_payslip_item where payslip_run_id = $1 and item_status in (''QUEUED'', ''FAILED'') order by payslip_item_id', v_schema_name) using v_payslip_run_id
  loop
    begin
      v_snapshot := public.platform_payroll_core_result_snapshot(v_schema_name, v_run.payroll_batch_id, v_item.employee_id);
      execute format('select jsonb_build_object(''employee_id'', e.employee_id, ''employee_code'', e.employee_code, ''employee_name'', trim(concat_ws('' '', e.first_name, e.last_name)), ''payroll_period'', $2, ''summary'', $3) from %I.wcm_employee e where e.employee_id = $1', v_schema_name)
        into v_render_payload using v_item.employee_id, v_run.payroll_period, v_snapshot;

      execute format('update %I.wcm_payslip_item set item_status = ''COMPLETED'', artifact_status = ''PAYLOAD_READY'', render_payload = $2, last_error = null, completed_at = timezone(''utc'', now()), updated_at = timezone(''utc'', now()) where payslip_item_id = $1', v_schema_name)
        using v_item.payslip_item_id, coalesce(v_render_payload, jsonb_build_object('employee_id', v_item.employee_id, 'payroll_period', v_run.payroll_period, 'summary', v_snapshot));

      perform public.platform_payroll_core_append_audit(v_schema_name, 'PAYSLIP_ITEM_RENDER_PAYLOAD_READY', 'PAYROLL_CORE', jsonb_build_object('payslip_item_id', v_item.payslip_item_id), v_payslip_run_id, v_item.payslip_item_id, v_run.payroll_batch_id, v_item.employee_id, v_actor_user_id);
      v_completed := v_completed + 1;
    exception when others then
      execute format('update %I.wcm_payslip_item set item_status = case when failure_count + 1 >= 3 then ''DEAD_LETTER'' else ''FAILED'' end, artifact_status = ''FAILED'', failure_count = failure_count + 1, last_error = $2, updated_at = timezone(''utc'', now()) where payslip_item_id = $1', v_schema_name)
        using v_item.payslip_item_id, sqlerrm;
      perform public.platform_payroll_core_append_audit(v_schema_name, 'PAYSLIP_ITEM_FAILED', 'PAYROLL_CORE', jsonb_build_object('error', sqlerrm), v_payslip_run_id, v_item.payslip_item_id, v_run.payroll_batch_id, v_item.employee_id, v_actor_user_id);
      v_failed := v_failed + 1;
    end;
  end loop;

  execute format('update %I.wcm_payslip_run set run_status = case when exists (select 1 from %I.wcm_payslip_item where payslip_run_id = $1 and item_status in (''FAILED'', ''DEAD_LETTER'')) then ''FAILED'' else ''COMPLETED'' end, completed_at = case when not exists (select 1 from %I.wcm_payslip_item where payslip_run_id = $1 and item_status in (''FAILED'', ''DEAD_LETTER'')) then timezone(''utc'', now()) else completed_at end, updated_at = timezone(''utc'', now()) where payslip_run_id = $1', v_schema_name, v_schema_name, v_schema_name)
    using v_payslip_run_id;

  return public.platform_json_response(true,'OK','Payslip run processed.',jsonb_build_object('payslip_run_id', v_payslip_run_id,'completed_items', v_completed,'failed_items', v_failed));
exception when others then
  if v_schema_name is not null and v_payslip_run_id is not null then
    execute format('update %I.wcm_payslip_run set run_status = ''FAILED'', run_metadata = jsonb_build_object(''error'', $2), updated_at = timezone(''utc'', now()) where payslip_run_id = $1', v_schema_name)
      using v_payslip_run_id, sqlerrm;
  end if;
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_process_payslip_run_job.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_get_employee_payslip(p_params jsonb)
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
  v_record record;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_employee_id is null then return public.platform_json_response(false,'EMPLOYEE_ID_REQUIRED','employee_id is required.', '{}'::jsonb); end if;

  execute format(
    'select i.payslip_item_id, i.generated_document_id, i.render_payload, i.artifact_status, i.item_status, r.payslip_run_id, r.payroll_period
       from %I.wcm_payslip_item i
       join %I.wcm_payslip_run r on r.payslip_run_id = i.payslip_run_id
      where i.employee_id = $1
        and (case when $2 is null then true else r.payroll_period = $2 end)
      order by r.payroll_period desc, i.updated_at desc
      limit 1',
    v_schema_name,
    v_schema_name
  ) into v_record using v_employee_id, v_payroll_period;

  if v_record.payslip_item_id is null then return public.platform_json_response(false,'PAYSLIP_NOT_FOUND','No payslip was found for the employee and requested period.',jsonb_build_object('employee_id', v_employee_id,'payroll_period', v_payroll_period)); end if;

  return public.platform_json_response(true,'OK','Employee payslip resolved.',jsonb_build_object('employee_id', v_employee_id,'payroll_period', v_record.payroll_period,'payslip_run_id', v_record.payslip_run_id,'payslip_item_id', v_record.payslip_item_id,'generated_document_id', v_record.generated_document_id,'artifact_status', v_record.artifact_status,'item_status', v_record.item_status,'render_payload', v_record.render_payload));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_get_employee_payslip.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_get_payroll_batch_status(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_payroll_batch_id uuid := public.platform_try_uuid(p_params->>'payroll_batch_id');
  v_batch record;
  v_payslip record;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_payroll_batch_id is null then return public.platform_json_response(false,'PAYROLL_BATCH_ID_REQUIRED','payroll_batch_id is required.', '{}'::jsonb); end if;

  execute format('select payroll_batch_id, payroll_period, processing_type, batch_status, total_employees, processed_employees, failed_employees, summary_metrics, last_error, processed_at, finalized_at from %I.wcm_payroll_batch where payroll_batch_id = $1', v_schema_name)
    into v_batch using v_payroll_batch_id;
  if v_batch.payroll_batch_id is null then return public.platform_json_response(false,'PAYROLL_BATCH_NOT_FOUND','Payroll batch not found.',jsonb_build_object('payroll_batch_id', v_payroll_batch_id)); end if;

  execute format('select count(*)::integer as total_runs, count(*) filter (where run_status = ''COMPLETED'')::integer as completed_runs from %I.wcm_payslip_run where payroll_batch_id = $1', v_schema_name)
    into v_payslip using v_payroll_batch_id;

  return public.platform_json_response(true,'OK','Payroll batch status resolved.',jsonb_build_object(
    'payroll_batch_id', v_batch.payroll_batch_id,
    'payroll_period', v_batch.payroll_period,
    'processing_type', v_batch.processing_type,
    'batch_status', v_batch.batch_status,
    'total_employees', v_batch.total_employees,
    'processed_employees', v_batch.processed_employees,
    'failed_employees', v_batch.failed_employees,
    'summary_metrics', coalesce(v_batch.summary_metrics, '{}'::jsonb),
    'last_error', v_batch.last_error,
    'processed_at', v_batch.processed_at,
    'finalized_at', v_batch.finalized_at,
    'payslip_runs', jsonb_build_object('total_runs', coalesce(v_payslip.total_runs, 0), 'completed_runs', coalesce(v_payslip.completed_runs, 0))
  ));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_get_payroll_batch_status.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
