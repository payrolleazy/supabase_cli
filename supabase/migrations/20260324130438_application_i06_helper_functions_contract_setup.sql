create or replace function public.platform_exchange_write_event(p_params jsonb)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  insert into public.platform_export_event_log (
    export_job_id,
    contract_id,
    tenant_id,
    actor_user_id,
    event_type,
    severity,
    message,
    details
  ) values (
    public.platform_try_uuid(p_params->>'export_job_id'),
    public.platform_try_uuid(p_params->>'contract_id'),
    public.platform_try_uuid(p_params->>'tenant_id'),
    public.platform_try_uuid(p_params->>'actor_user_id'),
    btrim(coalesce(p_params->>'event_type', 'exchange_event')),
    lower(coalesce(nullif(p_params->>'severity', ''), 'info')),
    btrim(coalesce(p_params->>'message', 'exchange event')),
    coalesce(p_params->'details', '{}'::jsonb)
  );
end;
$function$;

create or replace function public.platform_i06_roles_overlap(
  p_actor_roles text[],
  p_allowed_roles text[]
)
returns boolean
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select case
    when coalesce(array_length(p_allowed_roles, 1), 0) = 0 then true
    else coalesce(p_actor_roles, '{}'::text[]) && p_allowed_roles
  end;
$function$;

create or replace function public.platform_i06_assert_actor_access(
  p_tenant_id uuid,
  p_actor_user_id uuid,
  p_allowed_role_codes text[]
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_access_row public.platform_rm_actor_access_overview%rowtype;
begin
  if p_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id is required.', '{}'::jsonb);
  end if;
  if p_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
  end if;

  select *
  into v_access_row
  from public.platform_rm_actor_access_overview
  where tenant_id = p_tenant_id
    and actor_user_id = p_actor_user_id
    and membership_status = 'active'
    and routing_status = 'enabled'
    and client_access_allowed = true
  order by is_default_tenant desc
  limit 1;

  if not found then
    return public.platform_json_response(false, 'ACCESS_DENIED', 'Actor does not have active tenant access.', jsonb_build_object(
      'tenant_id', p_tenant_id,
      'actor_user_id', p_actor_user_id
    ));
  end if;

  if not public.platform_i06_roles_overlap(v_access_row.active_role_codes, p_allowed_role_codes) then
    return public.platform_json_response(false, 'INSUFFICIENT_ROLE', 'Actor role is not permitted for this exchange contract.', jsonb_build_object(
      'tenant_id', p_tenant_id,
      'actor_user_id', p_actor_user_id,
      'allowed_role_codes', to_jsonb(coalesce(p_allowed_role_codes, '{}'::text[])),
      'active_role_codes', to_jsonb(coalesce(v_access_row.active_role_codes, '{}'::text[]))
    ));
  end if;

  return public.platform_json_response(true, 'OK', 'Actor access validated for exchange contract.', jsonb_build_object(
    'tenant_id', v_access_row.tenant_id,
    'tenant_code', v_access_row.tenant_code,
    'schema_name', v_access_row.schema_name,
    'actor_user_id', v_access_row.actor_user_id,
    'access_state', v_access_row.access_state,
    'active_role_codes', to_jsonb(coalesce(v_access_row.active_role_codes, '{}'::text[]))
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_i06_assert_actor_access.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_exchange_contract(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_contract_code text := lower(btrim(coalesce(p_params->>'contract_code', '')));
  v_direction text := lower(coalesce(nullif(p_params->>'direction', ''), ''));
  v_contract_label text := nullif(btrim(coalesce(p_params->>'contract_label', '')), '');
  v_owner_module_code text := lower(btrim(coalesce(p_params->>'owner_module_code', '')));
  v_entity_code text := lower(btrim(coalesce(p_params->>'entity_code', '')));
  v_worker_code text := lower(btrim(coalesce(p_params->>'worker_code', '')));
  v_source_operation_code text := lower(nullif(btrim(coalesce(p_params->>'source_operation_code', '')), ''));
  v_target_operation_code text := lower(nullif(btrim(coalesce(p_params->>'target_operation_code', '')), ''));
  v_join_profile_code text := lower(nullif(btrim(coalesce(p_params->>'join_profile_code', '')), ''));
  v_template_mode text := lower(coalesce(nullif(p_params->>'template_mode', ''), 'i04_descriptor'));
  v_upload_document_class_code text := lower(nullif(btrim(coalesce(p_params->>'upload_document_class_code', '')), ''));
  v_artifact_document_class_code text := lower(nullif(btrim(coalesce(p_params->>'artifact_document_class_code', '')), ''));
  v_artifact_bucket_code text := lower(nullif(btrim(coalesce(p_params->>'artifact_bucket_code', '')), ''));
  v_contract_status text := lower(coalesce(nullif(p_params->>'contract_status', ''), 'active'));
  v_validation_profile jsonb := coalesce(p_params->'validation_profile', '{}'::jsonb);
  v_delivery_profile jsonb := coalesce(p_params->'delivery_profile', '{}'::jsonb);
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_created_by uuid := coalesce(public.platform_try_uuid(p_params->>'created_by'), public.platform_resolve_actor());
  v_allowed_role_codes text[];
  v_accepted_file_formats text[];
  v_missing_role_codes text[];
  v_entity public.platform_extensible_entity_registry%rowtype;
  v_worker public.platform_async_worker_registry%rowtype;
  v_artifact_document_class public.platform_document_class%rowtype;
  v_contract public.platform_exchange_contract%rowtype;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Exchange-contract registration is restricted to internal callers.', '{}'::jsonb);
  end if;
  if v_contract_code = '' then
    return public.platform_json_response(false, 'CONTRACT_CODE_REQUIRED', 'contract_code is required.', '{}'::jsonb);
  end if;
  if v_direction not in ('import', 'export') then
    return public.platform_json_response(false, 'INVALID_DIRECTION', 'direction is invalid.', jsonb_build_object('direction', v_direction));
  end if;
  if v_contract_label is null then
    return public.platform_json_response(false, 'CONTRACT_LABEL_REQUIRED', 'contract_label is required.', '{}'::jsonb);
  end if;
  if v_owner_module_code = '' then
    return public.platform_json_response(false, 'OWNER_MODULE_CODE_REQUIRED', 'owner_module_code is required.', '{}'::jsonb);
  end if;
  if v_entity_code = '' then
    return public.platform_json_response(false, 'ENTITY_CODE_REQUIRED', 'entity_code is required.', '{}'::jsonb);
  end if;
  if v_worker_code = '' then
    return public.platform_json_response(false, 'WORKER_CODE_REQUIRED', 'worker_code is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_validation_profile) <> 'object' or jsonb_typeof(v_delivery_profile) <> 'object' or jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'validation_profile, delivery_profile, and metadata must be JSON objects.', '{}'::jsonb);
  end if;

  v_allowed_role_codes := public.platform_jsonb_text_array(p_params->'allowed_role_codes');
  v_accepted_file_formats := public.platform_jsonb_text_array(p_params->'accepted_file_formats');
  if v_allowed_role_codes is null or v_accepted_file_formats is null then
    return public.platform_json_response(false, 'INVALID_TEXT_ARRAY', 'allowed_role_codes and accepted_file_formats must be JSON arrays of text.', '{}'::jsonb);
  end if;

  select * into v_entity from public.platform_extensible_entity_registry where entity_code = v_entity_code and entity_status = 'active';
  if not found then
    return public.platform_json_response(false, 'ENTITY_NOT_FOUND', 'Active extensible entity not found.', jsonb_build_object('entity_code', v_entity_code));
  end if;

  select * into v_worker from public.platform_async_worker_registry where worker_code = v_worker_code and is_active = true;
  if not found then
    return public.platform_json_response(false, 'WORKER_NOT_REGISTERED', 'Active async worker not found.', jsonb_build_object('worker_code', v_worker_code));
  end if;

  if v_join_profile_code is not null and not exists (
    select 1 from public.platform_extensible_join_profile
    where entity_id = v_entity.entity_id and tenant_id is null and join_profile_code = v_join_profile_code and profile_status = 'active'
  ) then
    return public.platform_json_response(false, 'JOIN_PROFILE_NOT_FOUND', 'Active join profile not found for the entity.', jsonb_build_object('entity_code', v_entity_code, 'join_profile_code', v_join_profile_code));
  end if;

  if array_length(v_allowed_role_codes, 1) is not null then
    select coalesce(array_agg(r.role_code order by r.role_code), '{}'::text[])
    into v_missing_role_codes
    from unnest(v_allowed_role_codes) as r(role_code)
    where not exists (
      select 1 from public.platform_access_role par where par.role_code = r.role_code and par.role_status = 'active'
    );
    if array_length(v_missing_role_codes, 1) is not null then
      return public.platform_json_response(false, 'ALLOWED_ROLE_CODES_INVALID', 'One or more allowed_role_codes are not active roles.', jsonb_build_object('missing_role_codes', v_missing_role_codes));
    end if;
  end if;

  if v_direction = 'import' and v_upload_document_class_code is null then
    return public.platform_json_response(false, 'UPLOAD_DOCUMENT_CLASS_REQUIRED', 'upload_document_class_code is required for import contracts.', '{}'::jsonb);
  end if;
  if v_direction = 'export' and v_artifact_document_class_code is null then
    return public.platform_json_response(false, 'ARTIFACT_DOCUMENT_CLASS_REQUIRED', 'artifact_document_class_code is required for export contracts.', '{}'::jsonb);
  end if;

  if v_artifact_document_class_code is not null then
    select * into v_artifact_document_class from public.platform_document_class where document_class_code = v_artifact_document_class_code and class_status = 'active';
    if not found then
      return public.platform_json_response(false, 'ARTIFACT_DOCUMENT_CLASS_NOT_FOUND', 'Active artifact_document_class_code was not found.', jsonb_build_object('artifact_document_class_code', v_artifact_document_class_code));
    end if;
    if v_artifact_bucket_code is null then
      v_artifact_bucket_code := v_artifact_document_class.default_bucket_code;
    end if;
  end if;

  insert into public.platform_exchange_contract (
    contract_code, direction, contract_label, owner_module_code, entity_id, worker_code, source_operation_code, target_operation_code,
    join_profile_code, template_mode, accepted_file_formats, allowed_role_codes, upload_document_class_code,
    artifact_document_class_code, artifact_bucket_code, validation_profile, delivery_profile, contract_status, metadata, created_by
  ) values (
    v_contract_code, v_direction, v_contract_label, v_owner_module_code, v_entity.entity_id, v_worker.worker_code, v_source_operation_code,
    v_target_operation_code, v_join_profile_code, v_template_mode, v_accepted_file_formats, v_allowed_role_codes,
    v_upload_document_class_code, v_artifact_document_class_code, v_artifact_bucket_code, v_validation_profile,
    v_delivery_profile, v_contract_status, v_metadata, v_created_by
  ) on conflict (contract_code) do update
  set direction = excluded.direction,
      contract_label = excluded.contract_label,
      owner_module_code = excluded.owner_module_code,
      entity_id = excluded.entity_id,
      worker_code = excluded.worker_code,
      source_operation_code = excluded.source_operation_code,
      target_operation_code = excluded.target_operation_code,
      join_profile_code = excluded.join_profile_code,
      template_mode = excluded.template_mode,
      accepted_file_formats = excluded.accepted_file_formats,
      allowed_role_codes = excluded.allowed_role_codes,
      upload_document_class_code = excluded.upload_document_class_code,
      artifact_document_class_code = excluded.artifact_document_class_code,
      artifact_bucket_code = excluded.artifact_bucket_code,
      validation_profile = excluded.validation_profile,
      delivery_profile = excluded.delivery_profile,
      contract_status = excluded.contract_status,
      metadata = excluded.metadata,
      created_by = excluded.created_by,
      updated_at = timezone('utc', now())
  returning * into v_contract;

  perform public.platform_exchange_write_event(jsonb_build_object(
    'contract_id', v_contract.contract_id,
    'actor_user_id', v_created_by,
    'event_type', 'exchange_contract_registered',
    'message', 'Exchange contract upserted.',
    'details', jsonb_build_object('contract_code', v_contract.contract_code, 'direction', v_contract.direction, 'worker_code', v_contract.worker_code)
  ));

  return public.platform_json_response(true, 'OK', 'Exchange contract registered.', jsonb_build_object(
    'contract_id', v_contract.contract_id,
    'contract_code', v_contract.contract_code,
    'direction', v_contract.direction,
    'entity_code', v_entity.entity_code,
    'worker_code', v_contract.worker_code,
    'upload_document_class_code', v_contract.upload_document_class_code,
    'artifact_document_class_code', v_contract.artifact_document_class_code
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_exchange_contract.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_upsert_export_policy(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_contract_code text := lower(btrim(coalesce(p_params->>'contract_code', '')));
  v_default_retention_days integer := greatest(coalesce((p_params->>'default_retention_days')::integer, 7), 1);
  v_max_jobs_per_tenant_per_day integer := case when p_params ? 'max_jobs_per_tenant_per_day' then greatest((p_params->>'max_jobs_per_tenant_per_day')::integer, 1) else null end;
  v_max_active_jobs_per_tenant integer := case when p_params ? 'max_active_jobs_per_tenant' then greatest((p_params->>'max_active_jobs_per_tenant')::integer, 1) else null end;
  v_cleanup_enabled boolean := case when p_params ? 'cleanup_enabled' then (p_params->>'cleanup_enabled')::boolean else true end;
  v_policy_status text := lower(coalesce(nullif(p_params->>'policy_status', ''), 'active'));
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_created_by uuid := coalesce(public.platform_try_uuid(p_params->>'created_by'), public.platform_resolve_actor());
  v_contract public.platform_exchange_contract%rowtype;
  v_policy public.platform_export_policy%rowtype;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Export-policy writes are restricted to internal callers.', '{}'::jsonb);
  end if;
  if v_contract_code = '' then
    return public.platform_json_response(false, 'CONTRACT_CODE_REQUIRED', 'contract_code is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  select * into v_contract from public.platform_exchange_contract where contract_code = v_contract_code;
  if not found then
    return public.platform_json_response(false, 'CONTRACT_NOT_FOUND', 'Exchange contract not found.', jsonb_build_object('contract_code', v_contract_code));
  end if;
  if v_contract.direction <> 'export' then
    return public.platform_json_response(false, 'EXPORT_CONTRACT_REQUIRED', 'Export policy can only be attached to export contracts.', jsonb_build_object('contract_code', v_contract_code));
  end if;

  insert into public.platform_export_policy (
    contract_id, default_retention_days, max_jobs_per_tenant_per_day, max_active_jobs_per_tenant,
    cleanup_enabled, policy_status, metadata, created_by
  ) values (
    v_contract.contract_id, v_default_retention_days, v_max_jobs_per_tenant_per_day, v_max_active_jobs_per_tenant,
    v_cleanup_enabled, v_policy_status, v_metadata, v_created_by
  ) on conflict (contract_id) do update
  set default_retention_days = excluded.default_retention_days,
      max_jobs_per_tenant_per_day = excluded.max_jobs_per_tenant_per_day,
      max_active_jobs_per_tenant = excluded.max_active_jobs_per_tenant,
      cleanup_enabled = excluded.cleanup_enabled,
      policy_status = excluded.policy_status,
      metadata = excluded.metadata,
      created_by = excluded.created_by,
      updated_at = timezone('utc', now())
  returning * into v_policy;

  return public.platform_json_response(true, 'OK', 'Export policy upserted.', jsonb_build_object(
    'contract_code', v_contract.contract_code,
    'default_retention_days', v_policy.default_retention_days,
    'max_jobs_per_tenant_per_day', v_policy.max_jobs_per_tenant_per_day,
    'max_active_jobs_per_tenant', v_policy.max_active_jobs_per_tenant
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_upsert_export_policy.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_export_artifact(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_export_job_id uuid := public.platform_try_uuid(p_params->>'export_job_id');
  v_document_id uuid := public.platform_try_uuid(p_params->>'document_id');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_created_by uuid := coalesce(public.platform_try_uuid(p_params->>'created_by'), public.platform_resolve_actor());
  v_retention_expires_at timestamptz := case when p_params ? 'retention_expires_at' then (p_params->>'retention_expires_at')::timestamptz else null end;
  v_export_job public.platform_export_job%rowtype;
  v_policy public.platform_export_policy%rowtype;
  v_document public.platform_document_record%rowtype;
  v_artifact public.platform_export_artifact%rowtype;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Export-artifact registration is restricted to internal callers.', '{}'::jsonb);
  end if;
  if v_export_job_id is null then
    return public.platform_json_response(false, 'EXPORT_JOB_ID_REQUIRED', 'export_job_id is required.', '{}'::jsonb);
  end if;
  if v_document_id is null then
    return public.platform_json_response(false, 'DOCUMENT_ID_REQUIRED', 'document_id is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  select * into v_export_job from public.platform_export_job where export_job_id = v_export_job_id;
  if not found then
    return public.platform_json_response(false, 'EXPORT_JOB_NOT_FOUND', 'Export job not found.', jsonb_build_object('export_job_id', v_export_job_id));
  end if;

  select * into v_document from public.platform_document_record where document_id = v_document_id and document_status = 'active';
  if not found then
    return public.platform_json_response(false, 'DOCUMENT_NOT_FOUND', 'Active export document not found.', jsonb_build_object('document_id', v_document_id));
  end if;
  if v_document.tenant_id <> v_export_job.tenant_id then
    return public.platform_json_response(false, 'DOCUMENT_TENANT_MISMATCH', 'Export artifact document belongs to a different tenant.', jsonb_build_object('export_job_id', v_export_job_id, 'document_id', v_document_id));
  end if;

  select * into v_policy from public.platform_export_policy where contract_id = v_export_job.contract_id and policy_status = 'active';
  if v_retention_expires_at is null and found then
    v_retention_expires_at := timezone('utc', now()) + make_interval(days => v_policy.default_retention_days);
  end if;

  insert into public.platform_export_artifact (
    export_job_id, tenant_id, contract_id, document_id, bucket_code, storage_object_name, file_name, content_type,
    file_size_bytes, checksum_sha256, retention_expires_at, artifact_status, metadata, created_by
  ) values (
    v_export_job.export_job_id, v_export_job.tenant_id, v_export_job.contract_id, v_document.document_id, v_document.bucket_code,
    v_document.storage_object_name, v_document.original_file_name, v_document.content_type, v_document.file_size_bytes,
    v_document.checksum_sha256, v_retention_expires_at, 'active', v_metadata, v_created_by
  ) on conflict (export_job_id) do update
  set document_id = excluded.document_id,
      bucket_code = excluded.bucket_code,
      storage_object_name = excluded.storage_object_name,
      file_name = excluded.file_name,
      content_type = excluded.content_type,
      file_size_bytes = excluded.file_size_bytes,
      checksum_sha256 = excluded.checksum_sha256,
      retention_expires_at = excluded.retention_expires_at,
      artifact_status = excluded.artifact_status,
      metadata = excluded.metadata,
      created_by = excluded.created_by,
      updated_at = timezone('utc', now())
  returning * into v_artifact;

  update public.platform_export_job
  set artifact_document_id = v_document.document_id,
      job_status = 'completed',
      progress_percent = 100,
      completed_at = coalesce(completed_at, timezone('utc', now())),
      expires_at = coalesce(v_retention_expires_at, expires_at),
      result_summary = coalesce(result_summary, '{}'::jsonb) || jsonb_build_object('artifact_document_id', v_document.document_id, 'file_name', v_document.original_file_name),
      updated_at = timezone('utc', now())
  where export_job_id = v_export_job.export_job_id;

  perform public.platform_exchange_write_event(jsonb_build_object(
    'export_job_id', v_export_job.export_job_id,
    'contract_id', v_export_job.contract_id,
    'tenant_id', v_export_job.tenant_id,
    'actor_user_id', v_created_by,
    'event_type', 'export_artifact_registered',
    'message', 'Export artifact registered.',
    'details', jsonb_build_object('document_id', v_document.document_id, 'file_name', v_document.original_file_name)
  ));

  return public.platform_json_response(true, 'OK', 'Export artifact registered.', jsonb_build_object(
    'export_artifact_id', v_artifact.export_artifact_id,
    'export_job_id', v_export_job.export_job_id,
    'document_id', v_document.document_id,
    'file_name', v_artifact.file_name,
    'bucket_code', v_artifact.bucket_code,
    'storage_object_name', v_artifact.storage_object_name
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_export_artifact.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
