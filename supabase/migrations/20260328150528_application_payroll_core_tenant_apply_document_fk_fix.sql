set search_path = public, pg_temp;

create or replace function public.platform_payroll_core_module_template_version()
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select 'payroll_core_v1'::text;
$function$;

create or replace function public.platform_payroll_core_try_date(p_value text)
returns date
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $function$
begin
  if nullif(btrim(coalesce(p_value, '')), '') is null then return null; end if;
  return p_value::date;
exception when others then return null;
end;
$function$;

create or replace function public.platform_payroll_core_try_numeric(p_value text)
returns numeric
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $function$
begin
  if nullif(btrim(coalesce(p_value, '')), '') is null then return null; end if;
  return p_value::numeric;
exception when others then return null;
end;
$function$;

create or replace function public.platform_payroll_core_try_integer(p_value text)
returns integer
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $function$
begin
  if nullif(btrim(coalesce(p_value, '')), '') is null then return null; end if;
  return p_value::integer;
exception when others then return null;
end;
$function$;

create or replace function public.platform_payroll_core_append_audit(
  p_schema_name text,
  p_event_type text,
  p_event_source text,
  p_event_details jsonb,
  p_payslip_run_id uuid default null,
  p_payslip_item_id uuid default null,
  p_payroll_batch_id uuid default null,
  p_employee_id uuid default null,
  p_actor_user_id uuid default null
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  execute format(
    'insert into %I.wcm_payslip_audit_event (payslip_run_id, payslip_item_id, payroll_batch_id, employee_id, event_type, event_source, event_details, actor_user_id) values ($1,$2,$3,$4,$5,$6,coalesce($7,''{}''::jsonb),$8)',
    p_schema_name
  ) using p_payslip_run_id, p_payslip_item_id, p_payroll_batch_id, p_employee_id, p_event_type, p_event_source, p_event_details, p_actor_user_id;
end;
$function$;

create or replace function public.platform_payroll_core_resolve_context(p_params jsonb default '{}'::jsonb)
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
      or not public.platform_table_exists(v_current_schema, 'hierarchy_position')
      or not public.platform_table_exists(v_current_schema, 'tps_employee_period_summary')
      or not public.platform_table_exists(v_current_schema, 'wcm_payroll_area')
      or not public.platform_table_exists(v_current_schema, 'wcm_component')
      or not public.platform_table_exists(v_current_schema, 'wcm_component_dependency')
      or not public.platform_table_exists(v_current_schema, 'wcm_component_rule_template')
      or not public.platform_table_exists(v_current_schema, 'wcm_pay_structure')
      or not public.platform_table_exists(v_current_schema, 'wcm_pay_structure_component')
      or not public.platform_table_exists(v_current_schema, 'wcm_pay_structure_version')
      or not public.platform_table_exists(v_current_schema, 'wcm_employee_pay_structure_assignment')
      or not public.platform_table_exists(v_current_schema, 'wcm_payroll_input_entry')
      or not public.platform_table_exists(v_current_schema, 'wcm_payroll_batch')
      or not public.platform_table_exists(v_current_schema, 'wcm_component_calculation_result')
      or not public.platform_table_exists(v_current_schema, 'wcm_preview_simulation')
      or not public.platform_table_exists(v_current_schema, 'wcm_payslip_run')
      or not public.platform_table_exists(v_current_schema, 'wcm_payslip_item')
      or not public.platform_table_exists(v_current_schema, 'wcm_payslip_audit_event')
    then
      return public.platform_json_response(false,'PAYROLL_CORE_TEMPLATE_NOT_APPLIED','PAYROLL_CORE is not applied to the current tenant schema.',jsonb_build_object('tenant_id', v_current_tenant_id,'tenant_schema', v_current_schema));
    end if;

    return public.platform_json_response(true,'OK','PAYROLL_CORE execution context resolved.',jsonb_build_object('tenant_id', v_current_tenant_id,'tenant_schema', v_current_schema,'actor_user_id', public.platform_current_actor_user_id()));
  end if;

  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false,'TENANT_CONTEXT_REQUIRED','An applied tenant execution context is required.', '{}'::jsonb);
  end if;

  if v_requested_tenant_id is null then
    return public.platform_json_response(false,'TENANT_ID_REQUIRED','tenant_id or tenant_code is required when no execution context is active.', '{}'::jsonb);
  end if;

  v_context_result := public.platform_apply_execution_context(jsonb_build_object(
    'execution_mode', 'internal_platform',
    'tenant_id', v_requested_tenant_id,
    'source', coalesce(nullif(btrim(v_params->>'source'), ''), 'platform_payroll_core_resolve_context')
  ));
  if coalesce((v_context_result->>'success')::boolean, false) is not true then return v_context_result; end if;

  v_details := coalesce(v_context_result->'details', '{}'::jsonb);
  if not public.platform_table_exists(v_details->>'tenant_schema', 'wcm_payroll_area') then
    return public.platform_json_response(false,'PAYROLL_CORE_TEMPLATE_NOT_APPLIED','PAYROLL_CORE is not applied to the requested tenant schema.',jsonb_build_object('tenant_id', public.platform_try_uuid(v_details->>'tenant_id'),'tenant_schema', v_details->>'tenant_schema'));
  end if;

  return public.platform_json_response(true,'OK','PAYROLL_CORE execution context resolved.',jsonb_build_object('tenant_id', public.platform_try_uuid(v_details->>'tenant_id'),'tenant_schema', v_details->>'tenant_schema','actor_user_id', public.platform_current_actor_user_id()));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_payroll_core_resolve_context.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_apply_payroll_core_to_tenant(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_template_version text := public.platform_payroll_core_module_template_version();
  v_dependency_result jsonb;
  v_apply_result jsonb;
  v_context jsonb;
  v_schema_name text;
  v_table_name text;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false,'INTERNAL_CALLER_REQUIRED','Internal caller is required.', '{}'::jsonb);
  end if;
  if v_tenant_id is null then
    return public.platform_json_response(false,'TENANT_ID_REQUIRED','tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  v_dependency_result := public.platform_apply_wcm_core_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_payroll_core_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;
  v_dependency_result := public.platform_apply_hierarchy_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_payroll_core_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;
  v_dependency_result := public.platform_apply_lms_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_payroll_core_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;
  v_dependency_result := public.platform_apply_ams_core_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_payroll_core_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;
  v_dependency_result := public.platform_apply_tps_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_payroll_core_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;

  v_apply_result := public.platform_apply_template_version_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'template_version', v_template_version,'source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_apply_payroll_core_to_tenant')));
  if coalesce((v_apply_result->>'success')::boolean, false) is not true then return v_apply_result; end if;

  v_context := public.platform_payroll_core_resolve_context(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_payroll_core_to_tenant'));
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_pay_structure' and c.conname = 'wcm_pay_structure_payroll_area_fk') then
    execute format('alter table %I.wcm_pay_structure add constraint wcm_pay_structure_payroll_area_fk foreign key (payroll_area_id) references %I.wcm_payroll_area(payroll_area_id) on delete set null', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_component_dependency' and c.conname = 'wcm_component_dependency_component_fk') then
    execute format('alter table %I.wcm_component_dependency add constraint wcm_component_dependency_component_fk foreign key (component_id) references %I.wcm_component(component_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_component_dependency' and c.conname = 'wcm_component_dependency_depends_on_fk') then
    execute format('alter table %I.wcm_component_dependency add constraint wcm_component_dependency_depends_on_fk foreign key (depends_on_component_id) references %I.wcm_component(component_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_component_rule_template' and c.conname = 'wcm_component_rule_template_component_fk') then
    execute format('alter table %I.wcm_component_rule_template add constraint wcm_component_rule_template_component_fk foreign key (component_id) references %I.wcm_component(component_id) on delete set null', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_pay_structure_component' and c.conname = 'wcm_pay_structure_component_structure_fk') then
    execute format('alter table %I.wcm_pay_structure_component add constraint wcm_pay_structure_component_structure_fk foreign key (pay_structure_id) references %I.wcm_pay_structure(pay_structure_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_pay_structure_component' and c.conname = 'wcm_pay_structure_component_component_fk') then
    execute format('alter table %I.wcm_pay_structure_component add constraint wcm_pay_structure_component_component_fk foreign key (component_id) references %I.wcm_component(component_id) on delete restrict', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_pay_structure_version' and c.conname = 'wcm_pay_structure_version_structure_fk') then
    execute format('alter table %I.wcm_pay_structure_version add constraint wcm_pay_structure_version_structure_fk foreign key (pay_structure_id) references %I.wcm_pay_structure(pay_structure_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_employee_pay_structure_assignment' and c.conname = 'wcm_employee_pay_structure_assignment_employee_fk') then
    execute format('alter table %I.wcm_employee_pay_structure_assignment add constraint wcm_employee_pay_structure_assignment_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_employee_pay_structure_assignment' and c.conname = 'wcm_employee_pay_structure_assignment_structure_fk') then
    execute format('alter table %I.wcm_employee_pay_structure_assignment add constraint wcm_employee_pay_structure_assignment_structure_fk foreign key (pay_structure_id) references %I.wcm_pay_structure(pay_structure_id) on delete restrict', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_employee_pay_structure_assignment' and c.conname = 'wcm_employee_pay_structure_assignment_version_fk') then
    execute format('alter table %I.wcm_employee_pay_structure_assignment add constraint wcm_employee_pay_structure_assignment_version_fk foreign key (pay_structure_version_id) references %I.wcm_pay_structure_version(pay_structure_version_id) on delete restrict', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_payroll_input_entry' and c.conname = 'wcm_payroll_input_entry_employee_fk') then
    execute format('alter table %I.wcm_payroll_input_entry add constraint wcm_payroll_input_entry_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_payroll_batch' and c.conname = 'wcm_payroll_batch_area_fk') then
    execute format('alter table %I.wcm_payroll_batch add constraint wcm_payroll_batch_area_fk foreign key (payroll_area_id) references %I.wcm_payroll_area(payroll_area_id) on delete set null', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_component_calculation_result' and c.conname = 'wcm_component_calculation_result_batch_fk') then
    execute format('alter table %I.wcm_component_calculation_result add constraint wcm_component_calculation_result_batch_fk foreign key (payroll_batch_id) references %I.wcm_payroll_batch(payroll_batch_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_component_calculation_result' and c.conname = 'wcm_component_calculation_result_employee_fk') then
    execute format('alter table %I.wcm_component_calculation_result add constraint wcm_component_calculation_result_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_preview_simulation' and c.conname = 'wcm_preview_simulation_employee_fk') then
    execute format('alter table %I.wcm_preview_simulation add constraint wcm_preview_simulation_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_preview_simulation' and c.conname = 'wcm_preview_simulation_structure_fk') then
    execute format('alter table %I.wcm_preview_simulation add constraint wcm_preview_simulation_structure_fk foreign key (pay_structure_id) references %I.wcm_pay_structure(pay_structure_id) on delete set null', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_preview_simulation' and c.conname = 'wcm_preview_simulation_batch_fk') then
    execute format('alter table %I.wcm_preview_simulation add constraint wcm_preview_simulation_batch_fk foreign key (source_batch_id) references %I.wcm_payroll_batch(payroll_batch_id) on delete set null', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_payslip_run' and c.conname = 'wcm_payslip_run_batch_fk') then
    execute format('alter table %I.wcm_payslip_run add constraint wcm_payslip_run_batch_fk foreign key (payroll_batch_id) references %I.wcm_payroll_batch(payroll_batch_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_payslip_item' and c.conname = 'wcm_payslip_item_run_fk') then
    execute format('alter table %I.wcm_payslip_item add constraint wcm_payslip_item_run_fk foreign key (payslip_run_id) references %I.wcm_payslip_run(payslip_run_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_payslip_item' and c.conname = 'wcm_payslip_item_batch_fk') then
    execute format('alter table %I.wcm_payslip_item add constraint wcm_payslip_item_batch_fk foreign key (payroll_batch_id) references %I.wcm_payroll_batch(payroll_batch_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_payslip_item' and c.conname = 'wcm_payslip_item_employee_fk') then
    execute format('alter table %I.wcm_payslip_item add constraint wcm_payslip_item_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_payslip_item' and c.conname = 'wcm_payslip_item_document_fk') then
    execute format('alter table %I.wcm_payslip_item add constraint wcm_payslip_item_document_fk foreign key (generated_document_id) references public.platform_document_record(document_id) on delete set null', v_schema_name);
  end if;

  foreach v_table_name in array array['wcm_payroll_area','wcm_component','wcm_component_rule_template','wcm_pay_structure','wcm_pay_structure_component','wcm_pay_structure_version','wcm_employee_pay_structure_assignment','wcm_payroll_input_entry','wcm_payroll_batch','wcm_component_calculation_result','wcm_preview_simulation','wcm_payslip_run','wcm_payslip_item'] loop
    if not exists (select 1 from pg_trigger tg join pg_class t on t.oid = tg.tgrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = v_table_name and tg.tgname = format('trg_%s_set_updated_at', v_table_name) and not tg.tgisinternal) then
      execute format('create trigger %I before update on %I.%I for each row execute function public.platform_set_updated_at()', format('trg_%s_set_updated_at', v_table_name), v_schema_name, v_table_name);
    end if;
  end loop;

  return public.platform_json_response(true,'OK','PAYROLL_CORE applied to tenant.',jsonb_build_object('tenant_id', v_tenant_id,'tenant_schema', v_schema_name,'template_version', v_template_version));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_apply_payroll_core_to_tenant.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
