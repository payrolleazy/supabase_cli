create or replace function public.platform_ptax_configuration_catalog_rows()
returns table (
  tenant_id uuid,
  configuration_id uuid,
  state_code text,
  effective_from date,
  effective_to date,
  deduction_frequency text,
  configuration_status text,
  configuration_version integer,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_ptax_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format('select $1::uuid, configuration_id, state_code, effective_from, effective_to, deduction_frequency, configuration_status, configuration_version, updated_at from %I.wcm_ptax_configuration order by state_code, effective_from desc', v_schema_name) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_ptax_configuration_catalog as select * from public.platform_ptax_configuration_catalog_rows();

create or replace function public.platform_ptax_batch_catalog_rows()
returns table (
  tenant_id uuid,
  batch_id bigint,
  state_code text,
  payroll_period date,
  batch_status text,
  processed_count integer,
  synced_count integer,
  skipped_count integer,
  error_count integer,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_ptax_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, batch_id, state_code, payroll_period, batch_status, coalesce((summary_payload->>''processed_count'')::integer,0), coalesce((summary_payload->>''synced_count'')::integer,0), coalesce((summary_payload->>''skipped_count'')::integer,0), coalesce((summary_payload->>''error_count'')::integer,0), updated_at
       from %I.wcm_ptax_processing_batch
      order by payroll_period desc, batch_id desc',
    v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_ptax_batch_catalog as select * from public.platform_ptax_batch_catalog_rows();

create or replace function public.platform_ptax_contribution_ledger_rows()
returns table (
  tenant_id uuid,
  contribution_ledger_id uuid,
  batch_id bigint,
  employee_id uuid,
  employee_code text,
  payroll_period date,
  state_code text,
  taxable_wages numeric,
  deduction_amount numeric,
  sync_status text
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_ptax_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, l.contribution_ledger_id, l.batch_id, l.employee_id, e.employee_code, l.payroll_period, l.state_code, l.taxable_wages, l.deduction_amount, l.sync_status
       from %I.wcm_ptax_monthly_ledger l
       join %I.wcm_employee e on e.employee_id = l.employee_id
      order by l.payroll_period desc, e.employee_code',
    v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_ptax_contribution_ledger as select * from public.platform_ptax_contribution_ledger_rows();

create or replace function public.platform_ptax_arrear_queue_rows()
returns table (
  tenant_id uuid,
  arrear_case_id uuid,
  employee_id uuid,
  employee_code text,
  state_code text,
  from_period date,
  to_period date,
  arrear_status text,
  target_payroll_period date,
  total_delta numeric,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_ptax_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, c.arrear_case_id, c.employee_id, e.employee_code, c.state_code, c.from_period, c.to_period, c.arrear_status, c.target_payroll_period, coalesce(sum(a.delta_deduction), 0), c.updated_at
       from %I.wcm_ptax_arrear_case c
       join %I.wcm_employee e on e.employee_id = c.employee_id
       left join %I.wcm_ptax_arrear_computation a on a.arrear_case_id = c.arrear_case_id
      group by c.arrear_case_id, c.employee_id, e.employee_code, c.state_code, c.from_period, c.to_period, c.arrear_status, c.target_payroll_period, c.updated_at
      order by c.updated_at desc, c.arrear_case_id desc',
    v_schema_name, v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_ptax_arrear_queue as select * from public.platform_ptax_arrear_queue_rows();

revoke all on function public.platform_ptax_module_template_version() from public, anon, authenticated;
revoke all on function public.platform_ptax_try_numeric(text) from public, anon, authenticated;
revoke all on function public.platform_ptax_try_date(text) from public, anon, authenticated;
revoke all on function public.platform_ptax_resolve_context(jsonb) from public, anon, authenticated;
revoke all on function public.platform_ptax_append_audit(text,text,text,text,text,jsonb,uuid,uuid,bigint) from public, anon, authenticated;
revoke all on function public.platform_ptax_calculate_from_slabs(numeric,jsonb,date) from public, anon, authenticated;
revoke all on function public.platform_ptax_frequency_applies(text,integer[],date) from public, anon, authenticated;
revoke all on function public.platform_ptax_resolve_employee_state_internal(text,uuid,date) from public, anon, authenticated;
revoke all on function public.platform_ptax_get_employee_gross_wages_internal(text,uuid,date) from public, anon, authenticated;
revoke all on function public.platform_ptax_get_employee_ptax_wages_internal(text,uuid,date,text) from public, anon, authenticated;
revoke all on function public.platform_ptax_sync_deduction_to_payroll_internal(text,uuid,uuid,date,bigint,text,numeric,numeric) from public, anon, authenticated;
revoke all on function public.platform_apply_ptax_to_tenant(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_ptax_configuration(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_ptax_employee_state_profile(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_ptax_wage_component_mapping(jsonb) from public, anon, authenticated;
revoke all on function public.platform_request_ptax_batch(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_ptax_batch_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_request_ptax_retry_batch(jsonb) from public, anon, authenticated;
revoke all on function public.platform_record_ptax_arrear_case(jsonb) from public, anon, authenticated;
revoke all on function public.platform_review_ptax_arrear(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_ptax_arrear_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_ptax_configuration_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_ptax_batch_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_ptax_contribution_ledger_rows() from public, anon, authenticated;
revoke all on function public.platform_ptax_arrear_queue_rows() from public, anon, authenticated;

grant execute on function public.platform_ptax_module_template_version() to service_role;
grant execute on function public.platform_ptax_resolve_context(jsonb) to service_role;
grant execute on function public.platform_apply_ptax_to_tenant(jsonb) to service_role;
grant execute on function public.platform_upsert_ptax_configuration(jsonb) to service_role;
grant execute on function public.platform_upsert_ptax_employee_state_profile(jsonb) to service_role;
grant execute on function public.platform_upsert_ptax_wage_component_mapping(jsonb) to service_role;
grant execute on function public.platform_request_ptax_batch(jsonb) to service_role;
grant execute on function public.platform_process_ptax_batch_job(jsonb) to service_role;
grant execute on function public.platform_request_ptax_retry_batch(jsonb) to service_role;
grant execute on function public.platform_record_ptax_arrear_case(jsonb) to service_role;
grant execute on function public.platform_review_ptax_arrear(jsonb) to service_role;
grant execute on function public.platform_process_ptax_arrear_job(jsonb) to service_role;
grant execute on function public.platform_ptax_configuration_catalog_rows() to service_role;
grant execute on function public.platform_ptax_batch_catalog_rows() to service_role;
grant execute on function public.platform_ptax_contribution_ledger_rows() to service_role;
grant execute on function public.platform_ptax_arrear_queue_rows() to service_role;

grant select on public.platform_rm_ptax_configuration_catalog to service_role;
grant select on public.platform_rm_ptax_batch_catalog to service_role;
grant select on public.platform_rm_ptax_contribution_ledger to service_role;
grant select on public.platform_rm_ptax_arrear_queue to service_role;;
