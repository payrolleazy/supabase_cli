create or replace function public.platform_hierarchy_run_diagnostics_internal(p_tenant_id uuid, p_schema_name text, p_trigger text default 'health_check')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_started_at timestamptz := timezone('utc', now());
  v_missing_tables text[] := '{}'::text[];
  v_position_count integer := 0;
  v_active_position_count integer := 0;
  v_active_occupancy_count integer := 0;
  v_overlap_position_count integer := 0;
  v_orphan_reporting_count integer := 0;
  v_missing_path_count integer := 0;
  v_inactive_position_with_active_occupancy_count integer := 0;
  v_issue_count integer := 0;
  v_health_status text := 'healthy';
  v_details jsonb := '{}'::jsonb;
  v_duration_ms integer;
begin
  if p_tenant_id is null or p_schema_name is null then
    return public.platform_json_response(false, 'TENANT_CONTEXT_REQUIRED', 'tenant_id and tenant_schema are required.', '{}'::jsonb);
  end if;

  if not public.platform_table_exists(p_schema_name, 'hierarchy_position') then
    v_missing_tables := array_append(v_missing_tables, 'hierarchy_position');
  end if;
  if not public.platform_table_exists(p_schema_name, 'hierarchy_position_occupancy') then
    v_missing_tables := array_append(v_missing_tables, 'hierarchy_position_occupancy');
  end if;
  if not public.platform_table_exists(p_schema_name, 'wcm_employee') then
    v_missing_tables := array_append(v_missing_tables, 'wcm_employee');
  end if;

  if coalesce(array_length(v_missing_tables, 1), 0) > 0 then
    return public.platform_json_response(false, 'HIERARCHY_NOT_APPLIED', 'HIERARCHY is not applied to the tenant schema.', jsonb_build_object('tenant_id', p_tenant_id, 'tenant_schema', p_schema_name, 'missing_tables', to_jsonb(v_missing_tables), 'trigger', p_trigger));
  end if;

  execute format(
    $sql$
      with position_metrics as (
        select
          count(*)::integer as position_count,
          count(*) filter (where p.position_status = 'active')::integer as active_position_count,
          count(*) filter (
            where p.reporting_position_id is not null
              and not exists (
                select 1 from %1$I.hierarchy_position parent where parent.position_id = p.reporting_position_id
              )
          )::integer as orphan_reporting_count,
          count(*) filter (
            where p.position_status = 'active' and p.hierarchy_path is null
          )::integer as missing_path_count
        from %1$I.hierarchy_position p
      ), occupancy_metrics as (
        select
          count(*) filter (
            where o.occupancy_status = 'active'
              and o.effective_start_date <= current_date
              and coalesce(o.effective_end_date, date '9999-12-31') >= current_date
          )::integer as active_occupancy_count,
          count(*) filter (
            where o.occupancy_status = 'active'
              and o.effective_start_date <= current_date
              and coalesce(o.effective_end_date, date '9999-12-31') >= current_date
              and coalesce(p.position_status, '') <> 'active'
          )::integer as inactive_position_with_active_occupancy_count
        from %1$I.hierarchy_position_occupancy o
        left join %1$I.hierarchy_position p on p.position_id = o.position_id
      ), overlap_metrics as (
        select count(*)::integer as overlap_position_count
        from (
          select o.position_id
          from %1$I.hierarchy_position_occupancy o
          where o.occupancy_status = 'active'
            and o.effective_start_date <= current_date
            and coalesce(o.effective_end_date, date '9999-12-31') >= current_date
          group by o.position_id
          having count(*) > 1
        ) overlap_rows
      )
      select pm.position_count, pm.active_position_count, om.active_occupancy_count, xm.overlap_position_count, pm.orphan_reporting_count, pm.missing_path_count, om.inactive_position_with_active_occupancy_count
      from position_metrics pm
      cross join occupancy_metrics om
      cross join overlap_metrics xm
    $sql$,
    p_schema_name
  ) into v_position_count, v_active_position_count, v_active_occupancy_count, v_overlap_position_count, v_orphan_reporting_count, v_missing_path_count, v_inactive_position_with_active_occupancy_count;

  v_issue_count := coalesce(v_orphan_reporting_count, 0) + coalesce(v_missing_path_count, 0) + coalesce(v_inactive_position_with_active_occupancy_count, 0) + coalesce(v_overlap_position_count, 0);
  v_health_status := case
    when coalesce(v_orphan_reporting_count, 0) > 0 or coalesce(v_missing_path_count, 0) > 0 then 'critical'
    when coalesce(v_inactive_position_with_active_occupancy_count, 0) > 0 or coalesce(v_overlap_position_count, 0) > 0 then 'warning'
    else 'healthy'
  end;

  v_details := jsonb_build_object(
    'tenant_id', p_tenant_id,
    'tenant_schema', p_schema_name,
    'health_status', v_health_status,
    'issue_count', v_issue_count,
    'position_count', v_position_count,
    'active_position_count', v_active_position_count,
    'active_occupancy_count', v_active_occupancy_count,
    'overlap_position_count', v_overlap_position_count,
    'orphan_reporting_count', v_orphan_reporting_count,
    'missing_path_count', v_missing_path_count,
    'inactive_position_with_active_occupancy_count', v_inactive_position_with_active_occupancy_count,
    'trigger', p_trigger
  );

  insert into public.platform_hierarchy_health_status (tenant_id, health_status, issue_count, checked_at, details)
  values (p_tenant_id, v_health_status, v_issue_count, timezone('utc', now()), v_details)
  on conflict (tenant_id)
  do update set health_status = excluded.health_status, issue_count = excluded.issue_count, checked_at = excluded.checked_at, details = excluded.details, updated_at = timezone('utc', now());

  insert into public.platform_hierarchy_metadata (tenant_id, last_health_check_at, last_self_test_at, last_health_status, metadata)
  values (p_tenant_id, timezone('utc', now()), case when p_trigger = 'self_test' then timezone('utc', now()) else null end, v_health_status, jsonb_build_object('last_trigger', p_trigger))
  on conflict (tenant_id)
  do update set
    last_health_check_at = timezone('utc', now()),
    last_self_test_at = case when p_trigger = 'self_test' then timezone('utc', now()) else public.platform_hierarchy_metadata.last_self_test_at end,
    last_health_status = excluded.last_health_status,
    metadata = coalesce(public.platform_hierarchy_metadata.metadata, '{}'::jsonb) || excluded.metadata,
    updated_at = timezone('utc', now());

  v_duration_ms := greatest(floor(extract(epoch from (timezone('utc', now()) - v_started_at)) * 1000)::integer, 0);

  insert into public.platform_hierarchy_performance_log (tenant_id, operation_code, status, duration_ms, details)
  values (
    p_tenant_id,
    'hierarchy_diagnostics',
    case when v_health_status = 'healthy' then 'succeeded' when v_health_status = 'warning' then 'warning' else 'failed' end,
    v_duration_ms,
    v_details
  );

  return public.platform_json_response(true, 'OK', 'Hierarchy diagnostics completed.', v_details);
exception
  when others then
    insert into public.platform_hierarchy_error_log (tenant_id, operation_code, error_code, error_message, details)
    values (p_tenant_id, 'hierarchy_diagnostics', 'UNEXPECTED_ERROR', sqlerrm, jsonb_build_object('tenant_schema', p_schema_name, 'trigger', p_trigger, 'sqlstate', sqlstate, 'sqlerrm', sqlerrm));

    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_hierarchy_run_diagnostics_internal.', jsonb_build_object('tenant_id', p_tenant_id, 'tenant_schema', p_schema_name, 'sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_hierarchy_health_check(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_schema_name text;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Hierarchy health check is restricted to internal callers.', '{}'::jsonb);
  end if;

  if v_tenant_id is null then
    v_tenant_id := public.platform_current_tenant_id();
  end if;
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select schema_name into v_schema_name from public.platform_tenant_registry_view where tenant_id = v_tenant_id and schema_provisioned is true;
  if v_schema_name is null then
    return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_FOUND', 'Tenant schema is not available.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;
  if not public.platform_table_exists(v_schema_name, 'hierarchy_position') then
    return public.platform_json_response(false, 'HIERARCHY_NOT_APPLIED', 'HIERARCHY is not applied to the tenant schema.', jsonb_build_object('tenant_id', v_tenant_id, 'tenant_schema', v_schema_name));
  end if;

  return public.platform_hierarchy_run_diagnostics_internal(v_tenant_id, v_schema_name, 'health_check');
end;
$function$;

create or replace function public.platform_hierarchy_self_test(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_schema_name text;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Hierarchy self-test is restricted to internal callers.', '{}'::jsonb);
  end if;

  if v_tenant_id is null then
    v_tenant_id := public.platform_current_tenant_id();
  end if;
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select schema_name into v_schema_name from public.platform_tenant_registry_view where tenant_id = v_tenant_id and schema_provisioned is true;
  if v_schema_name is null then
    return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_FOUND', 'Tenant schema is not available.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;
  if not public.platform_table_exists(v_schema_name, 'hierarchy_position') then
    return public.platform_json_response(false, 'HIERARCHY_NOT_APPLIED', 'HIERARCHY is not applied to the tenant schema.', jsonb_build_object('tenant_id', v_tenant_id, 'tenant_schema', v_schema_name));
  end if;

  return public.platform_hierarchy_run_diagnostics_internal(v_tenant_id, v_schema_name, 'self_test');
end;
$function$;

create or replace function public.platform_hierarchy_run_maintenance(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_trigger_source text := coalesce(nullif(btrim(p_params->>'source'), ''), 'manual');
  v_lock_key text := 'hierarchy_runtime_maintenance';
  v_run_id uuid;
  v_refresh_request jsonb;
  v_refresh_execute jsonb := '{}'::jsonb;
  v_refresh_run_id uuid;
  v_refresh_status text := '';
  v_refresh_row_count integer := 0;
  v_cache_refreshed boolean := false;
  v_tenant record;
  v_diag_result jsonb;
  v_diag_status text := '';
  v_tenant_checked_count integer := 0;
  v_healthy_tenant_count integer := 0;
  v_warning_tenant_count integer := 0;
  v_critical_tenant_count integer := 0;
  v_failed_tenant_ids jsonb := '[]'::jsonb;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Hierarchy maintenance is restricted to internal callers.', '{}'::jsonb);
  end if;

  delete from public.platform_hierarchy_maintenance_lock where lock_key = v_lock_key and lock_expires_at < timezone('utc', now());

  insert into public.platform_hierarchy_maintenance_lock (lock_key, tenant_id, lock_expires_at, details)
  values (v_lock_key, null, timezone('utc', now()) + interval '20 minutes', jsonb_build_object('trigger_source', v_trigger_source))
  on conflict do nothing;

  if not found then
    return public.platform_json_response(false, 'MAINTENANCE_ALREADY_RUNNING', 'Hierarchy maintenance is already running.', jsonb_build_object('lock_key', v_lock_key));
  end if;

  insert into public.platform_hierarchy_maintenance_run (maintenance_code, trigger_source, run_status, details)
  values ('hierarchy_maintenance', v_trigger_source, 'running', jsonb_build_object('trigger_source', v_trigger_source))
  returning run_id into v_run_id;

  v_refresh_request := public.platform_request_read_model_refresh(jsonb_build_object('read_model_code', 'hierarchy_org_chart_cached_store', 'refresh_trigger', 'schedule', 'requested_by', 'hierarchy_maintenance'));
  if coalesce((v_refresh_request->>'success')::boolean, false) is not true then
    raise exception 'platform_request_read_model_refresh failed: %', v_refresh_request::text;
  end if;

  v_refresh_run_id := nullif(v_refresh_request->'details'->>'run_id', '')::uuid;
  v_refresh_status := coalesce(v_refresh_request->'details'->>'status', '');

  if v_refresh_status = 'queued' then
    v_refresh_execute := public.platform_execute_read_model_refresh(jsonb_build_object('run_id', v_refresh_run_id, 'capture_row_count', true));
    if coalesce((v_refresh_execute->>'success')::boolean, false) is not true then
      raise exception 'platform_execute_read_model_refresh failed: %', v_refresh_execute::text;
    end if;
    v_refresh_row_count := coalesce(nullif(v_refresh_execute->'details'->>'row_count', '')::integer, 0);
    v_cache_refreshed := true;
  end if;

  for v_tenant in
    select t.tenant_id, t.schema_name
    from public.platform_tenant_registry_view t
    where t.schema_provisioned is true
      and t.schema_name like 'tenant_%'
      and coalesce(t.background_processing_allowed, true) is true
      and public.platform_table_exists(t.schema_name, 'hierarchy_position')
      and public.platform_table_exists(t.schema_name, 'hierarchy_position_group')
      and public.platform_table_exists(t.schema_name, 'hierarchy_position_occupancy')
    order by t.schema_name
  loop
    v_diag_result := public.platform_hierarchy_run_diagnostics_internal(v_tenant.tenant_id, v_tenant.schema_name, 'maintenance');
    v_tenant_checked_count := v_tenant_checked_count + 1;

    if coalesce((v_diag_result->>'success')::boolean, false) is true then
      v_diag_status := coalesce(v_diag_result->'details'->>'health_status', 'critical');
    else
      v_diag_status := 'critical';
      v_failed_tenant_ids := v_failed_tenant_ids || jsonb_build_array(v_tenant.tenant_id);
    end if;

    if v_diag_status = 'healthy' then
      v_healthy_tenant_count := v_healthy_tenant_count + 1;
    elsif v_diag_status = 'warning' then
      v_warning_tenant_count := v_warning_tenant_count + 1;
    else
      v_critical_tenant_count := v_critical_tenant_count + 1;
    end if;

    insert into public.platform_hierarchy_metadata (tenant_id, last_cache_refresh_at, last_maintenance_at, metadata)
    values (
      v_tenant.tenant_id,
      case when v_cache_refreshed then timezone('utc', now()) else null end,
      timezone('utc', now()),
      jsonb_build_object('last_maintenance_trigger', v_trigger_source)
    )
    on conflict (tenant_id)
    do update set
      last_cache_refresh_at = case when v_cache_refreshed then timezone('utc', now()) else public.platform_hierarchy_metadata.last_cache_refresh_at end,
      last_maintenance_at = timezone('utc', now()),
      metadata = coalesce(public.platform_hierarchy_metadata.metadata, '{}'::jsonb) || excluded.metadata,
      updated_at = timezone('utc', now());
  end loop;

  delete from public.platform_hierarchy_health_status h
  using public.platform_tenant_registry_view t
  where h.tenant_id = t.tenant_id
    and not public.platform_table_exists(t.schema_name, 'hierarchy_position');

  delete from public.platform_hierarchy_metadata m
  using public.platform_tenant_registry_view t
  where m.tenant_id = t.tenant_id
    and not public.platform_table_exists(t.schema_name, 'hierarchy_position');

  update public.platform_hierarchy_maintenance_run
  set run_status = 'succeeded',
      refresh_run_id = v_refresh_run_id,
      tenant_checked_count = v_tenant_checked_count,
      healthy_tenant_count = v_healthy_tenant_count,
      warning_tenant_count = v_warning_tenant_count,
      critical_tenant_count = v_critical_tenant_count,
      details = jsonb_build_object('trigger_source', v_trigger_source, 'cache_refreshed', v_cache_refreshed, 'refresh_row_count', v_refresh_row_count, 'refresh_request', v_refresh_request, 'refresh_execute', v_refresh_execute, 'failed_tenant_ids', v_failed_tenant_ids),
      completed_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where run_id = v_run_id;

  delete from public.platform_hierarchy_maintenance_lock where lock_key = v_lock_key;

  return public.platform_json_response(true, 'OK', 'Hierarchy maintenance completed.', jsonb_build_object('run_id', v_run_id, 'refresh_run_id', v_refresh_run_id, 'cache_refreshed', v_cache_refreshed, 'refresh_row_count', v_refresh_row_count, 'tenant_checked_count', v_tenant_checked_count, 'healthy_tenant_count', v_healthy_tenant_count, 'warning_tenant_count', v_warning_tenant_count, 'critical_tenant_count', v_critical_tenant_count, 'failed_tenant_ids', v_failed_tenant_ids));
exception
  when others then
    if v_run_id is not null then
      update public.platform_hierarchy_maintenance_run
      set run_status = 'failed',
          refresh_run_id = v_refresh_run_id,
          details = jsonb_build_object('trigger_source', v_trigger_source, 'refresh_request', v_refresh_request, 'refresh_execute', v_refresh_execute, 'sqlstate', sqlstate, 'sqlerrm', sqlerrm),
          completed_at = timezone('utc', now()),
          updated_at = timezone('utc', now())
      where run_id = v_run_id;
    end if;

    insert into public.platform_hierarchy_error_log (tenant_id, operation_code, error_code, error_message, details)
    values (null, 'hierarchy_maintenance', 'UNEXPECTED_ERROR', sqlerrm, jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm, 'trigger_source', v_trigger_source));

    delete from public.platform_hierarchy_maintenance_lock where lock_key = v_lock_key;

    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_hierarchy_run_maintenance.', jsonb_build_object('run_id', v_run_id, 'sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

do $do$
declare
  v_result jsonb;
begin
  v_result := public.platform_hierarchy_run_maintenance_scheduler();
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'HIERARCHY maintenance scope correction rerun failed: %', v_result::text;
  end if;
end;
$do$;
