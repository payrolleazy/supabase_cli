create or replace function public.platform_generate_schema_name(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_tenant_code text := public.platform_normalize_tenant_code(p_params->>'tenant_code');
  v_schema_name text;
begin
  if v_tenant_id is not null then
    select tenant_code
    into v_tenant_code
    from public.platform_tenant
    where tenant_id = v_tenant_id;

    if not found then
      return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant not found.', jsonb_build_object('tenant_id', v_tenant_id));
    end if;
  end if;

  if v_tenant_code is null then
    return public.platform_json_response(false, 'TENANT_CODE_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  v_schema_name := public.platform_build_schema_name(v_tenant_code);

  if v_schema_name is null then
    return public.platform_json_response(false, 'SCHEMA_NAME_GENERATION_FAILED', 'Schema name could not be generated.', jsonb_build_object('tenant_code', v_tenant_code));
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'Schema name generated.',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'tenant_code', v_tenant_code,
      'schema_name', v_schema_name
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_generate_schema_name.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_template_version(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_actor uuid := public.platform_resolve_actor();
  v_template_version text := nullif(btrim(coalesce(p_params->>'template_version', '')), '');
  v_template_scope text := lower(coalesce(nullif(btrim(p_params->>'template_scope'), ''), 'foundation'));
  v_template_status text := lower(coalesce(nullif(btrim(p_params->>'template_status'), ''), 'draft'));
  v_foundation_version text := nullif(btrim(coalesce(p_params->>'foundation_version', '')), '');
  v_description text := nullif(btrim(coalesce(p_params->>'description', '')), '');
  v_release_notes jsonb := coalesce(p_params->'release_notes', '{}'::jsonb);
  v_released_at timestamptz;
begin
  if v_template_version is null then
    return public.platform_json_response(false, 'TEMPLATE_VERSION_REQUIRED', 'template_version is required.', jsonb_build_object('field', 'template_version'));
  end if;

  if v_template_scope not in ('foundation', 'module', 'patch') then
    return public.platform_json_response(false, 'INVALID_TEMPLATE_SCOPE', 'template_scope must be foundation, module, or patch.', jsonb_build_object('field', 'template_scope'));
  end if;

  if v_template_status not in ('draft', 'released', 'retired') then
    return public.platform_json_response(false, 'INVALID_TEMPLATE_STATUS', 'template_status must be draft, released, or retired.', jsonb_build_object('field', 'template_status'));
  end if;

  if jsonb_typeof(v_release_notes) is distinct from 'object' then
    return public.platform_json_response(false, 'INVALID_RELEASE_NOTES', 'release_notes must be a JSON object.', jsonb_build_object('field', 'release_notes'));
  end if;

  v_released_at := case when v_template_status = 'released' then timezone('utc', now()) else null end;

  insert into public.platform_template_version (
    template_version,
    template_scope,
    template_status,
    foundation_version,
    description,
    release_notes,
    released_at,
    created_by
  )
  values (
    v_template_version,
    v_template_scope,
    v_template_status,
    v_foundation_version,
    v_description,
    v_release_notes,
    v_released_at,
    v_actor
  )
  on conflict (template_version) do update
  set
    template_scope = excluded.template_scope,
    template_status = excluded.template_status,
    foundation_version = excluded.foundation_version,
    description = excluded.description,
    release_notes = excluded.release_notes,
    released_at = case
      when excluded.template_status = 'released' then coalesce(public.platform_template_version.released_at, excluded.released_at)
      else public.platform_template_version.released_at
    end;

  return public.platform_json_response(
    true,
    'OK',
    'Template version registered.',
    jsonb_build_object(
      'template_version', v_template_version,
      'template_scope', v_template_scope,
      'template_status', v_template_status
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_template_version.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_template_table(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_actor uuid := public.platform_resolve_actor();
  v_template_version text := nullif(btrim(coalesce(p_params->>'template_version', '')), '');
  v_module_code text := nullif(btrim(coalesce(p_params->>'module_code', '')), '');
  v_source_schema_name text := coalesce(nullif(btrim(p_params->>'source_schema_name'), ''), 'public');
  v_source_table_name text := nullif(btrim(coalesce(p_params->>'source_table_name', '')), '');
  v_target_table_name text := coalesce(nullif(btrim(p_params->>'target_table_name'), ''), v_source_table_name);
  v_clone_order integer := coalesce((p_params->>'clone_order')::integer, 1);
  v_clone_enabled boolean := coalesce((p_params->>'clone_enabled')::boolean, true);
  v_seed_mode text := lower(coalesce(nullif(btrim(p_params->>'seed_mode'), ''), 'none'));
  v_seed_filter jsonb := coalesce(p_params->'seed_filter', '{}'::jsonb);
  v_notes jsonb := coalesce(p_params->'notes', '{}'::jsonb);
begin
  if v_template_version is null then
    return public.platform_json_response(false, 'TEMPLATE_VERSION_REQUIRED', 'template_version is required.', jsonb_build_object('field', 'template_version'));
  end if;

  if v_module_code is null then
    return public.platform_json_response(false, 'MODULE_CODE_REQUIRED', 'module_code is required.', jsonb_build_object('field', 'module_code'));
  end if;

  if v_source_table_name is null then
    return public.platform_json_response(false, 'SOURCE_TABLE_REQUIRED', 'source_table_name is required.', jsonb_build_object('field', 'source_table_name'));
  end if;

  if v_target_table_name is null then
    return public.platform_json_response(false, 'TARGET_TABLE_REQUIRED', 'target_table_name is required.', jsonb_build_object('field', 'target_table_name'));
  end if;

  if v_seed_mode not in ('none', 'copy_all_rows') then
    return public.platform_json_response(false, 'INVALID_SEED_MODE', 'seed_mode must be none or copy_all_rows.', jsonb_build_object('field', 'seed_mode'));
  end if;

  if jsonb_typeof(v_seed_filter) is distinct from 'object' then
    return public.platform_json_response(false, 'INVALID_SEED_FILTER', 'seed_filter must be a JSON object.', jsonb_build_object('field', 'seed_filter'));
  end if;

  if jsonb_typeof(v_notes) is distinct from 'object' then
    return public.platform_json_response(false, 'INVALID_NOTES', 'notes must be a JSON object.', jsonb_build_object('field', 'notes'));
  end if;

  if not exists (
    select 1
    from public.platform_template_version
    where template_version = v_template_version
  ) then
    return public.platform_json_response(false, 'TEMPLATE_VERSION_NOT_FOUND', 'Template version not found.', jsonb_build_object('template_version', v_template_version));
  end if;

  if not public.platform_table_exists(v_source_schema_name, v_source_table_name) then
    return public.platform_json_response(
      false,
      'TEMPLATE_TABLE_NOT_FOUND',
      'Source template table was not found.',
      jsonb_build_object('source_schema_name', v_source_schema_name, 'source_table_name', v_source_table_name)
    );
  end if;

  insert into public.platform_template_table_registry (
    template_version,
    module_code,
    source_schema_name,
    source_table_name,
    target_table_name,
    clone_order,
    clone_enabled,
    seed_mode,
    seed_filter,
    notes,
    created_by
  )
  values (
    v_template_version,
    v_module_code,
    v_source_schema_name,
    v_source_table_name,
    v_target_table_name,
    v_clone_order,
    v_clone_enabled,
    v_seed_mode,
    v_seed_filter,
    v_notes,
    v_actor
  )
  on conflict (template_version, source_schema_name, source_table_name) do update
  set
    module_code = excluded.module_code,
    target_table_name = excluded.target_table_name,
    clone_order = excluded.clone_order,
    clone_enabled = excluded.clone_enabled,
    seed_mode = excluded.seed_mode,
    seed_filter = excluded.seed_filter,
    notes = excluded.notes;

  return public.platform_json_response(
    true,
    'OK',
    'Template table registered.',
    jsonb_build_object(
      'template_version', v_template_version,
      'source_schema_name', v_source_schema_name,
      'source_table_name', v_source_table_name,
      'target_table_name', v_target_table_name
    )
  );
exception
  when unique_violation then
    return public.platform_json_response(false, 'TEMPLATE_TABLE_INVALID', 'Template table registration conflicts with an existing target table mapping.', jsonb_build_object('template_version', v_template_version, 'target_table_name', v_target_table_name));
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_template_table.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_create_tenant_schema(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_actor uuid := public.platform_resolve_actor();
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_source text := coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_create_tenant_schema');
  v_tenant_row public.platform_tenant%rowtype;
  v_provisioning_row public.platform_tenant_provisioning%rowtype;
  v_schema_name text;
  v_existing_owner uuid;
  v_run_id uuid;
  v_transition_result jsonb;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select *
  into v_tenant_row
  from public.platform_tenant
  where tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  select *
  into v_provisioning_row
  from public.platform_tenant_provisioning
  where tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant provisioning row not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  v_schema_name := coalesce(v_tenant_row.schema_name, public.platform_build_schema_name(v_tenant_row.tenant_code));

  if v_schema_name is null then
    return public.platform_json_response(false, 'SCHEMA_NAME_GENERATION_FAILED', 'Schema name could not be generated.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  select tenant_id
  into v_existing_owner
  from public.platform_tenant
  where schema_name = v_schema_name
    and tenant_id <> v_tenant_id
  limit 1;

  if v_existing_owner is not null then
    return public.platform_json_response(
      false,
      'SCHEMA_ALREADY_BOUND_TO_OTHER_TENANT',
      'Schema name is already bound to another tenant.',
      jsonb_build_object('schema_name', v_schema_name, 'tenant_id', v_tenant_id, 'existing_owner_tenant_id', v_existing_owner)
    );
  end if;

  v_run_id := public.platform_start_schema_provisioning_run(
    v_tenant_id,
    v_schema_name,
    'schema_create',
    null,
    v_actor,
    v_source,
    jsonb_build_object('provisioning_status', v_provisioning_row.provisioning_status)
  );

  if public.platform_schema_exists(v_schema_name) then
    update public.platform_tenant
    set schema_name = v_schema_name
    where tenant_id = v_tenant_id
      and schema_name is distinct from v_schema_name;

    if v_provisioning_row.provisioning_status in ('registry_created', 'failed', 'disabled') then
      v_transition_result := public.platform_transition_provisioning_state(jsonb_build_object(
        'tenant_id', v_tenant_id,
        'to_status', 'schema_pending',
        'source', v_source,
        'latest_completed_step', 'schema_create_replay_started',
        'details', jsonb_build_object('schema_name', v_schema_name)
      ));

      if coalesce((v_transition_result->>'success')::boolean, false) is not true then
        perform public.platform_finish_schema_provisioning_run(v_run_id, 'failed', 'SCHEMA_CREATE_FAILED', coalesce(v_transition_result->>'message', 'Provisioning transition failed.'), jsonb_build_object('transition_result', v_transition_result));
        return v_transition_result;
      end if;
    end if;

    if v_provisioning_row.provisioning_status in ('registry_created', 'schema_pending', 'failed', 'disabled') then
      v_transition_result := public.platform_transition_provisioning_state(jsonb_build_object(
        'tenant_id', v_tenant_id,
        'to_status', 'schema_ready',
        'source', v_source,
        'latest_completed_step', 'schema_created',
        'schema_provisioned', true,
        'details', jsonb_build_object('schema_name', v_schema_name, 'idempotent_replay', true)
      ));

      if coalesce((v_transition_result->>'success')::boolean, false) is not true then
        perform public.platform_finish_schema_provisioning_run(v_run_id, 'failed', 'SCHEMA_CREATE_FAILED', coalesce(v_transition_result->>'message', 'Provisioning transition failed.'), jsonb_build_object('transition_result', v_transition_result));
        return v_transition_result;
      end if;
    end if;

    perform public.platform_finish_schema_provisioning_run(v_run_id, 'succeeded', null, null, jsonb_build_object('idempotent_replay', true, 'schema_exists', true));

    return public.platform_json_response(
      true,
      'OK',
      'Tenant schema already exists for this tenant.',
      jsonb_build_object(
        'tenant_id', v_tenant_id,
        'schema_name', v_schema_name,
        'run_id', v_run_id,
        'idempotent_replay', true
      )
    );
  end if;

  if v_provisioning_row.provisioning_status in ('registry_created', 'failed', 'disabled') then
    v_transition_result := public.platform_transition_provisioning_state(jsonb_build_object(
      'tenant_id', v_tenant_id,
      'to_status', 'schema_pending',
      'source', v_source,
      'latest_completed_step', 'schema_create_started',
      'details', jsonb_build_object('schema_name', v_schema_name)
    ));

    if coalesce((v_transition_result->>'success')::boolean, false) is not true then
      perform public.platform_finish_schema_provisioning_run(v_run_id, 'failed', 'SCHEMA_CREATE_FAILED', coalesce(v_transition_result->>'message', 'Provisioning transition failed.'), jsonb_build_object('transition_result', v_transition_result));
      return v_transition_result;
    end if;
  elsif v_provisioning_row.provisioning_status not in ('schema_pending', 'schema_ready', 'foundation_ready', 'ready_for_routing') then
    perform public.platform_finish_schema_provisioning_run(v_run_id, 'failed', 'INVALID_PROVISIONING_TRANSITION', 'Provisioning state is not valid for schema creation.', jsonb_build_object('provisioning_status', v_provisioning_row.provisioning_status));
    return public.platform_json_response(false, 'INVALID_PROVISIONING_TRANSITION', 'Provisioning state is not valid for schema creation.', jsonb_build_object('from_status', v_provisioning_row.provisioning_status, 'to_status', 'schema_ready'));
  end if;

  execute format('create schema %I', v_schema_name);

  update public.platform_tenant
  set schema_name = v_schema_name
  where tenant_id = v_tenant_id;

  if v_provisioning_row.provisioning_status in ('registry_created', 'schema_pending', 'failed', 'disabled') then
    v_transition_result := public.platform_transition_provisioning_state(jsonb_build_object(
      'tenant_id', v_tenant_id,
      'to_status', 'schema_ready',
      'source', v_source,
      'latest_completed_step', 'schema_created',
      'schema_provisioned', true,
      'details', jsonb_build_object('schema_name', v_schema_name)
    ));

    if coalesce((v_transition_result->>'success')::boolean, false) is not true then
      perform public.platform_finish_schema_provisioning_run(v_run_id, 'failed', 'SCHEMA_CREATE_FAILED', coalesce(v_transition_result->>'message', 'Provisioning transition failed.'), jsonb_build_object('transition_result', v_transition_result));
      return v_transition_result;
    end if;
  end if;

  perform public.platform_finish_schema_provisioning_run(v_run_id, 'succeeded', null, null, jsonb_build_object('schema_created', true));

  return public.platform_json_response(
    true,
    'OK',
    'Tenant schema created.',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'schema_name', v_schema_name,
      'run_id', v_run_id
    )
  );
exception
  when others then
    if v_run_id is not null then
      perform public.platform_finish_schema_provisioning_run(v_run_id, 'failed', 'SCHEMA_CREATE_FAILED', sqlerrm, jsonb_build_object('sqlstate', sqlstate));
    end if;

    if v_tenant_id is not null then
      perform public.platform_transition_provisioning_state(jsonb_build_object(
        'tenant_id', v_tenant_id,
        'to_status', 'failed',
        'source', v_source,
        'last_error_code', 'SCHEMA_CREATE_FAILED',
        'last_error_message', sqlerrm,
        'details', jsonb_build_object('schema_name', coalesce(v_schema_name, null))
      ));
    end if;

    return public.platform_json_response(false, 'SCHEMA_CREATE_FAILED', 'Tenant schema creation failed.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm, 'tenant_id', v_tenant_id, 'schema_name', v_schema_name));
end;
$function$;

create or replace function public.platform_apply_template_version_to_tenant(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_actor uuid := public.platform_resolve_actor();
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_template_version text := nullif(btrim(coalesce(p_params->>'template_version', '')), '');
  v_source text := coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_apply_template_version_to_tenant');
  v_tenant_row public.platform_tenant%rowtype;
  v_provisioning_row public.platform_tenant_provisioning%rowtype;
  v_template_row public.platform_template_version%rowtype;
  v_existing_apply public.platform_tenant_template_version%rowtype;
  v_run_id uuid;
  v_clone_summary jsonb;
  v_transition_result jsonb;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  if v_template_version is null then
    return public.platform_json_response(false, 'TEMPLATE_VERSION_REQUIRED', 'template_version is required.', jsonb_build_object('field', 'template_version'));
  end if;

  select *
  into v_tenant_row
  from public.platform_tenant
  where tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  select *
  into v_provisioning_row
  from public.platform_tenant_provisioning
  where tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant provisioning row not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  select *
  into v_template_row
  from public.platform_template_version
  where template_version = v_template_version;

  if not found then
    return public.platform_json_response(false, 'TEMPLATE_VERSION_NOT_FOUND', 'Template version not found.', jsonb_build_object('template_version', v_template_version));
  end if;

  if v_template_row.template_status <> 'released' then
    return public.platform_json_response(false, 'TEMPLATE_VERSION_NOT_RELEASED', 'Template version is not released.', jsonb_build_object('template_version', v_template_version, 'template_status', v_template_row.template_status));
  end if;

  if v_tenant_row.schema_name is null or not public.platform_schema_exists(v_tenant_row.schema_name) then
    return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_READY', 'Tenant schema is not ready.', jsonb_build_object('tenant_id', v_tenant_id, 'schema_name', v_tenant_row.schema_name));
  end if;

  select *
  into v_existing_apply
  from public.platform_tenant_template_version
  where tenant_id = v_tenant_id
    and template_version = v_template_version
  for update;

  v_run_id := public.platform_start_schema_provisioning_run(
    v_tenant_id,
    v_tenant_row.schema_name,
    'template_apply',
    v_template_version,
    v_actor,
    v_source,
    jsonb_build_object('template_scope', v_template_row.template_scope)
  );

  if found and v_existing_apply.apply_status = 'applied' then
    perform public.platform_finish_schema_provisioning_run(v_run_id, 'succeeded', null, null, jsonb_build_object('idempotent_replay', true, 'template_version', v_template_version));

    return public.platform_json_response(
      true,
      'OK',
      'Template version already applied for this tenant.',
      jsonb_build_object(
        'tenant_id', v_tenant_id,
        'template_version', v_template_version,
        'schema_name', v_tenant_row.schema_name,
        'run_id', v_run_id,
        'idempotent_replay', true
      )
    );
  end if;

  insert into public.platform_tenant_template_version (
    tenant_id,
    template_version,
    schema_name,
    apply_status,
    run_id,
    details
  )
  values (
    v_tenant_id,
    v_template_version,
    v_tenant_row.schema_name,
    'pending',
    v_run_id,
    '{}'::jsonb
  )
  on conflict (tenant_id, template_version) do update
  set
    schema_name = excluded.schema_name,
    apply_status = 'pending',
    run_id = excluded.run_id,
    details = public.platform_tenant_template_version.details || jsonb_build_object('retry_requested_at', timezone('utc', now()));

  v_clone_summary := public.platform_clone_registered_template_tables(v_tenant_id, v_template_version);

  update public.platform_tenant_template_version
  set
    apply_status = 'applied',
    applied_at = timezone('utc', now()),
    run_id = v_run_id,
    details = details || coalesce(v_clone_summary, '{}'::jsonb)
  where tenant_id = v_tenant_id
    and template_version = v_template_version;

  if v_template_row.template_scope = 'foundation'
     and v_provisioning_row.provisioning_status in ('schema_ready', 'failed', 'disabled') then
    v_transition_result := public.platform_transition_provisioning_state(jsonb_build_object(
      'tenant_id', v_tenant_id,
      'to_status', 'foundation_ready',
      'source', v_source,
      'latest_completed_step', 'foundation_template_applied',
      'foundation_version', v_template_version,
      'schema_provisioned', true,
      'details', jsonb_build_object('schema_name', v_tenant_row.schema_name, 'template_version', v_template_version)
    ));

    if coalesce((v_transition_result->>'success')::boolean, false) is not true then
      perform public.platform_finish_schema_provisioning_run(v_run_id, 'failed', 'TEMPLATE_APPLY_FAILED', coalesce(v_transition_result->>'message', 'Provisioning transition failed.'), jsonb_build_object('transition_result', v_transition_result));
      return v_transition_result;
    end if;
  end if;

  perform public.platform_finish_schema_provisioning_run(v_run_id, 'succeeded', null, null, coalesce(v_clone_summary, '{}'::jsonb));

  return public.platform_json_response(
    true,
    'OK',
    'Template version applied.',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'template_version', v_template_version,
      'schema_name', v_tenant_row.schema_name,
      'run_id', v_run_id,
      'clone_summary', coalesce(v_clone_summary, '{}'::jsonb)
    )
  );
exception
  when others then
    if v_run_id is not null then
      perform public.platform_finish_schema_provisioning_run(v_run_id, 'failed', 'TEMPLATE_APPLY_FAILED', sqlerrm, jsonb_build_object('sqlstate', sqlstate, 'template_version', v_template_version));
    end if;

    if v_tenant_id is not null and v_template_version is not null and coalesce(v_tenant_row.schema_name, '') <> '' then
      insert into public.platform_tenant_template_version (
        tenant_id,
        template_version,
        schema_name,
        apply_status,
        run_id,
        details
      )
      values (
        v_tenant_id,
        v_template_version,
        v_tenant_row.schema_name,
        'failed',
        v_run_id,
        jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
      )
      on conflict (tenant_id, template_version) do update
      set
        apply_status = 'failed',
        run_id = excluded.run_id,
        details = public.platform_tenant_template_version.details || excluded.details;
    end if;

    if v_template_row.template_scope = 'foundation'
       and v_tenant_id is not null
       and coalesce(v_provisioning_row.provisioning_status, '') not in ('ready_for_routing') then
      perform public.platform_transition_provisioning_state(jsonb_build_object(
        'tenant_id', v_tenant_id,
        'to_status', 'failed',
        'source', v_source,
        'last_error_code', 'TEMPLATE_APPLY_FAILED',
        'last_error_message', sqlerrm,
        'details', jsonb_build_object('template_version', v_template_version)
      ));
    end if;

    return public.platform_json_response(false, 'TEMPLATE_APPLY_FAILED', 'Template version apply failed.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm, 'tenant_id', v_tenant_id, 'template_version', v_template_version));
end;
$function$;

create or replace function public.platform_get_tenant_schema_state(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_row public.platform_schema_provisioning_view%rowtype;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select *
  into v_row
  from public.platform_schema_provisioning_view
  where tenant_id = v_tenant_id;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'Tenant schema state resolved.',
    jsonb_build_object(
      'tenant_id', v_row.tenant_id,
      'tenant_code', v_row.tenant_code,
      'schema_name', v_row.schema_name,
      'schema_exists', v_row.schema_exists,
      'provisioning_status', v_row.provisioning_status,
      'schema_provisioned', v_row.schema_provisioned,
      'foundation_version', v_row.foundation_version,
      'ready_for_routing', v_row.ready_for_routing,
      'latest_completed_step', v_row.latest_completed_step,
      'last_error_code', v_row.last_error_code,
      'last_error_message', v_row.last_error_message,
      'last_error_at', v_row.last_error_at,
      'applied_versions', coalesce(v_row.applied_versions, '[]'::jsonb),
      'latest_run', coalesce(v_row.latest_run, '{}'::jsonb)
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_get_tenant_schema_state.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
