create or replace function public.platform_register_async_worker(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_worker_code text := lower(btrim(coalesce(p_params->>'worker_code', '')));
  v_module_code text := upper(btrim(coalesce(p_params->>'module_code', '')));
  v_dispatch_mode text := lower(btrim(coalesce(p_params->>'dispatch_mode', '')));
  v_handler_contract text := btrim(coalesce(p_params->>'handler_contract', ''));
  v_is_active boolean := case when p_params ? 'is_active' then (p_params->>'is_active')::boolean else true end;
  v_max_batch_size integer := greatest(coalesce((p_params->>'max_batch_size')::integer, 50), 1);
  v_default_lease_seconds integer := greatest(coalesce((p_params->>'default_lease_seconds')::integer, 120), 1);
  v_heartbeat_grace_seconds integer := greatest(coalesce((p_params->>'heartbeat_grace_seconds')::integer, greatest(v_default_lease_seconds, 180)), v_default_lease_seconds);
  v_retry_backoff_policy jsonb := coalesce(p_params->'retry_backoff_policy', '{}'::jsonb);
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
begin
  if v_worker_code = '' then
    return public.platform_json_response(false, 'WORKER_CODE_REQUIRED', 'worker_code is required.', '{}'::jsonb);
  end if;
  if v_module_code = '' then
    return public.platform_json_response(false, 'MODULE_CODE_REQUIRED', 'module_code is required.', '{}'::jsonb);
  end if;
  if v_dispatch_mode not in ('edge_worker', 'db_inline_handler') then
    return public.platform_json_response(false, 'INVALID_DISPATCH_MODE', 'dispatch_mode is invalid.', jsonb_build_object('dispatch_mode', v_dispatch_mode));
  end if;
  if v_handler_contract = '' then
    return public.platform_json_response(false, 'HANDLER_CONTRACT_REQUIRED', 'handler_contract is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_retry_backoff_policy) <> 'object' then
    return public.platform_json_response(false, 'INVALID_RETRY_BACKOFF_POLICY', 'retry_backoff_policy must be a JSON object.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  insert into public.platform_async_worker_registry (
    worker_code, module_code, dispatch_mode, handler_contract, is_active, max_batch_size,
    default_lease_seconds, heartbeat_grace_seconds, retry_backoff_policy, metadata, created_by
  ) values (
    v_worker_code, v_module_code, v_dispatch_mode, v_handler_contract, v_is_active, least(v_max_batch_size, 500),
    v_default_lease_seconds, v_heartbeat_grace_seconds, v_retry_backoff_policy, v_metadata, public.platform_resolve_actor()
  )
  on conflict (worker_code) do update
  set module_code = excluded.module_code,
      dispatch_mode = excluded.dispatch_mode,
      handler_contract = excluded.handler_contract,
      is_active = excluded.is_active,
      max_batch_size = excluded.max_batch_size,
      default_lease_seconds = excluded.default_lease_seconds,
      heartbeat_grace_seconds = excluded.heartbeat_grace_seconds,
      retry_backoff_policy = excluded.retry_backoff_policy,
      metadata = excluded.metadata,
      updated_at = timezone('utc', now());

  return public.platform_json_response(true, 'OK', 'Async worker registered.', jsonb_build_object(
    'worker_code', v_worker_code,
    'module_code', v_module_code,
    'dispatch_mode', v_dispatch_mode,
    'handler_contract', v_handler_contract,
    'is_active', v_is_active
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_async_worker.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_async_enqueue_job(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_worker_code text := lower(btrim(coalesce(p_params->>'worker_code', '')));
  v_job_type text := btrim(coalesce(p_params->>'job_type', ''));
  v_priority integer := coalesce((p_params->>'priority')::integer, 100);
  v_payload jsonb := coalesce(p_params->'payload', '{}'::jsonb);
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_idempotency_key text := nullif(btrim(coalesce(p_params->>'idempotency_key', '')), '');
  v_deduplication_key text := nullif(btrim(coalesce(p_params->>'deduplication_key', '')), '');
  v_origin_source text := btrim(coalesce(nullif(p_params->>'origin_source', ''), 'platform_async_enqueue_job'));
  v_available_at timestamptz := coalesce((p_params->>'available_at')::timestamptz, timezone('utc', now()));
  v_max_attempts integer := greatest(coalesce((p_params->>'max_attempts')::integer, 10), 1);
  v_worker public.platform_async_worker_registry%rowtype;
  v_gate jsonb;
  v_gate_details jsonb;
  v_schema_state jsonb;
  v_schema_details jsonb;
  v_existing public.platform_async_job%rowtype;
  v_inserted public.platform_async_job%rowtype;
  v_block_code text;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;
  if v_worker_code = '' then
    return public.platform_json_response(false, 'WORKER_CODE_REQUIRED', 'worker_code is required.', '{}'::jsonb);
  end if;
  if v_job_type = '' then
    return public.platform_json_response(false, 'JOB_TYPE_REQUIRED', 'job_type is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_payload) <> 'object' then
    return public.platform_json_response(false, 'INVALID_PAYLOAD', 'payload must be a JSON object.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  select * into v_worker
  from public.platform_async_worker_registry
  where worker_code = v_worker_code;

  if not found then
    return public.platform_json_response(false, 'WORKER_NOT_REGISTERED', 'Worker route is not registered.', jsonb_build_object('worker_code', v_worker_code));
  end if;
  if v_worker.is_active = false then
    return public.platform_json_response(false, 'WORKER_ROUTE_DISABLED', 'Worker route is disabled.', jsonb_build_object('worker_code', v_worker_code));
  end if;

  v_gate := public.platform_get_tenant_access_gate(jsonb_build_object('tenant_id', v_tenant_id));
  if coalesce((v_gate->>'success')::boolean, false) = false then
    return v_gate;
  end if;
  v_gate_details := coalesce(v_gate->'details', '{}'::jsonb);
  if coalesce((v_gate_details->>'ready_for_routing')::boolean, false) = false then
    return public.platform_json_response(false, 'TENANT_NOT_READY_FOR_ROUTING', 'Tenant is not ready for routing.', v_gate_details);
  end if;
  if coalesce((v_gate_details->>'background_processing_allowed')::boolean, false) = false then
    v_block_code := case coalesce(v_gate_details->>'access_state', '')
      when 'disabled' then 'TENANT_DISABLED'
      when 'terminated' then 'TENANT_TERMINATED'
      else 'TENANT_BACKGROUND_BLOCKED_DORMANT'
    end;
    return public.platform_json_response(false, v_block_code, 'Background processing is blocked for the tenant.', v_gate_details);
  end if;

  v_schema_state := public.platform_get_tenant_schema_state(jsonb_build_object('tenant_id', v_tenant_id));
  if coalesce((v_schema_state->>'success')::boolean, false) = false then
    return v_schema_state;
  end if;
  v_schema_details := coalesce(v_schema_state->'details', '{}'::jsonb);
  if coalesce((v_schema_details->>'schema_exists')::boolean, false) = false or nullif(v_schema_details->>'schema_name', '') is null then
    return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_AVAILABLE', 'Tenant schema is not available.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_idempotency_key is not null then
    select * into v_existing
    from public.platform_async_job
    where tenant_id = v_tenant_id
      and worker_code = v_worker_code
      and idempotency_key = v_idempotency_key
    limit 1;
    if found then
      return public.platform_json_response(true, 'OK', 'Async job already exists for the idempotency key.', jsonb_build_object(
        'job_id', v_existing.job_id, 'job_state', v_existing.job_state, 'worker_code', v_existing.worker_code,
        'module_code', v_existing.module_code, 'tenant_id', v_existing.tenant_id, 'tenant_schema', v_existing.tenant_schema
      ));
    end if;
  end if;

  if v_deduplication_key is not null then
    select * into v_existing
    from public.platform_async_job
    where tenant_id = v_tenant_id
      and worker_code = v_worker_code
      and deduplication_key = v_deduplication_key
      and job_state in ('queued', 'claimed', 'running', 'retry_wait')
    limit 1;
    if found then
      return public.platform_json_response(true, 'OK', 'Active async job already exists for the deduplication key.', jsonb_build_object(
        'job_id', v_existing.job_id, 'job_state', v_existing.job_state, 'worker_code', v_existing.worker_code,
        'module_code', v_existing.module_code, 'tenant_id', v_existing.tenant_id, 'tenant_schema', v_existing.tenant_schema
      ));
    end if;
  end if;

  insert into public.platform_async_job (
    tenant_id, tenant_schema, module_code, worker_code, job_type, job_state, dispatch_mode, priority,
    payload, idempotency_key, deduplication_key, available_at, max_attempts, result_summary,
    origin_source, created_by, metadata
  ) values (
    v_tenant_id, v_schema_details->>'schema_name', v_worker.module_code, v_worker.worker_code, v_job_type, 'queued',
    v_worker.dispatch_mode, v_priority, v_payload, v_idempotency_key, v_deduplication_key, v_available_at,
    v_max_attempts, '{}'::jsonb, v_origin_source, public.platform_resolve_actor(), v_metadata
  )
  returning * into v_inserted;

  return public.platform_json_response(true, 'OK', 'Async job queued.', jsonb_build_object(
    'job_id', v_inserted.job_id,
    'tenant_id', v_inserted.tenant_id,
    'tenant_schema', v_inserted.tenant_schema,
    'module_code', v_inserted.module_code,
    'worker_code', v_inserted.worker_code,
    'job_type', v_inserted.job_type,
    'job_state', v_inserted.job_state,
    'dispatch_mode', v_inserted.dispatch_mode
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_async_enqueue_job.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_async_dispatch_due_jobs(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_worker_code text := nullif(lower(btrim(coalesce(p_params->>'worker_code', ''))), '');
  v_module_code text := nullif(upper(btrim(coalesce(p_params->>'module_code', ''))), '');
  v_dispatch_mode text := nullif(lower(btrim(coalesce(p_params->>'dispatch_mode', ''))), '');
  v_limit_workers integer := greatest(coalesce((p_params->>'limit_workers')::integer, 50), 1);
  v_rows jsonb;
begin
  if v_dispatch_mode is not null and v_dispatch_mode not in ('edge_worker', 'db_inline_handler') then
    return public.platform_json_response(false, 'INVALID_DISPATCH_MODE', 'dispatch_mode is invalid.', jsonb_build_object('dispatch_mode', v_dispatch_mode));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'worker_code', padrv.worker_code,
    'module_code', padrv.module_code,
    'dispatch_mode', padrv.dispatch_mode,
    'due_job_count', padrv.due_job_count,
    'oldest_due_at', padrv.oldest_due_at,
    'highest_priority', padrv.highest_priority
  ) order by padrv.highest_priority asc, padrv.oldest_due_at asc), '[]'::jsonb)
  into v_rows
  from (
    select *
    from public.platform_async_dispatch_readiness_view
    where (v_worker_code is null or worker_code = v_worker_code)
      and (v_module_code is null or module_code = v_module_code)
      and (v_dispatch_mode is null or dispatch_mode = v_dispatch_mode)
    order by highest_priority asc, oldest_due_at asc
    limit v_limit_workers
  ) padrv;

  return public.platform_json_response(true, 'OK', 'Dispatch readiness resolved.', jsonb_build_object(
    'workers', v_rows,
    'worker_count', jsonb_array_length(v_rows)
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_async_dispatch_due_jobs.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
