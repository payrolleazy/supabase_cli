create or replace function public.platform_request_export_job(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_contract_code text := lower(btrim(coalesce(p_params->>'contract_code', '')));
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_resolve_actor());
  v_request_payload jsonb := coalesce(p_params->'request_payload', '{}'::jsonb);
  v_idempotency_key text := nullif(btrim(coalesce(p_params->>'idempotency_key', '')), '');
  v_deduplication_key text := nullif(btrim(coalesce(p_params->>'deduplication_key', '')), '');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_contract public.platform_exchange_contract%rowtype;
  v_entity public.platform_extensible_entity_registry%rowtype;
  v_policy public.platform_export_policy%rowtype;
  v_access_result jsonb;
  v_existing public.platform_export_job%rowtype;
  v_enqueue_result jsonb;
  v_job_id uuid;
  v_active_count integer;
  v_daily_count integer;
  v_export_job public.platform_export_job%rowtype;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;
  if v_contract_code = '' then
    return public.platform_json_response(false, 'CONTRACT_CODE_REQUIRED', 'contract_code is required.', '{}'::jsonb);
  end if;
  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_request_payload) <> 'object' or jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_JSON_OBJECT', 'request_payload and metadata must be JSON objects.', '{}'::jsonb);
  end if;

  select * into v_contract from public.platform_exchange_contract where contract_code = v_contract_code and direction = 'export' and contract_status = 'active';
  if not found then
    return public.platform_json_response(false, 'EXPORT_CONTRACT_NOT_FOUND', 'Active export contract not found.', jsonb_build_object('contract_code', v_contract_code));
  end if;

  select * into v_entity from public.platform_extensible_entity_registry where entity_id = v_contract.entity_id;
  v_access_result := public.platform_i06_assert_actor_access(v_tenant_id, v_actor_user_id, v_contract.allowed_role_codes);
  if not coalesce((v_access_result->>'success')::boolean, false) then
    return v_access_result;
  end if;

  if v_idempotency_key is not null then
    select * into v_existing from public.platform_export_job where tenant_id = v_tenant_id and contract_id = v_contract.contract_id and idempotency_key = v_idempotency_key limit 1;
    if found then
      return public.platform_json_response(true, 'OK', 'Export job already exists for the idempotency key.', jsonb_build_object('export_job_id', v_existing.export_job_id, 'job_id', v_existing.job_id, 'job_status', v_existing.job_status));
    end if;
  end if;

  select * into v_policy from public.platform_export_policy where contract_id = v_contract.contract_id and policy_status = 'active';
  if found and v_policy.max_active_jobs_per_tenant is not null then
    select count(*) into v_active_count from public.platform_export_job where tenant_id = v_tenant_id and contract_id = v_contract.contract_id and job_status in ('queued', 'running');
    if v_active_count >= v_policy.max_active_jobs_per_tenant then
      return public.platform_json_response(false, 'EXPORT_QUOTA_EXCEEDED', 'Maximum active export jobs for the tenant has been reached.', jsonb_build_object('max_active_jobs_per_tenant', v_policy.max_active_jobs_per_tenant));
    end if;
  end if;
  if found and v_policy.max_jobs_per_tenant_per_day is not null then
    select count(*) into v_daily_count from public.platform_export_job where tenant_id = v_tenant_id and contract_id = v_contract.contract_id and created_at >= date_trunc('day', timezone('utc', now()));
    if v_daily_count >= v_policy.max_jobs_per_tenant_per_day then
      return public.platform_json_response(false, 'EXPORT_DAILY_QUOTA_EXCEEDED', 'Daily export quota for the tenant has been reached.', jsonb_build_object('max_jobs_per_tenant_per_day', v_policy.max_jobs_per_tenant_per_day));
    end if;
  end if;

  v_enqueue_result := public.platform_async_enqueue_job(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'worker_code', v_contract.worker_code,
    'job_type', 'export_generate',
    'payload', jsonb_build_object(
      'contract_code', v_contract.contract_code,
      'entity_code', v_entity.entity_code,
      'source_operation_code', v_contract.source_operation_code,
      'join_profile_code', v_contract.join_profile_code,
      'request_payload', v_request_payload,
      'requested_by_actor_user_id', v_actor_user_id
    ),
    'idempotency_key', v_idempotency_key,
    'deduplication_key', v_deduplication_key,
    'origin_source', 'I06_EXPORT_REQUEST',
    'metadata', v_metadata || jsonb_build_object('contract_code', v_contract.contract_code, 'tenant_id', v_tenant_id)
  ));

  if not coalesce((v_enqueue_result->>'success')::boolean, false) then
    return v_enqueue_result;
  end if;

  v_job_id := public.platform_try_uuid(v_enqueue_result->'details'->>'job_id');
  if v_job_id is null then
    return public.platform_json_response(false, 'ASYNC_JOB_ID_MISSING', 'platform_async_enqueue_job did not return job_id.', v_enqueue_result);
  end if;

  select * into v_existing from public.platform_export_job where job_id = v_job_id limit 1;
  if found then
    return public.platform_json_response(true, 'OK', 'Export job already exists for the queued async job.', jsonb_build_object('export_job_id', v_existing.export_job_id, 'job_id', v_existing.job_id, 'job_status', v_existing.job_status));
  end if;

  insert into public.platform_export_job (
    tenant_id, contract_id, requested_by_actor_user_id, job_id, idempotency_key, deduplication_key,
    request_payload, job_status, progress_percent, result_summary, error_details
  ) values (
    v_tenant_id, v_contract.contract_id, v_actor_user_id, v_job_id, v_idempotency_key, v_deduplication_key,
    v_request_payload, 'queued', 0, '{}'::jsonb, '{}'::jsonb
  ) returning * into v_export_job;

  perform public.platform_exchange_write_event(jsonb_build_object(
    'export_job_id', v_export_job.export_job_id,
    'contract_id', v_contract.contract_id,
    'tenant_id', v_tenant_id,
    'actor_user_id', v_actor_user_id,
    'event_type', 'export_job_requested',
    'message', 'Export job requested.',
    'details', jsonb_build_object('export_job_id', v_export_job.export_job_id, 'job_id', v_job_id)
  ));

  return public.platform_json_response(true, 'OK', 'Export job requested.', jsonb_build_object('export_job_id', v_export_job.export_job_id, 'job_id', v_job_id, 'job_status', v_export_job.job_status));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_request_export_job.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_get_export_delivery_descriptor(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_export_job_id uuid := public.platform_try_uuid(p_params->>'export_job_id');
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_resolve_actor());
  v_export_job public.platform_export_job%rowtype;
  v_contract public.platform_exchange_contract%rowtype;
  v_artifact public.platform_export_artifact%rowtype;
  v_access_result jsonb;
  v_document_result jsonb;
begin
  if v_export_job_id is null then
    return public.platform_json_response(false, 'EXPORT_JOB_ID_REQUIRED', 'export_job_id is required.', '{}'::jsonb);
  end if;
  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
  end if;

  select * into v_export_job from public.platform_export_job where export_job_id = v_export_job_id;
  if not found then
    return public.platform_json_response(false, 'EXPORT_JOB_NOT_FOUND', 'Export job not found.', jsonb_build_object('export_job_id', v_export_job_id));
  end if;
  if v_export_job.job_status <> 'completed' then
    return public.platform_json_response(false, 'EXPORT_ARTIFACT_NOT_READY', 'Export job is not completed yet.', jsonb_build_object('export_job_id', v_export_job_id, 'job_status', v_export_job.job_status));
  end if;

  select * into v_contract from public.platform_exchange_contract where contract_id = v_export_job.contract_id;
  v_access_result := public.platform_i06_assert_actor_access(v_export_job.tenant_id, v_actor_user_id, v_contract.allowed_role_codes);
  if not coalesce((v_access_result->>'success')::boolean, false) then
    return v_access_result;
  end if;

  select * into v_artifact from public.platform_export_artifact where export_job_id = v_export_job.export_job_id and artifact_status = 'active';
  if not found then
    return public.platform_json_response(false, 'EXPORT_ARTIFACT_NOT_FOUND', 'Active export artifact not found.', jsonb_build_object('export_job_id', v_export_job_id));
  end if;
  if v_artifact.document_id is null then
    return public.platform_json_response(false, 'EXPORT_ARTIFACT_DOCUMENT_REQUIRED', 'Export artifact must be backed by a governed document record.', jsonb_build_object('export_job_id', v_export_job_id));
  end if;

  v_document_result := public.platform_get_document_access_descriptor(jsonb_build_object('document_id', v_artifact.document_id, 'actor_user_id', v_actor_user_id));
  if not coalesce((v_document_result->>'success')::boolean, false) then
    return v_document_result;
  end if;

  return public.platform_json_response(true, 'OK', 'Export delivery descriptor resolved.', jsonb_build_object(
    'export_job_id', v_export_job.export_job_id,
    'tenant_id', v_export_job.tenant_id,
    'contract_code', v_contract.contract_code,
    'export_artifact_id', v_artifact.export_artifact_id,
    'artifact_status', v_artifact.artifact_status,
    'file_name', v_artifact.file_name,
    'content_type', v_artifact.content_type,
    'retention_expires_at', v_artifact.retention_expires_at,
    'document_access', v_document_result->'details'
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_get_export_delivery_descriptor.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

revoke all on public.platform_exchange_contract from public, anon, authenticated;
revoke all on public.platform_import_session from public, anon, authenticated;
revoke all on public.platform_import_staging_row from public, anon, authenticated;
revoke all on public.platform_import_run from public, anon, authenticated;
revoke all on public.platform_import_validation_summary from public, anon, authenticated;
revoke all on public.platform_export_policy from public, anon, authenticated;
revoke all on public.platform_export_job from public, anon, authenticated;
revoke all on public.platform_export_artifact from public, anon, authenticated;
revoke all on public.platform_export_event_log from public, anon, authenticated;
revoke all on public.platform_rm_exchange_contract_catalog from public, anon, authenticated;
revoke all on public.platform_rm_import_session_overview from public, anon, authenticated;
revoke all on public.platform_rm_import_validation_summary from public, anon, authenticated;
revoke all on public.platform_rm_export_job_overview from public, anon, authenticated;
revoke all on public.platform_rm_export_queue_health from public, anon, authenticated;

revoke all on function public.platform_exchange_write_event(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_i06_roles_overlap(text[], text[]) from public, anon, authenticated, service_role;
revoke all on function public.platform_i06_assert_actor_access(uuid, uuid, text[]) from public, anon, authenticated, service_role;
revoke all on function public.platform_register_exchange_contract(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_upsert_export_policy(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_register_export_artifact(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_get_exchange_contract(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_issue_import_session(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_preview_import_session(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_commit_import_session(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_request_export_job(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_get_export_delivery_descriptor(jsonb) from public, anon, authenticated, service_role;

grant select on public.platform_rm_exchange_contract_catalog to service_role;
grant select on public.platform_rm_import_session_overview to service_role;
grant select on public.platform_rm_import_validation_summary to service_role;
grant select on public.platform_rm_export_job_overview to service_role;
grant select on public.platform_rm_export_queue_health to service_role;

grant execute on function public.platform_exchange_write_event(jsonb) to service_role;
grant execute on function public.platform_i06_assert_actor_access(uuid, uuid, text[]) to service_role;
grant execute on function public.platform_register_exchange_contract(jsonb) to service_role;
grant execute on function public.platform_upsert_export_policy(jsonb) to service_role;
grant execute on function public.platform_register_export_artifact(jsonb) to service_role;
grant execute on function public.platform_get_exchange_contract(jsonb) to service_role;
grant execute on function public.platform_issue_import_session(jsonb) to service_role;
grant execute on function public.platform_preview_import_session(jsonb) to service_role;
grant execute on function public.platform_commit_import_session(jsonb) to service_role;
grant execute on function public.platform_request_export_job(jsonb) to service_role;
grant execute on function public.platform_get_export_delivery_descriptor(jsonb) to service_role;;
