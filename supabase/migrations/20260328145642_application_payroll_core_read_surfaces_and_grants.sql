set search_path = public, pg_temp;

create or replace function public.platform_payroll_area_catalog_rows()
returns table (
  tenant_id uuid,
  payroll_area_id uuid,
  area_code text,
  area_name text,
  payroll_frequency text,
  currency_code text,
  country_code text,
  area_status text,
  area_metadata jsonb,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_payroll_core_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format('select $1::uuid, payroll_area_id, area_code, area_name, payroll_frequency, currency_code, country_code, area_status, area_metadata, created_at, updated_at from %I.wcm_payroll_area order by area_code', v_schema_name) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_payroll_area_catalog with (security_invoker = true) as select * from public.platform_payroll_area_catalog_rows();

create or replace function public.platform_pay_structure_catalog_rows()
returns table (
  tenant_id uuid,
  pay_structure_id uuid,
  payroll_area_id uuid,
  structure_code text,
  structure_name text,
  structure_status text,
  active_version_no integer,
  component_count bigint,
  effective_from date,
  effective_to date,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_payroll_core_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format('select $1::uuid, ps.pay_structure_id, ps.payroll_area_id, ps.structure_code, ps.structure_name, ps.structure_status, ps.active_version_no, count(psc.pay_structure_component_id)::bigint as component_count, ps.effective_from, ps.effective_to, ps.updated_at from %I.wcm_pay_structure ps left join %I.wcm_pay_structure_component psc on psc.pay_structure_id = ps.pay_structure_id and psc.component_status = ''ACTIVE'' group by ps.pay_structure_id order by ps.structure_code', v_schema_name, v_schema_name) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_pay_structure_catalog with (security_invoker = true) as select * from public.platform_pay_structure_catalog_rows();

create or replace function public.platform_employee_pay_structure_assignment_rows()
returns table (
  tenant_id uuid,
  employee_pay_structure_assignment_id uuid,
  employee_id uuid,
  employee_code text,
  employee_name text,
  pay_structure_id uuid,
  structure_code text,
  pay_structure_version_id uuid,
  effective_from date,
  effective_to date,
  assignment_status text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_payroll_core_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format('select $1::uuid, a.employee_pay_structure_assignment_id, a.employee_id, e.employee_code, trim(concat_ws('' '', e.first_name, e.last_name)), a.pay_structure_id, ps.structure_code, a.pay_structure_version_id, a.effective_from, a.effective_to, a.assignment_status, a.updated_at from %I.wcm_employee_pay_structure_assignment a join %I.wcm_employee e on e.employee_id = a.employee_id join %I.wcm_pay_structure ps on ps.pay_structure_id = a.pay_structure_id order by a.effective_from desc, e.employee_code', v_schema_name, v_schema_name, v_schema_name) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_employee_pay_structure_assignment with (security_invoker = true) as select * from public.platform_employee_pay_structure_assignment_rows();

create or replace function public.platform_payroll_result_summary_rows()
returns table (
  tenant_id uuid,
  payroll_batch_id uuid,
  payroll_period date,
  employee_id uuid,
  employee_code text,
  gross_earnings numeric,
  total_deductions numeric,
  employer_contributions numeric,
  net_pay numeric,
  batch_status text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_payroll_core_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, r.payroll_batch_id, r.payroll_period, r.employee_id, e.employee_code,
            coalesce(sum(case when r.component_kind = ''EARNING'' then r.calculated_amount else 0 end), 0) as gross_earnings,
            coalesce(sum(case when r.component_kind = ''DEDUCTION'' then r.calculated_amount else 0 end), 0) as total_deductions,
            coalesce(sum(case when r.component_kind = ''EMPLOYER_CONTRIBUTION'' then r.calculated_amount else 0 end), 0) as employer_contributions,
            coalesce(max(case when r.component_code = ''NET_PAY'' then r.calculated_amount end), coalesce(sum(case when r.component_kind = ''EARNING'' then r.calculated_amount else 0 end), 0) - coalesce(sum(case when r.component_kind = ''DEDUCTION'' then r.calculated_amount else 0 end), 0)) as net_pay,
            b.batch_status,
            max(r.updated_at) as updated_at
       from %I.wcm_component_calculation_result r
       join %I.wcm_payroll_batch b on b.payroll_batch_id = r.payroll_batch_id
       join %I.wcm_employee e on e.employee_id = r.employee_id
      group by r.payroll_batch_id, r.payroll_period, r.employee_id, e.employee_code, b.batch_status
      order by r.payroll_period desc, e.employee_code',
    v_schema_name,
    v_schema_name,
    v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_payroll_result_summary with (security_invoker = true) as select * from public.platform_payroll_result_summary_rows();

create or replace function public.platform_payroll_batch_catalog_rows()
returns table (
  tenant_id uuid,
  payroll_batch_id uuid,
  payroll_period date,
  processing_type text,
  batch_status text,
  total_employees integer,
  processed_employees integer,
  failed_employees integer,
  gross_earnings numeric,
  total_deductions numeric,
  net_pay numeric,
  processed_at timestamptz,
  finalized_at timestamptz,
  last_error text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_payroll_core_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, b.payroll_batch_id, b.payroll_period, b.processing_type, b.batch_status, b.total_employees, b.processed_employees, b.failed_employees,
            coalesce(sum(case when r.component_kind = ''EARNING'' then r.calculated_amount else 0 end), 0) as gross_earnings,
            coalesce(sum(case when r.component_kind = ''DEDUCTION'' then r.calculated_amount else 0 end), 0) as total_deductions,
            coalesce(sum(case when r.component_kind = ''EARNING'' then r.calculated_amount else 0 end), 0) - coalesce(sum(case when r.component_kind = ''DEDUCTION'' then r.calculated_amount else 0 end), 0) as net_pay,
            b.processed_at, b.finalized_at, b.last_error, b.updated_at
       from %I.wcm_payroll_batch b
       left join %I.wcm_component_calculation_result r on r.payroll_batch_id = b.payroll_batch_id
      group by b.payroll_batch_id
      order by b.payroll_period desc, b.created_at desc',
    v_schema_name,
    v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_payroll_batch_catalog with (security_invoker = true) as select * from public.platform_payroll_batch_catalog_rows();

create or replace function public.platform_employee_payslip_history_rows()
returns table (
  tenant_id uuid,
  payslip_run_id uuid,
  payslip_item_id uuid,
  payroll_period date,
  employee_id uuid,
  employee_code text,
  item_status text,
  artifact_status text,
  generated_document_id uuid,
  completed_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_payroll_core_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format('select $1::uuid, i.payslip_run_id, i.payslip_item_id, r.payroll_period, i.employee_id, e.employee_code, i.item_status, i.artifact_status, i.generated_document_id, i.completed_at, i.updated_at from %I.wcm_payslip_item i join %I.wcm_payslip_run r on r.payslip_run_id = i.payslip_run_id join %I.wcm_employee e on e.employee_id = i.employee_id order by r.payroll_period desc, e.employee_code', v_schema_name, v_schema_name, v_schema_name) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_employee_payslip_history with (security_invoker = true) as select * from public.platform_employee_payslip_history_rows();

create or replace function public.platform_payslip_run_status_rows()
returns table (
  tenant_id uuid,
  payslip_run_id uuid,
  payroll_batch_id uuid,
  payroll_period date,
  run_status text,
  total_items bigint,
  completed_items bigint,
  failed_items bigint,
  dead_letter_items bigint,
  completed_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_payroll_core_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format('select $1::uuid, r.payslip_run_id, r.payroll_batch_id, r.payroll_period, r.run_status, count(i.payslip_item_id)::bigint as total_items, count(*) filter (where i.item_status = ''COMPLETED'')::bigint as completed_items, count(*) filter (where i.item_status = ''FAILED'')::bigint as failed_items, count(*) filter (where i.item_status = ''DEAD_LETTER'')::bigint as dead_letter_items, r.completed_at, r.updated_at from %I.wcm_payslip_run r left join %I.wcm_payslip_item i on i.payslip_run_id = r.payslip_run_id group by r.payslip_run_id order by r.payroll_period desc, r.created_at desc', v_schema_name, v_schema_name) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_payslip_run_status with (security_invoker = true) as select * from public.platform_payslip_run_status_rows();

revoke all on public.wcm_payroll_area from public, anon, authenticated;
revoke all on public.wcm_component from public, anon, authenticated;
revoke all on public.wcm_component_dependency from public, anon, authenticated;
revoke all on public.wcm_component_rule_template from public, anon, authenticated;
revoke all on public.wcm_pay_structure from public, anon, authenticated;
revoke all on public.wcm_pay_structure_component from public, anon, authenticated;
revoke all on public.wcm_pay_structure_version from public, anon, authenticated;
revoke all on public.wcm_employee_pay_structure_assignment from public, anon, authenticated;
revoke all on public.wcm_payroll_input_entry from public, anon, authenticated;
revoke all on public.wcm_payroll_batch from public, anon, authenticated;
revoke all on public.wcm_component_calculation_result from public, anon, authenticated;
revoke all on public.wcm_preview_simulation from public, anon, authenticated;
revoke all on public.wcm_payslip_run from public, anon, authenticated;
revoke all on public.wcm_payslip_item from public, anon, authenticated;
revoke all on public.wcm_payslip_audit_event from public, anon, authenticated;
revoke all on public.platform_rm_payroll_area_catalog from public, anon, authenticated;
revoke all on public.platform_rm_pay_structure_catalog from public, anon, authenticated;
revoke all on public.platform_rm_employee_pay_structure_assignment from public, anon, authenticated;
revoke all on public.platform_rm_payroll_batch_catalog from public, anon, authenticated;
revoke all on public.platform_rm_payroll_result_summary from public, anon, authenticated;
revoke all on public.platform_rm_employee_payslip_history from public, anon, authenticated;
revoke all on public.platform_rm_payslip_run_status from public, anon, authenticated;

revoke all on function public.platform_payroll_core_module_template_version() from public, anon, authenticated;
revoke all on function public.platform_payroll_core_try_date(text) from public, anon, authenticated;
revoke all on function public.platform_payroll_core_try_numeric(text) from public, anon, authenticated;
revoke all on function public.platform_payroll_core_try_integer(text) from public, anon, authenticated;
revoke all on function public.platform_payroll_core_append_audit(text,text,text,jsonb,uuid,uuid,uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function public.platform_payroll_core_resolve_context(jsonb) from public, anon, authenticated;
revoke all on function public.platform_apply_payroll_core_to_tenant(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_payroll_area(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_payroll_component(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_component_dependency(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_component_rule_template(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_pay_structure(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_pay_structure_component(jsonb) from public, anon, authenticated;
revoke all on function public.platform_validate_pay_structure(jsonb) from public, anon, authenticated;
revoke all on function public.platform_activate_pay_structure(jsonb) from public, anon, authenticated;
revoke all on function public.platform_assign_employee_pay_structure(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_employee_pay_structure_components(jsonb) from public, anon, authenticated;
revoke all on function public.platform_payroll_core_write_input_entry(text,uuid,date,text,text,text,bigint,numeric,text,jsonb,jsonb,text) from public, anon, authenticated;
revoke all on function public.platform_upsert_payroll_input_entry(jsonb) from public, anon, authenticated;
revoke all on function public.platform_payroll_core_sync_tps_inputs(text,uuid,date,bigint) from public, anon, authenticated;
revoke all on function public.platform_payroll_core_input_map(text,uuid,date) from public, anon, authenticated;
revoke all on function public.platform_payroll_core_result_snapshot(text,uuid,uuid) from public, anon, authenticated;
revoke all on function public.platform_payroll_core_calculate_employee_batch(text,uuid,uuid,date,jsonb,uuid) from public, anon, authenticated;
revoke all on function public.platform_request_payroll_batch(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_payroll_batch_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_finalize_payroll_batch(jsonb) from public, anon, authenticated;
revoke all on function public.platform_request_payroll_preview(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_payroll_preview(jsonb) from public, anon, authenticated;
revoke all on function public.platform_request_payslip_run(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_payslip_run_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_employee_payslip(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_payroll_batch_status(jsonb) from public, anon, authenticated;
revoke all on function public.platform_payroll_area_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_pay_structure_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_employee_pay_structure_assignment_rows() from public, anon, authenticated;
revoke all on function public.platform_payroll_batch_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_payroll_result_summary_rows() from public, anon, authenticated;
revoke all on function public.platform_employee_payslip_history_rows() from public, anon, authenticated;
revoke all on function public.platform_payslip_run_status_rows() from public, anon, authenticated;

grant select on public.platform_rm_payroll_area_catalog to service_role;
grant select on public.platform_rm_pay_structure_catalog to service_role;
grant select on public.platform_rm_employee_pay_structure_assignment to service_role;
grant select on public.platform_rm_payroll_batch_catalog to service_role;
grant select on public.platform_rm_payroll_result_summary to service_role;
grant select on public.platform_rm_employee_payslip_history to service_role;
grant select on public.platform_rm_payslip_run_status to service_role;
grant execute on function public.platform_payroll_core_module_template_version() to service_role;
grant execute on function public.platform_payroll_core_resolve_context(jsonb) to service_role;
grant execute on function public.platform_apply_payroll_core_to_tenant(jsonb) to service_role;
grant execute on function public.platform_register_payroll_area(jsonb) to service_role;
grant execute on function public.platform_register_payroll_component(jsonb) to service_role;
grant execute on function public.platform_register_component_dependency(jsonb) to service_role;
grant execute on function public.platform_register_component_rule_template(jsonb) to service_role;
grant execute on function public.platform_register_pay_structure(jsonb) to service_role;
grant execute on function public.platform_upsert_pay_structure_component(jsonb) to service_role;
grant execute on function public.platform_validate_pay_structure(jsonb) to service_role;
grant execute on function public.platform_activate_pay_structure(jsonb) to service_role;
grant execute on function public.platform_assign_employee_pay_structure(jsonb) to service_role;
grant execute on function public.platform_get_employee_pay_structure_components(jsonb) to service_role;
grant execute on function public.platform_upsert_payroll_input_entry(jsonb) to service_role;
grant execute on function public.platform_request_payroll_batch(jsonb) to service_role;
grant execute on function public.platform_process_payroll_batch_job(jsonb) to service_role;
grant execute on function public.platform_finalize_payroll_batch(jsonb) to service_role;
grant execute on function public.platform_request_payroll_preview(jsonb) to service_role;
grant execute on function public.platform_get_payroll_preview(jsonb) to service_role;
grant execute on function public.platform_request_payslip_run(jsonb) to service_role;
grant execute on function public.platform_process_payslip_run_job(jsonb) to service_role;
grant execute on function public.platform_get_employee_payslip(jsonb) to service_role;
grant execute on function public.platform_get_payroll_batch_status(jsonb) to service_role;;
