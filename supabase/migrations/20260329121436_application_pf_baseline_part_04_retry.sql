create or replace function public.platform_pf_establishment_catalog_rows()
returns table (
  tenant_id uuid,
  establishment_id uuid,
  establishment_code text,
  establishment_name text,
  pf_office_code text,
  establishment_status text,
  active_enrollment_count bigint
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid,
            e.establishment_id,
            e.establishment_code,
            e.establishment_name,
            e.pf_office_code,
            e.establishment_status,
            coalesce(count(en.enrollment_id) filter (where en.enrollment_status = ''ACTIVE''), 0)::bigint as active_enrollment_count
       from %I.wcm_pf_establishment e
       left join %I.wcm_pf_employee_enrollment en on en.establishment_id = e.establishment_id
      group by e.establishment_id, e.establishment_code, e.establishment_name, e.pf_office_code, e.establishment_status
      order by e.establishment_code',
    v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_pf_establishment_catalog as select * from public.platform_pf_establishment_catalog_rows();

create or replace function public.platform_pf_enrollment_status_rows()
returns table (
  tenant_id uuid,
  enrollment_id uuid,
  employee_id uuid,
  employee_code text,
  establishment_id uuid,
  enrollment_status text,
  uan text,
  pf_member_id text,
  effective_from date,
  effective_to date
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid,
            e.enrollment_id,
            e.employee_id,
            w.employee_code,
            e.establishment_id,
            e.enrollment_status,
            e.uan,
            e.pf_member_id,
            e.effective_from,
            e.effective_to
       from %I.wcm_pf_employee_enrollment e
       join %I.wcm_employee w on w.employee_id = e.employee_id
      order by w.employee_code, e.effective_from desc',
    v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_pf_enrollment_status as select * from public.platform_pf_enrollment_status_rows();

create or replace function public.platform_pf_batch_catalog_rows()
returns table (
  tenant_id uuid,
  batch_id bigint,
  establishment_id uuid,
  payroll_period date,
  batch_status text,
  processed_count integer,
  anomaly_count integer,
  skipped_count integer,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid,
            b.batch_id,
            b.establishment_id,
            b.payroll_period,
            b.batch_status,
            coalesce((b.summary_payload->>''processed_count'')::integer, 0),
            coalesce((b.summary_payload->>''anomaly_count'')::integer, 0),
            coalesce((b.summary_payload->>''skipped_count'')::integer, 0),
            b.created_at,
            b.updated_at
       from %I.wcm_pf_processing_batch b
      order by b.payroll_period desc, b.batch_id desc',
    v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_pf_batch_catalog as select * from public.platform_pf_batch_catalog_rows();

create or replace function public.platform_pf_anomaly_queue_rows()
returns table (
  tenant_id uuid,
  anomaly_id uuid,
  batch_id bigint,
  employee_id uuid,
  employee_code text,
  anomaly_code text,
  severity text,
  anomaly_status text,
  anomaly_message text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid,
            a.anomaly_id,
            a.batch_id,
            a.employee_id,
            w.employee_code,
            a.anomaly_code,
            a.severity,
            a.anomaly_status,
            a.anomaly_message,
            a.created_at
       from %I.wcm_pf_anomaly a
       join %I.wcm_employee w on w.employee_id = a.employee_id
      order by a.created_at desc, a.anomaly_id desc',
    v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_pf_anomaly_queue as select * from public.platform_pf_anomaly_queue_rows();

create or replace function public.platform_pf_ecr_run_status_rows()
returns table (
  tenant_id uuid,
  ecr_run_id uuid,
  batch_id bigint,
  establishment_id uuid,
  payroll_period date,
  run_status text,
  row_count integer,
  template_document_id uuid,
  generated_document_id uuid,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid,
            r.ecr_run_id,
            r.batch_id,
            r.establishment_id,
            r.payroll_period,
            r.run_status,
            r.row_count,
            r.template_document_id,
            r.generated_document_id,
            r.updated_at
       from %I.wcm_pf_ecr_run r
      order by r.created_at desc, r.ecr_run_id desc',
    v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_pf_ecr_run_status as select * from public.platform_pf_ecr_run_status_rows();

create or replace function public.platform_pf_contribution_ledger_rows()
returns table (
  tenant_id uuid,
  contribution_ledger_id uuid,
  batch_id bigint,
  employee_id uuid,
  employee_code text,
  payroll_period date,
  employee_share numeric,
  employer_share numeric,
  eps_share numeric,
  epf_share numeric,
  sync_status text
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_pf_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid,
            l.contribution_ledger_id,
            l.batch_id,
            l.employee_id,
            w.employee_code,
            l.payroll_period,
            l.employee_share,
            l.employer_share,
            l.eps_share,
            l.epf_share,
            l.sync_status
       from %I.wcm_pf_contribution_ledger l
       join %I.wcm_employee w on w.employee_id = l.employee_id
      order by l.payroll_period desc, w.employee_code',
    v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_pf_contribution_ledger as select * from public.platform_pf_contribution_ledger_rows();

revoke all on function public.platform_pf_module_template_version() from public, anon, authenticated;
revoke all on function public.platform_pf_try_numeric(text) from public, anon, authenticated;
revoke all on function public.platform_pf_try_date(text) from public, anon, authenticated;
revoke all on function public.platform_pf_resolve_context(jsonb) from public, anon, authenticated;
revoke all on function public.platform_pf_append_audit(text,text,text,text,text,jsonb,uuid,uuid,bigint) from public, anon, authenticated;
revoke all on function public.platform_apply_pf_to_tenant(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_pf_establishment(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_pf_employee_enrollment(jsonb) from public, anon, authenticated;
revoke all on function public.platform_record_pf_arrear_case(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_pf_arrear_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_pf_sync_deduction_to_payroll_internal(text,uuid,uuid,date,bigint,text,numeric,numeric,numeric,numeric,numeric) from public, anon, authenticated;
revoke all on function public.platform_request_pf_batch(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_pf_batch_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_review_pf_anomaly(jsonb) from public, anon, authenticated;
revoke all on function public.platform_request_pf_ecr_run(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_pf_ecr_run_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_pf_establishment_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_pf_enrollment_status_rows() from public, anon, authenticated;
revoke all on function public.platform_pf_batch_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_pf_anomaly_queue_rows() from public, anon, authenticated;
revoke all on function public.platform_pf_ecr_run_status_rows() from public, anon, authenticated;
revoke all on function public.platform_pf_contribution_ledger_rows() from public, anon, authenticated;

grant execute on function public.platform_pf_module_template_version() to service_role;
grant execute on function public.platform_pf_resolve_context(jsonb) to service_role;
grant execute on function public.platform_apply_pf_to_tenant(jsonb) to service_role;
grant execute on function public.platform_register_pf_establishment(jsonb) to service_role;
grant execute on function public.platform_register_pf_employee_enrollment(jsonb) to service_role;
grant execute on function public.platform_record_pf_arrear_case(jsonb) to service_role;
grant execute on function public.platform_process_pf_arrear_job(jsonb) to service_role;
grant execute on function public.platform_request_pf_batch(jsonb) to service_role;
grant execute on function public.platform_process_pf_batch_job(jsonb) to service_role;
grant execute on function public.platform_review_pf_anomaly(jsonb) to service_role;
grant execute on function public.platform_request_pf_ecr_run(jsonb) to service_role;
grant execute on function public.platform_process_pf_ecr_run_job(jsonb) to service_role;
grant execute on function public.platform_pf_establishment_catalog_rows() to service_role;
grant execute on function public.platform_pf_enrollment_status_rows() to service_role;
grant execute on function public.platform_pf_batch_catalog_rows() to service_role;
grant execute on function public.platform_pf_anomaly_queue_rows() to service_role;
grant execute on function public.platform_pf_ecr_run_status_rows() to service_role;
grant execute on function public.platform_pf_contribution_ledger_rows() to service_role;

grant select on public.platform_rm_pf_establishment_catalog to service_role;
grant select on public.platform_rm_pf_enrollment_status to service_role;
grant select on public.platform_rm_pf_batch_catalog to service_role;
grant select on public.platform_rm_pf_anomaly_queue to service_role;
grant select on public.platform_rm_pf_ecr_run_status to service_role;
grant select on public.platform_rm_pf_contribution_ledger to service_role;

do $$
declare
  v_template_version text := public.platform_pf_module_template_version();
  v_result jsonb;
begin
  v_result := public.platform_register_template_version(jsonb_build_object(
    'template_version', v_template_version,
    'template_scope', 'module',
    'module_code', 'PF',
    'template_status', 'released',
    'description', 'PF tenant-owned provident-fund statutory engine baseline.',
    'metadata', jsonb_build_object('slice', 'PF', 'module_code', 'PF')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PF template version registration failed: %', v_result::text; end if;

  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PF','source_schema_name', 'public','source_table_name', 'wcm_pf_establishment','target_table_name', 'wcm_pf_establishment','clone_order', 100,'notes', jsonb_build_object('slice', 'PF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PF establishment table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PF','source_schema_name', 'public','source_table_name', 'wcm_pf_employee_enrollment','target_table_name', 'wcm_pf_employee_enrollment','clone_order', 110,'notes', jsonb_build_object('slice', 'PF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PF enrollment table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PF','source_schema_name', 'public','source_table_name', 'wcm_pf_processing_batch','target_table_name', 'wcm_pf_processing_batch','clone_order', 120,'notes', jsonb_build_object('slice', 'PF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PF processing batch table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PF','source_schema_name', 'public','source_table_name', 'wcm_pf_contribution_ledger','target_table_name', 'wcm_pf_contribution_ledger','clone_order', 130,'notes', jsonb_build_object('slice', 'PF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PF contribution ledger table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PF','source_schema_name', 'public','source_table_name', 'wcm_pf_arrear_case','target_table_name', 'wcm_pf_arrear_case','clone_order', 140,'notes', jsonb_build_object('slice', 'PF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PF arrear table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PF','source_schema_name', 'public','source_table_name', 'wcm_pf_anomaly','target_table_name', 'wcm_pf_anomaly','clone_order', 150,'notes', jsonb_build_object('slice', 'PF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PF anomaly table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PF','source_schema_name', 'public','source_table_name', 'wcm_pf_ecr_run','target_table_name', 'wcm_pf_ecr_run','clone_order', 160,'notes', jsonb_build_object('slice', 'PF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PF ecr run table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'PF','source_schema_name', 'public','source_table_name', 'wcm_pf_audit_event','target_table_name', 'wcm_pf_audit_event','clone_order', 170,'notes', jsonb_build_object('slice', 'PF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PF audit table registration failed: %', v_result::text; end if;

  v_result := public.platform_register_async_worker(jsonb_build_object(
    'worker_code', 'pf_monthly_worker',
    'module_code', 'PF',
    'dispatch_mode', 'db_inline_handler',
    'handler_contract', 'platform_process_pf_batch_job',
    'is_active', true,
    'max_batch_size', 4,
    'default_lease_seconds', 600,
    'heartbeat_grace_seconds', 900,
    'retry_backoff_policy', jsonb_build_object('base_seconds', 90, 'multiplier', 2, 'max_seconds', 3600),
    'metadata', jsonb_build_object('slice', 'PF', 'notes', 'First clean PF monthly compute worker on shared F04 spine.')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PF monthly worker registration failed: %', v_result::text; end if;

  v_result := public.platform_register_async_worker(jsonb_build_object(
    'worker_code', 'pf_arrear_worker',
    'module_code', 'PF',
    'dispatch_mode', 'db_inline_handler',
    'handler_contract', 'platform_process_pf_arrear_job',
    'is_active', true,
    'max_batch_size', 5,
    'default_lease_seconds', 300,
    'heartbeat_grace_seconds', 600,
    'retry_backoff_policy', jsonb_build_object('base_seconds', 60, 'multiplier', 2, 'max_seconds', 1800),
    'metadata', jsonb_build_object('slice', 'PF', 'notes', 'First clean PF arrear preparation worker on shared F04 spine.')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PF arrear worker registration failed: %', v_result::text; end if;

  v_result := public.platform_register_async_worker(jsonb_build_object(
    'worker_code', 'pf_ecr_generation_worker',
    'module_code', 'PF',
    'dispatch_mode', 'db_inline_handler',
    'handler_contract', 'platform_process_pf_ecr_run_job',
    'is_active', true,
    'max_batch_size', 3,
    'default_lease_seconds', 600,
    'heartbeat_grace_seconds', 900,
    'retry_backoff_policy', jsonb_build_object('base_seconds', 120, 'multiplier', 2, 'max_seconds', 3600),
    'metadata', jsonb_build_object('slice', 'PF', 'notes', 'First clean PF ECR generation worker on shared F04 spine.')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'PF ECR worker registration failed: %', v_result::text; end if;
end;
$$;;
