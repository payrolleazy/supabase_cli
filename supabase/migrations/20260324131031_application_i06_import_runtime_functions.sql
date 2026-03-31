create or replace function public.platform_get_exchange_contract(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_contract_code text := lower(btrim(coalesce(p_params->>'contract_code', '')));
  v_tenant_id uuid := coalesce(public.platform_try_uuid(p_params->>'tenant_id'), public.platform_current_tenant_id());
  v_include_template_descriptor boolean := case when p_params ? 'include_template_descriptor' then (p_params->>'include_template_descriptor')::boolean else true end;
  v_contract public.platform_exchange_contract%rowtype;
  v_entity public.platform_extensible_entity_registry%rowtype;
  v_template_result jsonb;
  v_template_descriptor jsonb := '{}'::jsonb;
begin
  if v_contract_code = '' then
    return public.platform_json_response(false, 'CONTRACT_CODE_REQUIRED', 'contract_code is required.', '{}'::jsonb);
  end if;

  select * into v_contract from public.platform_exchange_contract where contract_code = v_contract_code and contract_status = 'active';
  if not found then
    return public.platform_json_response(false, 'CONTRACT_NOT_FOUND', 'Active exchange contract not found.', jsonb_build_object('contract_code', v_contract_code));
  end if;

  select * into v_entity from public.platform_extensible_entity_registry where entity_id = v_contract.entity_id;
  if v_include_template_descriptor and v_contract.template_mode = 'i04_descriptor' then
    v_template_result := public.platform_get_extensible_template_descriptor(jsonb_build_object('entity_code', v_entity.entity_code, 'tenant_id', v_tenant_id));
    if not coalesce((v_template_result->>'success')::boolean, false) then
      return v_template_result;
    end if;
    v_template_descriptor := coalesce(v_template_result->'details', '{}'::jsonb);
  end if;

  return public.platform_json_response(true, 'OK', 'Exchange contract resolved.', jsonb_build_object(
    'contract_id', v_contract.contract_id,
    'contract_code', v_contract.contract_code,
    'direction', v_contract.direction,
    'contract_label', v_contract.contract_label,
    'owner_module_code', v_contract.owner_module_code,
    'entity_code', v_entity.entity_code,
    'entity_label', v_entity.entity_label,
    'worker_code', v_contract.worker_code,
    'source_operation_code', v_contract.source_operation_code,
    'target_operation_code', v_contract.target_operation_code,
    'join_profile_code', v_contract.join_profile_code,
    'template_mode', v_contract.template_mode,
    'accepted_file_formats', to_jsonb(v_contract.accepted_file_formats),
    'allowed_role_codes', to_jsonb(v_contract.allowed_role_codes),
    'upload_document_class_code', v_contract.upload_document_class_code,
    'artifact_document_class_code', v_contract.artifact_document_class_code,
    'artifact_bucket_code', v_contract.artifact_bucket_code,
    'validation_profile', v_contract.validation_profile,
    'delivery_profile', v_contract.delivery_profile,
    'template_descriptor', v_template_descriptor
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_get_exchange_contract.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_issue_import_session(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_contract_code text := lower(btrim(coalesce(p_params->>'contract_code', '')));
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_resolve_actor());
  v_source_file_name text := coalesce(nullif(btrim(p_params->>'source_file_name'), ''), nullif(btrim(p_params->>'original_file_name'), ''));
  v_content_type text := nullif(btrim(coalesce(p_params->>'content_type', '')), '');
  v_expected_size_bytes bigint := case when p_params ? 'expected_size_bytes' then (p_params->>'expected_size_bytes')::bigint else null end;
  v_idempotency_key text := nullif(btrim(coalesce(p_params->>'idempotency_key', '')), '');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_contract public.platform_exchange_contract%rowtype;
  v_access_result jsonb;
  v_existing public.platform_import_session%rowtype;
  v_issue_result jsonb;
  v_upload_intent_id uuid;
  v_file_extension text;
  v_session public.platform_import_session%rowtype;
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
  if v_source_file_name is null then
    return public.platform_json_response(false, 'SOURCE_FILE_NAME_REQUIRED', 'source_file_name is required.', '{}'::jsonb);
  end if;
  if v_content_type is null then
    return public.platform_json_response(false, 'CONTENT_TYPE_REQUIRED', 'content_type is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  select * into v_contract from public.platform_exchange_contract where contract_code = v_contract_code and direction = 'import' and contract_status = 'active';
  if not found then
    return public.platform_json_response(false, 'IMPORT_CONTRACT_NOT_FOUND', 'Active import contract not found.', jsonb_build_object('contract_code', v_contract_code));
  end if;

  v_access_result := public.platform_i06_assert_actor_access(v_tenant_id, v_actor_user_id, v_contract.allowed_role_codes);
  if not coalesce((v_access_result->>'success')::boolean, false) then
    return v_access_result;
  end if;

  if array_length(v_contract.accepted_file_formats, 1) is not null then
    v_file_extension := lower(nullif(substring(v_source_file_name from '\.([^.]+)$'), ''));
    if v_file_extension is null or not (v_file_extension = any(v_contract.accepted_file_formats)) then
      return public.platform_json_response(false, 'INVALID_FILE_FORMAT', 'File extension is not allowed for this import contract.', jsonb_build_object('contract_code', v_contract.contract_code, 'source_file_name', v_source_file_name, 'accepted_file_formats', to_jsonb(v_contract.accepted_file_formats)));
    end if;
  end if;

  if v_idempotency_key is not null then
    select * into v_existing from public.platform_import_session
    where tenant_id = v_tenant_id and contract_id = v_contract.contract_id and requested_by_actor_user_id = v_actor_user_id and idempotency_key = v_idempotency_key
    limit 1;
    if found then
      return public.platform_json_response(true, 'OK', 'Import session already exists for the idempotency key.', jsonb_build_object(
        'import_session_id', v_existing.import_session_id,
        'upload_intent_id', v_existing.upload_intent_id,
        'source_document_id', v_existing.source_document_id,
        'session_status', v_existing.session_status
      ));
    end if;
  end if;

  v_issue_result := public.platform_issue_document_upload_intent(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'document_class_code', v_contract.upload_document_class_code,
    'requested_by_actor_user_id', v_actor_user_id,
    'owner_actor_user_id', v_actor_user_id,
    'original_file_name', v_source_file_name,
    'content_type', v_content_type,
    'expected_size_bytes', v_expected_size_bytes,
    'metadata', jsonb_build_object('exchange_contract_code', v_contract.contract_code, 'exchange_direction', 'import') || v_metadata
  ));

  if not coalesce((v_issue_result->>'success')::boolean, false) then
    return v_issue_result;
  end if;

  v_upload_intent_id := public.platform_try_uuid(v_issue_result->'details'->>'upload_intent_id');
  if v_upload_intent_id is null then
    return public.platform_json_response(false, 'UPLOAD_INTENT_ID_MISSING', 'platform_issue_document_upload_intent did not return upload_intent_id.', v_issue_result);
  end if;

  insert into public.platform_import_session (
    contract_id, tenant_id, requested_by_actor_user_id, upload_intent_id, idempotency_key,
    source_file_name, content_type, expected_size_bytes, session_status, metadata
  ) values (
    v_contract.contract_id, v_tenant_id, v_actor_user_id, v_upload_intent_id, v_idempotency_key,
    v_source_file_name, v_content_type, v_expected_size_bytes, 'pending_upload', v_metadata
  ) returning * into v_session;

  perform public.platform_exchange_write_event(jsonb_build_object(
    'contract_id', v_contract.contract_id,
    'tenant_id', v_tenant_id,
    'actor_user_id', v_actor_user_id,
    'event_type', 'import_session_issued',
    'message', 'Import session issued.',
    'details', jsonb_build_object('import_session_id', v_session.import_session_id, 'upload_intent_id', v_session.upload_intent_id)
  ));

  return public.platform_json_response(true, 'OK', 'Import session issued.', jsonb_build_object(
    'import_session_id', v_session.import_session_id,
    'tenant_id', v_session.tenant_id,
    'contract_code', v_contract.contract_code,
    'upload_intent_id', v_session.upload_intent_id,
    'storage_object_name', v_issue_result->'details'->>'storage_object_name',
    'bucket_name', v_issue_result->'details'->>'bucket_name',
    'session_status', v_session.session_status
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_issue_import_session.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_preview_import_session(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_import_session_id uuid := public.platform_try_uuid(p_params->>'import_session_id');
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_resolve_actor());
  v_staged_rows jsonb := coalesce(p_params->'staged_rows', '[]'::jsonb);
  v_session public.platform_import_session%rowtype;
  v_contract public.platform_exchange_contract%rowtype;
  v_entity public.platform_extensible_entity_registry%rowtype;
  v_access_result jsonb;
  v_source_document_id uuid;
  v_row record;
  v_row_payload jsonb;
  v_validation_result jsonb;
  v_validation_messages jsonb;
  v_canonical_row jsonb;
  v_validation_status text;
  v_duplicate_key_field text;
  v_duplicate_key text;
  v_seen_duplicate_keys text[] := '{}'::text[];
  v_total_rows integer := 0;
  v_ready_rows integer := 0;
  v_invalid_rows integer := 0;
  v_duplicate_rows integer := 0;
  v_summary jsonb;
  v_next_status text;
begin
  if v_import_session_id is null then
    return public.platform_json_response(false, 'IMPORT_SESSION_ID_REQUIRED', 'import_session_id is required.', '{}'::jsonb);
  end if;
  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_staged_rows) <> 'array' then
    return public.platform_json_response(false, 'STAGED_ROWS_ARRAY_REQUIRED', 'staged_rows must be a JSON array.', '{}'::jsonb);
  end if;
  if jsonb_array_length(v_staged_rows) = 0 then
    return public.platform_json_response(false, 'STAGED_ROWS_REQUIRED', 'staged_rows must contain at least one row.', '{}'::jsonb);
  end if;

  select * into v_session from public.platform_import_session where import_session_id = v_import_session_id;
  if not found then
    return public.platform_json_response(false, 'IMPORT_SESSION_NOT_FOUND', 'Import session not found.', jsonb_build_object('import_session_id', v_import_session_id));
  end if;

  select * into v_contract from public.platform_exchange_contract where contract_id = v_session.contract_id;
  select * into v_entity from public.platform_extensible_entity_registry where entity_id = v_contract.entity_id;

  v_access_result := public.platform_i06_assert_actor_access(v_session.tenant_id, v_actor_user_id, v_contract.allowed_role_codes);
  if not coalesce((v_access_result->>'success')::boolean, false) then
    return v_access_result;
  end if;

  if v_session.session_status in ('committing', 'committed', 'cancelled', 'expired') then
    return public.platform_json_response(false, 'IMPORT_SESSION_PREVIEW_BLOCKED', 'Import session cannot be previewed in its current state.', jsonb_build_object('import_session_id', v_session.import_session_id, 'session_status', v_session.session_status));
  end if;

  if v_session.source_document_id is null and v_session.upload_intent_id is not null then
    select document_id into v_source_document_id
    from public.platform_document_record
    where upload_intent_id = v_session.upload_intent_id
      and tenant_id = v_session.tenant_id
      and document_status = 'active'
    order by created_at desc
    limit 1;

    if v_source_document_id is not null then
      update public.platform_import_session
      set source_document_id = v_source_document_id,
          session_status = case when session_status = 'pending_upload' then 'uploaded' else session_status end,
          updated_at = timezone('utc', now())
      where import_session_id = v_session.import_session_id
      returning * into v_session;
    end if;
  end if;

  if v_session.source_document_id is null then
    return public.platform_json_response(false, 'SOURCE_DOCUMENT_NOT_READY', 'Source document is not yet available for preview.', jsonb_build_object('import_session_id', v_session.import_session_id, 'upload_intent_id', v_session.upload_intent_id));
  end if;

  v_duplicate_key_field := nullif(btrim(coalesce(v_contract.validation_profile->>'duplicate_key_field', '')), '');

  delete from public.platform_import_staging_row where import_session_id = v_session.import_session_id;
  delete from public.platform_import_validation_summary where import_session_id = v_session.import_session_id;

  for v_row in select value, ordinality from jsonb_array_elements(v_staged_rows) with ordinality as t(value, ordinality)
  loop
    v_total_rows := v_total_rows + 1;
    v_row_payload := v_row.value;
    v_validation_status := 'ready';
    v_validation_messages := '[]'::jsonb;
    v_canonical_row := '{}'::jsonb;
    v_duplicate_key := null;

    if jsonb_typeof(v_row_payload) <> 'object' then
      v_validation_status := 'invalid';
      v_validation_messages := jsonb_build_array(jsonb_build_object('reason', 'Row must be a JSON object.'));
    else
      v_validation_result := public.platform_validate_extensible_payload(jsonb_build_object(
        'entity_code', v_entity.entity_code,
        'tenant_id', v_session.tenant_id,
        'payload', v_row_payload,
        'allow_unknown_attributes', false
      ));
      if coalesce((v_validation_result->>'success')::boolean, false) then
        v_canonical_row := coalesce(v_validation_result->'details'->'normalized_payload', v_row_payload);
      else
        v_validation_status := 'invalid';
        v_canonical_row := coalesce(v_validation_result->'details'->'normalized_payload', '{}'::jsonb);
        v_validation_messages := case
          when jsonb_typeof(v_validation_result->'details'->'attribute_errors') = 'array' then v_validation_result->'details'->'attribute_errors'
          else jsonb_build_array(jsonb_build_object('reason', coalesce(v_validation_result->>'message', 'Payload validation failed.')))
        end;
      end if;
    end if;

    if v_validation_status = 'ready' and v_duplicate_key_field is not null then
      v_duplicate_key := nullif(btrim(coalesce(v_canonical_row->>v_duplicate_key_field, '')), '');
      if v_duplicate_key is not null then
        if v_duplicate_key = any(v_seen_duplicate_keys) then
          v_validation_status := 'duplicate';
          v_validation_messages := jsonb_build_array(jsonb_build_object('attribute_code', v_duplicate_key_field, 'reason', 'Duplicate key detected in preview batch.'));
        else
          v_seen_duplicate_keys := array_append(v_seen_duplicate_keys, v_duplicate_key);
        end if;
      end if;
    end if;

    if v_validation_status = 'ready' then
      v_ready_rows := v_ready_rows + 1;
    elsif v_validation_status = 'duplicate' then
      v_duplicate_rows := v_duplicate_rows + 1;
    else
      v_invalid_rows := v_invalid_rows + 1;
    end if;

    insert into public.platform_import_staging_row (
      import_session_id, tenant_id, source_row_number, raw_row, canonical_row, validation_status, validation_messages, duplicate_key, commit_result
    ) values (
      v_session.import_session_id, v_session.tenant_id, v_row.ordinality::integer, coalesce(v_row_payload, '{}'::jsonb),
      v_canonical_row, v_validation_status, v_validation_messages, v_duplicate_key, '{}'::jsonb
    );
  end loop;

  v_next_status := case when v_total_rows > 0 and v_invalid_rows = 0 and v_duplicate_rows = 0 then 'ready_to_commit' else 'preview_ready' end;
  v_summary := jsonb_build_object(
    'import_session_id', v_session.import_session_id,
    'contract_code', v_contract.contract_code,
    'entity_code', v_entity.entity_code,
    'total_rows', v_total_rows,
    'ready_rows', v_ready_rows,
    'invalid_rows', v_invalid_rows,
    'duplicate_rows', v_duplicate_rows,
    'session_status', v_next_status
  );

  insert into public.platform_import_validation_summary (
    import_session_id, tenant_id, total_rows, ready_rows, invalid_rows, duplicate_rows, committed_rows, failed_rows, summary_payload
  ) values (
    v_session.import_session_id, v_session.tenant_id, v_total_rows, v_ready_rows, v_invalid_rows, v_duplicate_rows, 0, 0, v_summary
  );

  update public.platform_import_session
  set session_status = v_next_status,
      staging_row_count = v_total_rows,
      ready_row_count = v_ready_rows,
      invalid_row_count = v_invalid_rows,
      duplicate_row_count = v_duplicate_rows,
      preview_summary = v_summary,
      validation_summary = v_summary,
      updated_at = timezone('utc', now())
  where import_session_id = v_session.import_session_id;

  perform public.platform_exchange_write_event(jsonb_build_object(
    'contract_id', v_contract.contract_id,
    'tenant_id', v_session.tenant_id,
    'actor_user_id', v_actor_user_id,
    'event_type', 'import_preview_generated',
    'message', 'Import preview generated.',
    'details', v_summary
  ));

  return public.platform_json_response(true, 'OK', 'Import preview generated.', v_summary);
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_preview_import_session.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_commit_import_session(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_import_session_id uuid := public.platform_try_uuid(p_params->>'import_session_id');
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_resolve_actor());
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_session public.platform_import_session%rowtype;
  v_contract public.platform_exchange_contract%rowtype;
  v_entity public.platform_extensible_entity_registry%rowtype;
  v_access_result jsonb;
  v_existing_run public.platform_import_run%rowtype;
  v_run_no integer;
  v_enqueue_result jsonb;
  v_job_id uuid;
  v_run public.platform_import_run%rowtype;
begin
  if v_import_session_id is null then
    return public.platform_json_response(false, 'IMPORT_SESSION_ID_REQUIRED', 'import_session_id is required.', '{}'::jsonb);
  end if;
  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  select * into v_session from public.platform_import_session where import_session_id = v_import_session_id;
  if not found then
    return public.platform_json_response(false, 'IMPORT_SESSION_NOT_FOUND', 'Import session not found.', jsonb_build_object('import_session_id', v_import_session_id));
  end if;

  select * into v_contract from public.platform_exchange_contract where contract_id = v_session.contract_id;
  select * into v_entity from public.platform_extensible_entity_registry where entity_id = v_contract.entity_id;

  v_access_result := public.platform_i06_assert_actor_access(v_session.tenant_id, v_actor_user_id, v_contract.allowed_role_codes);
  if not coalesce((v_access_result->>'success')::boolean, false) then
    return v_access_result;
  end if;

  if v_session.session_status = 'committing' then
    select * into v_existing_run from public.platform_import_run where import_session_id = v_session.import_session_id order by requested_at desc limit 1;
    if found then
      return public.platform_json_response(true, 'OK', 'Import commit is already queued.', jsonb_build_object('import_run_id', v_existing_run.import_run_id, 'job_id', v_existing_run.job_id, 'run_status', v_existing_run.run_status));
    end if;
  end if;

  if v_session.source_document_id is null then
    return public.platform_json_response(false, 'SOURCE_DOCUMENT_NOT_READY', 'Source document is not available for commit.', jsonb_build_object('import_session_id', v_session.import_session_id));
  end if;

  if v_session.ready_row_count <= 0 or v_session.invalid_row_count > 0 or v_session.duplicate_row_count > 0 or v_session.session_status <> 'ready_to_commit' then
    return public.platform_json_response(false, 'IMPORT_SESSION_NOT_READY', 'Import session is not ready to commit.', jsonb_build_object(
      'import_session_id', v_session.import_session_id,
      'session_status', v_session.session_status,
      'ready_row_count', v_session.ready_row_count,
      'invalid_row_count', v_session.invalid_row_count,
      'duplicate_row_count', v_session.duplicate_row_count
    ));
  end if;

  select coalesce(max(run_no), 0) + 1 into v_run_no from public.platform_import_run where import_session_id = v_session.import_session_id;

  v_enqueue_result := public.platform_async_enqueue_job(jsonb_build_object(
    'tenant_id', v_session.tenant_id,
    'worker_code', v_contract.worker_code,
    'job_type', 'import_commit',
    'payload', jsonb_build_object(
      'import_session_id', v_session.import_session_id,
      'contract_code', v_contract.contract_code,
      'entity_code', v_entity.entity_code,
      'target_operation_code', v_contract.target_operation_code,
      'requested_by_actor_user_id', v_actor_user_id
    ),
    'idempotency_key', 'i06-import-' || v_session.import_session_id::text || '-' || v_run_no::text,
    'origin_source', 'I06_IMPORT_COMMIT',
    'metadata', v_metadata || jsonb_build_object('contract_code', v_contract.contract_code, 'import_session_id', v_session.import_session_id)
  ));

  if not coalesce((v_enqueue_result->>'success')::boolean, false) then
    return v_enqueue_result;
  end if;

  v_job_id := public.platform_try_uuid(v_enqueue_result->'details'->>'job_id');
  if v_job_id is null then
    return public.platform_json_response(false, 'ASYNC_JOB_ID_MISSING', 'platform_async_enqueue_job did not return job_id.', v_enqueue_result);
  end if;

  insert into public.platform_import_run (
    import_session_id, tenant_id, contract_id, run_no, requested_by_actor_user_id, job_id, run_status, result_summary, diagnostics
  ) values (
    v_session.import_session_id, v_session.tenant_id, v_session.contract_id, v_run_no, v_actor_user_id, v_job_id,
    'queued', jsonb_build_object('job_state', v_enqueue_result->'details'->>'job_state'), '{}'::jsonb
  ) returning * into v_run;

  update public.platform_import_session
  set session_status = 'committing',
      commit_requested_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where import_session_id = v_session.import_session_id;

  perform public.platform_exchange_write_event(jsonb_build_object(
    'contract_id', v_contract.contract_id,
    'tenant_id', v_session.tenant_id,
    'actor_user_id', v_actor_user_id,
    'event_type', 'import_commit_queued',
    'message', 'Import commit queued.',
    'details', jsonb_build_object('import_session_id', v_session.import_session_id, 'import_run_id', v_run.import_run_id, 'job_id', v_job_id)
  ));

  return public.platform_json_response(true, 'OK', 'Import commit queued.', jsonb_build_object(
    'import_session_id', v_session.import_session_id,
    'import_run_id', v_run.import_run_id,
    'job_id', v_job_id,
    'run_status', v_run.run_status
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_commit_import_session.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
