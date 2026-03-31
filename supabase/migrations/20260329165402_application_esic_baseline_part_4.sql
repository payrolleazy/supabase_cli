create or replace function public.platform_esic_configuration_catalog_rows()
returns table (
  tenant_id uuid,
  configuration_id uuid,
  state_code text,
  effective_from date,
  effective_to date,
  wage_ceiling numeric,
  employee_contribution_rate numeric,
  employer_contribution_rate numeric,
  configuration_status text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_esic_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format('select $1::uuid, configuration_id, state_code, effective_from, effective_to, wage_ceiling, employee_contribution_rate, employer_contribution_rate, configuration_status, updated_at from %I.wcm_esic_configuration order by state_code, effective_from desc', v_schema_name) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_esic_configuration_catalog as select * from public.platform_esic_configuration_catalog_rows();

create or replace function public.platform_esic_establishment_catalog_rows()
returns table (
  tenant_id uuid,
  establishment_id uuid,
  establishment_code text,
  establishment_name text,
  registration_code text,
  state_code text,
  establishment_status text,
  coverage_start_date date,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_esic_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format('select $1::uuid, establishment_id, establishment_code, establishment_name, registration_code, state_code, establishment_status, coverage_start_date, updated_at from %I.wcm_esic_establishment order by establishment_code', v_schema_name) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_esic_establishment_catalog as select * from public.platform_esic_establishment_catalog_rows();

create or replace function public.platform_esic_registration_status_rows()
returns table (
  tenant_id uuid,
  registration_id uuid,
  employee_id uuid,
  employee_code text,
  establishment_id uuid,
  establishment_code text,
  ip_number text,
  registration_status text,
  registration_date date,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_esic_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, r.registration_id, r.employee_id, e.employee_code, r.establishment_id, s.establishment_code, r.ip_number, r.registration_status, r.registration_date, r.updated_at
       from %I.wcm_esic_employee_registration r
       join %I.wcm_employee e on e.employee_id = r.employee_id
       join %I.wcm_esic_establishment s on s.establishment_id = r.establishment_id
      order by r.registration_date desc, e.employee_code',
    v_schema_name, v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_esic_registration_status as select * from public.platform_esic_registration_status_rows();

create or replace function public.platform_esic_benefit_period_status_rows()
returns table (
  tenant_id uuid,
  benefit_period_id uuid,
  employee_id uuid,
  employee_code text,
  contribution_period_start date,
  contribution_period_end date,
  benefit_period_start date,
  benefit_period_end date,
  total_days_worked numeric,
  total_wages_paid numeric,
  is_eligible boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_esic_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, b.benefit_period_id, b.employee_id, e.employee_code, b.contribution_period_start, b.contribution_period_end, b.benefit_period_start, b.benefit_period_end, b.total_days_worked, b.total_wages_paid, b.is_eligible, b.updated_at
       from %I.wcm_esic_employee_benefit_period b
       join %I.wcm_employee e on e.employee_id = b.employee_id
      order by b.contribution_period_start desc, e.employee_code',
    v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_esic_benefit_period_status as select * from public.platform_esic_benefit_period_status_rows();

create or replace function public.platform_esic_batch_catalog_rows()
returns table (
  tenant_id uuid,
  batch_id bigint,
  establishment_id uuid,
  establishment_code text,
  payroll_period date,
  return_period text,
  batch_status text,
  worker_job_id uuid,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_esic_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, b.batch_id, b.establishment_id, e.establishment_code, b.payroll_period, b.return_period, b.batch_status, b.worker_job_id, b.updated_at
       from %I.wcm_esic_processing_batch b
       join %I.wcm_esic_establishment e on e.establishment_id = b.establishment_id
      order by b.payroll_period desc, b.batch_id desc',
    v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_esic_batch_catalog as select * from public.platform_esic_batch_catalog_rows();

create or replace function public.platform_esic_challan_run_status_rows()
returns table (
  tenant_id uuid,
  challan_run_id uuid,
  batch_id bigint,
  payroll_period date,
  return_period text,
  run_status text,
  reconciliation_status text,
  total_contribution numeric,
  payment_amount numeric,
  discrepancy_amount numeric,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_esic_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, challan_run_id, batch_id, payroll_period, return_period, run_status, reconciliation_status, total_contribution, payment_amount, discrepancy_amount, updated_at
       from %I.wcm_esic_challan_run
      order by payroll_period desc, challan_run_id desc',
    v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_esic_challan_run_status as select * from public.platform_esic_challan_run_status_rows();

create or replace function public.platform_esic_contribution_ledger_rows()
returns table (
  tenant_id uuid,
  contribution_ledger_id uuid,
  batch_id bigint,
  employee_id uuid,
  employee_code text,
  payroll_period date,
  eligible_wages numeric,
  employee_contribution numeric,
  employer_contribution numeric,
  total_contribution numeric,
  sync_status text
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_esic_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, l.contribution_ledger_id, l.batch_id, l.employee_id, e.employee_code, l.payroll_period, l.eligible_wages, l.employee_contribution, l.employer_contribution, l.total_contribution, l.sync_status
       from %I.wcm_esic_contribution_ledger l
       join %I.wcm_employee e on e.employee_id = l.employee_id
      order by l.payroll_period desc, e.employee_code',
    v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_esic_contribution_ledger as select * from public.platform_esic_contribution_ledger_rows();

revoke all on function public.platform_esic_module_template_version() from public, anon, authenticated;
revoke all on function public.platform_esic_try_numeric(text) from public, anon, authenticated;
revoke all on function public.platform_esic_try_date(text) from public, anon, authenticated;
revoke all on function public.platform_esic_resolve_context(jsonb) from public, anon, authenticated;
revoke all on function public.platform_esic_append_audit(text,text,text,text,text,jsonb,uuid,uuid,bigint) from public, anon, authenticated;
revoke all on function public.platform_esic_benefit_period_window(date) from public, anon, authenticated;
revoke all on function public.platform_apply_esic_to_tenant(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_esic_configuration(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_esic_establishment(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_esic_employee_registration(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_esic_wage_component_mapping(jsonb) from public, anon, authenticated;
revoke all on function public.platform_esic_sync_deduction_to_payroll_internal(text,uuid,uuid,date,bigint,text,numeric,numeric) from public, anon, authenticated;
revoke all on function public.platform_esic_refresh_benefit_period_internal(text,uuid,date,uuid) from public, anon, authenticated;
revoke all on function public.platform_request_esic_batch(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_esic_batch_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_request_esic_challan_run(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_esic_challan_run_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_reconcile_esic_payment(jsonb) from public, anon, authenticated;
revoke all on function public.platform_esic_configuration_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_esic_establishment_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_esic_registration_status_rows() from public, anon, authenticated;
revoke all on function public.platform_esic_benefit_period_status_rows() from public, anon, authenticated;
revoke all on function public.platform_esic_batch_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_esic_challan_run_status_rows() from public, anon, authenticated;
revoke all on function public.platform_esic_contribution_ledger_rows() from public, anon, authenticated;

grant execute on function public.platform_esic_module_template_version() to service_role;
grant execute on function public.platform_esic_resolve_context(jsonb) to service_role;
grant execute on function public.platform_apply_esic_to_tenant(jsonb) to service_role;
grant execute on function public.platform_upsert_esic_configuration(jsonb) to service_role;
grant execute on function public.platform_register_esic_establishment(jsonb) to service_role;
grant execute on function public.platform_register_esic_employee_registration(jsonb) to service_role;
grant execute on function public.platform_upsert_esic_wage_component_mapping(jsonb) to service_role;
grant execute on function public.platform_request_esic_batch(jsonb) to service_role;
grant execute on function public.platform_process_esic_batch_job(jsonb) to service_role;
grant execute on function public.platform_request_esic_challan_run(jsonb) to service_role;
grant execute on function public.platform_process_esic_challan_run_job(jsonb) to service_role;
grant execute on function public.platform_reconcile_esic_payment(jsonb) to service_role;
grant execute on function public.platform_esic_configuration_catalog_rows() to service_role;
grant execute on function public.platform_esic_establishment_catalog_rows() to service_role;
grant execute on function public.platform_esic_registration_status_rows() to service_role;
grant execute on function public.platform_esic_benefit_period_status_rows() to service_role;
grant execute on function public.platform_esic_batch_catalog_rows() to service_role;
grant execute on function public.platform_esic_challan_run_status_rows() to service_role;
grant execute on function public.platform_esic_contribution_ledger_rows() to service_role;

grant select on public.platform_rm_esic_configuration_catalog to service_role;
grant select on public.platform_rm_esic_establishment_catalog to service_role;
grant select on public.platform_rm_esic_registration_status to service_role;
grant select on public.platform_rm_esic_benefit_period_status to service_role;
grant select on public.platform_rm_esic_batch_catalog to service_role;
grant select on public.platform_rm_esic_challan_run_status to service_role;
grant select on public.platform_rm_esic_contribution_ledger to service_role;

do $$
declare
  v_template_version text := public.platform_esic_module_template_version();
  v_result jsonb;
begin
  v_result := public.platform_register_template_version(jsonb_build_object(
    'template_version', v_template_version,
    'template_scope', 'module',
    'module_code', 'ESIC',
    'template_status', 'released',
    'description', 'ESIC tenant-owned employee-state-insurance statutory engine baseline.',
    'metadata', jsonb_build_object('slice', 'ESIC', 'module_code', 'ESIC')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ESIC template version registration failed: %', v_result::text; end if;

  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'ESIC','source_schema_name', 'public','source_table_name', 'wcm_esic_configuration','target_table_name', 'wcm_esic_configuration','clone_order', 100,'notes', jsonb_build_object('slice', 'ESIC','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ESIC configuration table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'ESIC','source_schema_name', 'public','source_table_name', 'wcm_esic_establishment','target_table_name', 'wcm_esic_establishment','clone_order', 110,'notes', jsonb_build_object('slice', 'ESIC','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ESIC establishment table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'ESIC','source_schema_name', 'public','source_table_name', 'wcm_esic_employee_registration','target_table_name', 'wcm_esic_employee_registration','clone_order', 120,'notes', jsonb_build_object('slice', 'ESIC','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ESIC registration table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'ESIC','source_schema_name', 'public','source_table_name', 'wcm_esic_employee_benefit_period','target_table_name', 'wcm_esic_employee_benefit_period','clone_order', 130,'notes', jsonb_build_object('slice', 'ESIC','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ESIC benefit period table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'ESIC','source_schema_name', 'public','source_table_name', 'wcm_esic_wage_component_mapping','target_table_name', 'wcm_esic_wage_component_mapping','clone_order', 140,'notes', jsonb_build_object('slice', 'ESIC','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ESIC wage mapping table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'ESIC','source_schema_name', 'public','source_table_name', 'wcm_esic_processing_batch','target_table_name', 'wcm_esic_processing_batch','clone_order', 150,'notes', jsonb_build_object('slice', 'ESIC','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ESIC processing batch table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'ESIC','source_schema_name', 'public','source_table_name', 'wcm_esic_contribution_ledger','target_table_name', 'wcm_esic_contribution_ledger','clone_order', 160,'notes', jsonb_build_object('slice', 'ESIC','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ESIC ledger table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'ESIC','source_schema_name', 'public','source_table_name', 'wcm_esic_challan_run','target_table_name', 'wcm_esic_challan_run','clone_order', 170,'notes', jsonb_build_object('slice', 'ESIC','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ESIC challan table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'ESIC','source_schema_name', 'public','source_table_name', 'wcm_esic_audit_event','target_table_name', 'wcm_esic_audit_event','clone_order', 180,'notes', jsonb_build_object('slice', 'ESIC','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ESIC audit table registration failed: %', v_result::text; end if;

  v_result := public.platform_register_async_worker(jsonb_build_object(
    'worker_code', 'esic_monthly_worker',
    'module_code', 'ESIC',
    'dispatch_mode', 'db_inline_handler',
    'handler_contract', 'platform_process_esic_batch_job',
    'is_active', true,
    'max_batch_size', 4,
    'default_lease_seconds', 600,
    'heartbeat_grace_seconds', 900,
    'retry_backoff_policy', jsonb_build_object('base_seconds', 90, 'multiplier', 2, 'max_seconds', 3600),
    'metadata', jsonb_build_object('slice', 'ESIC', 'notes', 'First clean ESIC monthly worker on shared F04 spine.')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ESIC monthly worker registration failed: %', v_result::text; end if;

  v_result := public.platform_register_async_worker(jsonb_build_object(
    'worker_code', 'esic_challan_worker',
    'module_code', 'ESIC',
    'dispatch_mode', 'db_inline_handler',
    'handler_contract', 'platform_process_esic_challan_run_job',
    'is_active', true,
    'max_batch_size', 3,
    'default_lease_seconds', 600,
    'heartbeat_grace_seconds', 900,
    'retry_backoff_policy', jsonb_build_object('base_seconds', 120, 'multiplier', 2, 'max_seconds', 3600),
    'metadata', jsonb_build_object('slice', 'ESIC', 'notes', 'First clean ESIC challan generation worker on shared F04 spine.')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'ESIC challan worker registration failed: %', v_result::text; end if;
end;
$$;;
