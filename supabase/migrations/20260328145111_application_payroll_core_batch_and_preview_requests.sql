set search_path = public, pg_temp;

create or replace function public.platform_request_payroll_batch(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_tenant_id uuid;
  v_payroll_period date := date_trunc('month', public.platform_payroll_core_try_date(p_params->>'payroll_period')::timestamp)::date;
  v_payroll_area_id uuid := public.platform_try_uuid(p_params->>'payroll_area_id');
  v_processing_type text := upper(coalesce(nullif(btrim(p_params->>'processing_type'), ''), 'FULL'));
  v_request_scope jsonb := coalesce(p_params->'request_scope', '{}'::jsonb);
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_batch_id uuid;
  v_enqueue_result jsonb;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');

  if v_payroll_period is null then return public.platform_json_response(false,'PAYROLL_PERIOD_REQUIRED','payroll_period is required.', '{}'::jsonb); end if;
  if v_payroll_area_id is null then return public.platform_json_response(false,'PAYROLL_AREA_ID_REQUIRED','payroll_area_id is required.', '{}'::jsonb); end if;
  if v_processing_type not in ('FULL', 'ADHOC', 'CORRECTION') then return public.platform_json_response(false,'PROCESSING_TYPE_NOT_ALLOWED','Use platform_request_payroll_preview(...) for preview simulations.',jsonb_build_object('processing_type', v_processing_type)); end if;
  if jsonb_typeof(v_request_scope) <> 'object' then return public.platform_json_response(false,'REQUEST_SCOPE_INVALID','request_scope must be a JSON object.', '{}'::jsonb); end if;
  if v_request_scope ? 'employee_ids' then
    if jsonb_typeof(v_request_scope->'employee_ids') <> 'array' then
      return public.platform_json_response(false,'REQUEST_SCOPE_EMPLOYEE_IDS_INVALID','request_scope.employee_ids must be a JSON array of employee ids.', '{}'::jsonb);
    end if;
    if exists (select 1 from jsonb_array_elements_text(v_request_scope->'employee_ids') as e(value) where public.platform_try_uuid(e.value) is null) then
      return public.platform_json_response(false,'REQUEST_SCOPE_EMPLOYEE_IDS_INVALID','request_scope.employee_ids must contain valid employee ids.', '{}'::jsonb);
    end if;
  end if;

  execute format('insert into %I.wcm_payroll_batch (payroll_period, payroll_area_id, processing_type, batch_status, request_scope, requested_by_actor_user_id) values ($1,$2,$3,''QUEUED'',$4,$5) returning payroll_batch_id', v_schema_name)
    into v_batch_id using v_payroll_period, v_payroll_area_id, v_processing_type, v_request_scope, v_actor_user_id;

  v_enqueue_result := public.platform_async_enqueue_job(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'worker_code', 'payroll_batch_worker',
    'job_type', 'process_payroll_batch',
    'priority', 85,
    'payload', jsonb_build_object('tenant_id', v_tenant_id, 'payroll_batch_id', v_batch_id, 'payroll_period', v_payroll_period, 'actor_user_id', v_actor_user_id),
    'deduplication_key', format('payroll:%s:%s', v_tenant_id::text, v_batch_id::text),
    'origin_source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_request_payroll_batch'),
    'metadata', jsonb_build_object('slice', 'PAYROLL_CORE', 'reason', 'payroll_batch_processing', 'processing_type', v_processing_type)
  ));
  if coalesce((v_enqueue_result->>'success')::boolean, false) is not true then
    execute format('update %I.wcm_payroll_batch set batch_status = ''FAILED'', last_error = $2, updated_at = timezone(''utc'', now()) where payroll_batch_id = $1', v_schema_name)
      using v_batch_id, coalesce(v_enqueue_result->>'message', v_enqueue_result::text);
    return v_enqueue_result;
  end if;

  execute format('update %I.wcm_payroll_batch set batch_status = ''PROCESSING'', updated_at = timezone(''utc'', now()) where payroll_batch_id = $1', v_schema_name) using v_batch_id;

  return public.platform_json_response(true,'OK','Payroll batch queued for processing.',jsonb_build_object('payroll_batch_id', v_batch_id,'payroll_period', v_payroll_period,'processing_type', v_processing_type,'batch_status', 'PROCESSING','enqueued_job_id', v_enqueue_result->'details'->>'job_id'));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_request_payroll_batch.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

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
    'gross_earnings', coalesce((select sum(calculated_amount) from public.platform_rm_payroll_result_summary where payroll_batch_id = v_payroll_batch_id), 0),
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
$function$;

create or replace function public.platform_finalize_payroll_batch(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_payroll_batch_id uuid := public.platform_try_uuid(p_params->>'payroll_batch_id');
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_batch record;
  v_stale_count bigint := 0;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_payroll_batch_id is null then return public.platform_json_response(false,'PAYROLL_BATCH_ID_REQUIRED','payroll_batch_id is required.', '{}'::jsonb); end if;

  execute format('select payroll_batch_id, payroll_period, processing_type, batch_status from %I.wcm_payroll_batch where payroll_batch_id = $1 for update', v_schema_name) into v_batch using v_payroll_batch_id;
  if v_batch.payroll_batch_id is null then return public.platform_json_response(false,'PAYROLL_BATCH_NOT_FOUND','Payroll batch not found.',jsonb_build_object('payroll_batch_id', v_payroll_batch_id)); end if;
  if v_batch.batch_status <> 'PROCESSED' then return public.platform_json_response(false,'PAYROLL_BATCH_NOT_FINALIZABLE','Only PROCESSED payroll batches can be finalized.',jsonb_build_object('payroll_batch_id', v_payroll_batch_id,'batch_status', v_batch.batch_status)); end if;
  if v_batch.processing_type = 'PREVIEW_SIMULATION' then return public.platform_json_response(false,'PREVIEW_BATCH_NOT_FINALIZABLE','Preview payroll batches cannot be finalized.',jsonb_build_object('payroll_batch_id', v_payroll_batch_id)); end if;

  execute format('select count(*) from %I.tps_employee_period_summary s where s.payroll_period = $1 and s.is_stale = true and exists (select 1 from %I.wcm_component_calculation_result r where r.payroll_batch_id = $2 and r.employee_id = s.employee_id)', v_schema_name, v_schema_name) into v_stale_count using v_batch.payroll_period, v_payroll_batch_id;
  if coalesce(v_stale_count, 0) > 0 then return public.platform_json_response(false,'TPS_STALE_SUMMARIES_PRESENT','TPS still reports stale summaries for the payroll period.',jsonb_build_object('payroll_period', v_batch.payroll_period,'stale_count', v_stale_count)); end if;

  execute format('update %I.wcm_payroll_batch set batch_status = ''FINALIZED'', finalized_by_actor_user_id = $2, finalized_at = timezone(''utc'', now()), updated_at = timezone(''utc'', now()) where payroll_batch_id = $1', v_schema_name)
    using v_payroll_batch_id, v_actor_user_id;

  return public.platform_json_response(true,'OK','Payroll batch finalized.',jsonb_build_object('payroll_batch_id', v_payroll_batch_id,'batch_status', 'FINALIZED'));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_finalize_payroll_batch.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_request_payroll_preview(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_tenant_id uuid;
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_payroll_period date := date_trunc('month', public.platform_payroll_core_try_date(p_params->>'payroll_period')::timestamp)::date;
  v_pay_structure_id uuid := public.platform_try_uuid(p_params->>'pay_structure_id');
  v_resolved_pay_structure_id uuid;
  v_preview_payroll_area_id uuid;
  v_request_payload jsonb := coalesce(p_params->'request_payload', '{}'::jsonb);
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_preview_id uuid;
  v_batch_id uuid;
  v_enqueue_result jsonb;
  v_override_inputs jsonb;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  if v_employee_id is null then return public.platform_json_response(false,'EMPLOYEE_ID_REQUIRED','employee_id is required.', '{}'::jsonb); end if;
  if v_payroll_period is null then return public.platform_json_response(false,'PAYROLL_PERIOD_REQUIRED','payroll_period is required.', '{}'::jsonb); end if;
  if jsonb_typeof(v_request_payload) <> 'object' then return public.platform_json_response(false,'REQUEST_PAYLOAD_INVALID','request_payload must be a JSON object.', '{}'::jsonb); end if;
  v_override_inputs := coalesce(v_request_payload->'override_inputs', '{}'::jsonb);
  if jsonb_typeof(v_override_inputs) <> 'object' then return public.platform_json_response(false,'OVERRIDE_INPUTS_INVALID','request_payload.override_inputs must be a JSON object when supplied.', '{}'::jsonb); end if;

  if v_pay_structure_id is not null then
    execute format('select pay_structure_id, payroll_area_id from %I.wcm_pay_structure where pay_structure_id = $1 and structure_status = ''ACTIVE''', v_schema_name)
      into v_resolved_pay_structure_id, v_preview_payroll_area_id using v_pay_structure_id;
    if v_resolved_pay_structure_id is null then
      return public.platform_json_response(false,'PAY_STRUCTURE_NOT_FOUND','Requested pay structure was not found or is not active for preview.',jsonb_build_object('pay_structure_id', v_pay_structure_id));
    end if;
  else
    execute format('select a.pay_structure_id, ps.payroll_area_id from %I.wcm_employee_pay_structure_assignment a join %I.wcm_pay_structure ps on ps.pay_structure_id = a.pay_structure_id where a.employee_id = $1 and a.assignment_status = ''ACTIVE'' and a.effective_from <= $2 and (a.effective_to is null or a.effective_to >= $2) order by a.effective_from desc, a.created_at desc limit 1', v_schema_name, v_schema_name)
      into v_resolved_pay_structure_id, v_preview_payroll_area_id using v_employee_id, v_payroll_period;
    if v_resolved_pay_structure_id is null then
      return public.platform_json_response(false,'PAY_STRUCTURE_ASSIGNMENT_NOT_FOUND','No active pay-structure assignment exists for payroll preview.',jsonb_build_object('employee_id', v_employee_id,'payroll_period', v_payroll_period));
    end if;
  end if;

  execute format('insert into %I.wcm_preview_simulation (employee_id, payroll_period, pay_structure_id, preview_status, request_payload, requested_by_actor_user_id) values ($1,$2,$3,''QUEUED'',$4,$5) returning preview_simulation_id', v_schema_name)
    into v_preview_id using v_employee_id, v_payroll_period, v_resolved_pay_structure_id, v_request_payload, v_actor_user_id;
  execute format('insert into %I.wcm_payroll_batch (payroll_period, payroll_area_id, processing_type, batch_status, request_scope, requested_by_actor_user_id) values ($1,$2,''PREVIEW_SIMULATION'',''QUEUED'',jsonb_build_object(''preview_simulation_id'', $3, ''pay_structure_id'', $4),$5) returning payroll_batch_id', v_schema_name)
    into v_batch_id using v_payroll_period, v_preview_payroll_area_id, v_preview_id, v_resolved_pay_structure_id, v_actor_user_id;
  execute format('update %I.wcm_preview_simulation set source_batch_id = $2, updated_at = timezone(''utc'', now()) where preview_simulation_id = $1', v_schema_name)
    using v_preview_id, v_batch_id;

  v_enqueue_result := public.platform_async_enqueue_job(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'worker_code', 'payroll_batch_worker',
    'job_type', 'preview_payroll_batch',
    'priority', 90,
    'payload', jsonb_build_object('tenant_id', v_tenant_id, 'payroll_batch_id', v_batch_id, 'payroll_period', v_payroll_period, 'actor_user_id', v_actor_user_id),
    'deduplication_key', format('payroll_preview:%s:%s', v_tenant_id::text, v_preview_id::text),
    'origin_source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_request_payroll_preview'),
    'metadata', jsonb_build_object('slice', 'PAYROLL_CORE', 'reason', 'preview_simulation')
  ));
  if coalesce((v_enqueue_result->>'success')::boolean, false) is not true then
    execute format('update %I.wcm_payroll_batch set batch_status = ''FAILED'', last_error = $2, updated_at = timezone(''utc'', now()) where payroll_batch_id = $1', v_schema_name)
      using v_batch_id, coalesce(v_enqueue_result->>'message', v_enqueue_result::text);
    execute format('update %I.wcm_preview_simulation set preview_status = ''FAILED'', result_snapshot = jsonb_build_object(''error'', $2), updated_at = timezone(''utc'', now()) where preview_simulation_id = $1', v_schema_name)
      using v_preview_id, coalesce(v_enqueue_result->>'message', v_enqueue_result::text);
    return v_enqueue_result;
  end if;

  execute format('update %I.wcm_payroll_batch set batch_status = ''PROCESSING'', updated_at = timezone(''utc'', now()) where payroll_batch_id = $1', v_schema_name)
    using v_batch_id;
  execute format('update %I.wcm_preview_simulation set preview_status = ''PROCESSING'', updated_at = timezone(''utc'', now()) where preview_simulation_id = $1', v_schema_name)
    using v_preview_id;

  return public.platform_json_response(true,'OK','Payroll preview queued.',jsonb_build_object('preview_simulation_id', v_preview_id,'payroll_batch_id', v_batch_id,'pay_structure_id', v_resolved_pay_structure_id,'enqueued_job_id', v_enqueue_result->'details'->>'job_id'));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_request_payroll_preview.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_get_payroll_preview(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_preview_simulation_id uuid := public.platform_try_uuid(p_params->>'preview_simulation_id');
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_payroll_period date := date_trunc('month', public.platform_payroll_core_try_date(p_params->>'payroll_period')::timestamp)::date;
  v_record record;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_preview_simulation_id is null and v_employee_id is null then
    return public.platform_json_response(false,'PREVIEW_LOOKUP_REQUIRED','preview_simulation_id or employee_id is required.', '{}'::jsonb);
  end if;

  execute format(
    'select preview_simulation_id,
            employee_id,
            payroll_period,
            pay_structure_id,
            source_batch_id,
            preview_status,
            request_payload,
            result_snapshot,
            requested_by_actor_user_id,
            completed_at,
            updated_at
       from %I.wcm_preview_simulation
      where (case when $1 is null then true else preview_simulation_id = $1 end)
        and (case when $2 is null then true else employee_id = $2 end)
        and (case when $3 is null then true else payroll_period = $3 end)
      order by case when preview_simulation_id = $1 then 0 else 1 end,
               payroll_period desc,
               updated_at desc,
               preview_simulation_id desc
      limit 1',
    v_schema_name
  ) into v_record using v_preview_simulation_id, v_employee_id, v_payroll_period;

  if v_record.preview_simulation_id is null then
    return public.platform_json_response(false,'PREVIEW_NOT_FOUND','No payroll preview was found for the requested lookup.',jsonb_build_object('preview_simulation_id', v_preview_simulation_id,'employee_id', v_employee_id,'payroll_period', v_payroll_period));
  end if;

  return public.platform_json_response(true,'OK','Payroll preview resolved.',jsonb_build_object(
    'preview_simulation_id', v_record.preview_simulation_id,
    'employee_id', v_record.employee_id,
    'payroll_period', v_record.payroll_period,
    'pay_structure_id', v_record.pay_structure_id,
    'source_batch_id', v_record.source_batch_id,
    'preview_status', v_record.preview_status,
    'request_payload', coalesce(v_record.request_payload, '{}'::jsonb),
    'result_snapshot', coalesce(v_record.result_snapshot, '{}'::jsonb),
    'requested_by_actor_user_id', v_record.requested_by_actor_user_id,
    'completed_at', v_record.completed_at,
    'updated_at', v_record.updated_at
  ));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_get_payroll_preview.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
