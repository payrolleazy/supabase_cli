create or replace function public.platform_rcm_resolve_context(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_params jsonb := coalesce(p_params, '{}'::jsonb);
  v_requested_tenant_id uuid := public.platform_resolve_tenant_id(v_params);
  v_current_tenant_id uuid := public.platform_current_tenant_id();
  v_current_schema text := public.platform_current_tenant_schema();
  v_context_result jsonb;
  v_details jsonb;
begin
  if v_current_tenant_id is not null and v_current_schema is not null then
    if v_requested_tenant_id is not null and v_requested_tenant_id <> v_current_tenant_id then
      return public.platform_json_response(false,'CONTEXT_TENANT_MISMATCH','The requested tenant does not match the current execution context.',jsonb_build_object('requested_tenant_id', v_requested_tenant_id,'current_tenant_id', v_current_tenant_id));
    end if;

    if not public.platform_table_exists(v_current_schema, 'wcm_employee')
      or not public.platform_table_exists(v_current_schema, 'wcm_employee_service_state')
      or not public.platform_table_exists(v_current_schema, 'hierarchy_position')
      or not public.platform_table_exists(v_current_schema, 'rcm_requisition')
      or not public.platform_table_exists(v_current_schema, 'rcm_candidate')
      or not public.platform_table_exists(v_current_schema, 'rcm_job_application')
      or not public.platform_table_exists(v_current_schema, 'rcm_application_stage_event')
      or not public.platform_table_exists(v_current_schema, 'rcm_conversion_case')
      or not public.platform_table_exists(v_current_schema, 'rcm_conversion_event_log')
    then
      return public.platform_json_response(false,'RCM_TEMPLATE_NOT_APPLIED','RECRUITMENT_AND_CONVERSION is not applied to the current tenant schema.',jsonb_build_object('tenant_id', v_current_tenant_id,'tenant_schema', v_current_schema));
    end if;

    return public.platform_json_response(true,'OK','RECRUITMENT_AND_CONVERSION execution context resolved.',jsonb_build_object('tenant_id', v_current_tenant_id,'tenant_schema', v_current_schema,'actor_user_id', public.platform_current_actor_user_id()));
  end if;

  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false,'TENANT_CONTEXT_REQUIRED','An applied tenant execution context is required.','{}'::jsonb);
  end if;

  if v_requested_tenant_id is null then
    return public.platform_json_response(false,'TENANT_ID_REQUIRED','tenant_id or tenant_code is required when no execution context is active.','{}'::jsonb);
  end if;

  v_context_result := public.platform_apply_execution_context(jsonb_build_object('execution_mode', 'internal_platform','tenant_id', v_requested_tenant_id,'source', coalesce(nullif(btrim(v_params->>'source'), ''), 'platform_rcm_resolve_context')));
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  v_details := coalesce(v_context_result->'details', '{}'::jsonb);
  if not public.platform_table_exists(v_details->>'tenant_schema', 'wcm_employee')
    or not public.platform_table_exists(v_details->>'tenant_schema', 'wcm_employee_service_state')
    or not public.platform_table_exists(v_details->>'tenant_schema', 'hierarchy_position')
    or not public.platform_table_exists(v_details->>'tenant_schema', 'rcm_requisition')
    or not public.platform_table_exists(v_details->>'tenant_schema', 'rcm_candidate')
    or not public.platform_table_exists(v_details->>'tenant_schema', 'rcm_job_application')
    or not public.platform_table_exists(v_details->>'tenant_schema', 'rcm_application_stage_event')
    or not public.platform_table_exists(v_details->>'tenant_schema', 'rcm_conversion_case')
    or not public.platform_table_exists(v_details->>'tenant_schema', 'rcm_conversion_event_log')
  then
    return public.platform_json_response(false,'RCM_TEMPLATE_NOT_APPLIED','RECRUITMENT_AND_CONVERSION is not applied to the requested tenant schema.',jsonb_build_object('tenant_id', public.platform_try_uuid(v_details->>'tenant_id'),'tenant_schema', v_details->>'tenant_schema'));
  end if;

  return public.platform_json_response(true,'OK','RECRUITMENT_AND_CONVERSION execution context resolved.',jsonb_build_object('tenant_id', public.platform_try_uuid(v_details->>'tenant_id'),'tenant_schema', v_details->>'tenant_schema','actor_user_id', public.platform_current_actor_user_id()));
exception
  when others then
    return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_rcm_resolve_context.',jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_rcm_log_conversion_event_internal(
  p_schema_name text,
  p_conversion_case_id uuid,
  p_event_type text,
  p_event_details jsonb default '{}'::jsonb,
  p_actor_user_id uuid default null
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  execute format(
    'insert into %I.rcm_conversion_event_log (conversion_case_id, event_type, event_details, actor_user_id) values ($1, $2, $3, $4)',
    p_schema_name
  )
  using p_conversion_case_id, p_event_type, coalesce(p_event_details, '{}'::jsonb), p_actor_user_id;
end;
$function$;

create or replace function public.platform_apply_recruitment_and_conversion_to_tenant(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_template_version text := public.platform_rcm_module_template_version();
  v_hierarchy_result jsonb;
  v_apply_result jsonb;
  v_context_result jsonb;
  v_context_details jsonb;
  v_schema_name text;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Internal caller is required.', '{}'::jsonb);
  end if;

  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  v_hierarchy_result := public.platform_apply_hierarchy_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_apply_recruitment_and_conversion_to_tenant')));
  if coalesce((v_hierarchy_result->>'success')::boolean, false) is not true then
    return v_hierarchy_result;
  end if;

  v_apply_result := public.platform_apply_template_version_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'template_version', v_template_version,'source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_apply_recruitment_and_conversion_to_tenant')));
  if coalesce((v_apply_result->>'success')::boolean, false) is not true then
    return v_apply_result;
  end if;

  v_context_result := public.platform_rcm_resolve_context(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_recruitment_and_conversion_to_tenant'));
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');
  if v_schema_name is null then
    return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_AVAILABLE', 'Tenant schema is not available.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_requisition' and c.conname = 'rcm_requisition_position_fk') then
    execute format('alter table %I.rcm_requisition add constraint rcm_requisition_position_fk foreign key (position_id) references %I.hierarchy_position(position_id) on delete restrict',v_schema_name,v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_job_application' and c.conname = 'rcm_job_application_requisition_fk') then
    execute format('alter table %I.rcm_job_application add constraint rcm_job_application_requisition_fk foreign key (requisition_id) references %I.rcm_requisition(requisition_id) on delete cascade',v_schema_name,v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_job_application' and c.conname = 'rcm_job_application_candidate_fk') then
    execute format('alter table %I.rcm_job_application add constraint rcm_job_application_candidate_fk foreign key (candidate_id) references %I.rcm_candidate(candidate_id) on delete cascade',v_schema_name,v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_application_stage_event' and c.conname = 'rcm_stage_event_application_fk') then
    execute format('alter table %I.rcm_application_stage_event add constraint rcm_stage_event_application_fk foreign key (application_id) references %I.rcm_job_application(application_id) on delete cascade',v_schema_name,v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_conversion_case' and c.conname = 'rcm_conversion_case_application_fk') then
    execute format('alter table %I.rcm_conversion_case add constraint rcm_conversion_case_application_fk foreign key (application_id) references %I.rcm_job_application(application_id) on delete restrict',v_schema_name,v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_conversion_case' and c.conname = 'rcm_conversion_case_candidate_fk') then
    execute format('alter table %I.rcm_conversion_case add constraint rcm_conversion_case_candidate_fk foreign key (candidate_id) references %I.rcm_candidate(candidate_id) on delete restrict',v_schema_name,v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_conversion_case' and c.conname = 'rcm_conversion_case_requisition_fk') then
    execute format('alter table %I.rcm_conversion_case add constraint rcm_conversion_case_requisition_fk foreign key (requisition_id) references %I.rcm_requisition(requisition_id) on delete restrict',v_schema_name,v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_conversion_case' and c.conname = 'rcm_conversion_case_position_fk') then
    execute format('alter table %I.rcm_conversion_case add constraint rcm_conversion_case_position_fk foreign key (target_position_id) references %I.hierarchy_position(position_id) on delete restrict',v_schema_name,v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_conversion_case' and c.conname = 'rcm_conversion_case_employee_fk') then
    execute format('alter table %I.rcm_conversion_case add constraint rcm_conversion_case_employee_fk foreign key (wcm_employee_id) references %I.wcm_employee(employee_id) on delete restrict',v_schema_name,v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_conversion_event_log' and c.conname = 'rcm_conversion_event_log_case_fk') then
    execute format('alter table %I.rcm_conversion_event_log add constraint rcm_conversion_event_log_case_fk foreign key (conversion_case_id) references %I.rcm_conversion_case(conversion_case_id) on delete cascade',v_schema_name,v_schema_name);
  end if;

  if not exists (select 1 from pg_trigger tg join pg_class t on t.oid = tg.tgrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_requisition' and tg.tgname = 'trg_rcm_requisition_set_updated_at' and not tg.tgisinternal) then
    execute format('create trigger trg_rcm_requisition_set_updated_at before update on %I.rcm_requisition for each row execute function public.platform_set_updated_at()',v_schema_name);
  end if;
  if not exists (select 1 from pg_trigger tg join pg_class t on t.oid = tg.tgrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_candidate' and tg.tgname = 'trg_rcm_candidate_set_updated_at' and not tg.tgisinternal) then
    execute format('create trigger trg_rcm_candidate_set_updated_at before update on %I.rcm_candidate for each row execute function public.platform_set_updated_at()',v_schema_name);
  end if;
  if not exists (select 1 from pg_trigger tg join pg_class t on t.oid = tg.tgrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_job_application' and tg.tgname = 'trg_rcm_job_application_set_updated_at' and not tg.tgisinternal) then
    execute format('create trigger trg_rcm_job_application_set_updated_at before update on %I.rcm_job_application for each row execute function public.platform_set_updated_at()',v_schema_name);
  end if;
  if not exists (select 1 from pg_trigger tg join pg_class t on t.oid = tg.tgrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'rcm_conversion_case' and tg.tgname = 'trg_rcm_conversion_case_set_updated_at' and not tg.tgisinternal) then
    execute format('create trigger trg_rcm_conversion_case_set_updated_at before update on %I.rcm_conversion_case for each row execute function public.platform_set_updated_at()',v_schema_name);
  end if;

  return public.platform_json_response(true,'OK','RECRUITMENT_AND_CONVERSION applied to tenant schema.',jsonb_build_object('tenant_id', v_tenant_id,'tenant_schema', v_schema_name,'template_version', v_template_version,'hierarchy_apply', v_hierarchy_result->'details','template_apply', v_apply_result->'details'));
exception
  when others then
    return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_apply_recruitment_and_conversion_to_tenant.',jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm, 'tenant_id', v_tenant_id));
end;
$function$;;
