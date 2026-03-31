set search_path = public, pg_temp;

create or replace function public.platform_pf_module_template_version()
returns text
language sql
immutable
as $$
  select 'pf_v1'::text;
$$;

create or replace function public.platform_pf_try_numeric(p_value text)
returns numeric
language plpgsql
immutable
as $function$
begin
  if p_value is null or btrim(p_value) = '' then
    return null;
  end if;
  return p_value::numeric;
exception when others then
  return null;
end;
$function$;

create or replace function public.platform_pf_try_date(p_value text)
returns date
language plpgsql
immutable
as $function$
begin
  if p_value is null or btrim(p_value) = '' then
    return null;
  end if;
  return p_value::date;
exception when others then
  return null;
end;
$function$;

create or replace function public.platform_pf_resolve_context(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_params jsonb := coalesce(p_params, '{}'::jsonb);
  v_requested_tenant_id uuid := public.platform_try_uuid(v_params->>'tenant_id');
  v_context_result jsonb;
  v_tenant_id uuid;
  v_schema_name text;
begin
  if v_requested_tenant_id is not null and public.platform_is_internal_caller() then
    v_context_result := public.platform_apply_execution_context(jsonb_build_object(
      'execution_mode', 'internal_platform',
      'tenant_id', v_requested_tenant_id,
      'source', coalesce(nullif(btrim(v_params->>'source'), ''), 'platform_pf_resolve_context')
    ));
    if coalesce((v_context_result->>'success')::boolean, false) is not true then
      return v_context_result;
    end if;
  end if;

  v_tenant_id := coalesce(public.platform_current_tenant_id(), v_requested_tenant_id);
  if v_tenant_id is null then
    return public.platform_json_response(false,'TENANT_CONTEXT_REQUIRED','tenant_id or active tenant context is required.','{}'::jsonb);
  end if;

  v_schema_name := public.platform_current_tenant_schema();
  if v_schema_name is null or btrim(v_schema_name) = '' then
    select schema_name into v_schema_name from public.platform_tenant where tenant_id = v_tenant_id;
  end if;

  if v_schema_name is null or btrim(v_schema_name) = '' then
    return public.platform_json_response(false,'TENANT_SCHEMA_NOT_FOUND','Unable to resolve tenant schema for PF context.',jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  return public.platform_json_response(true,'OK','PF execution context resolved.',jsonb_build_object(
    'tenant_id', v_tenant_id,
    'tenant_schema', v_schema_name,
    'actor_user_id', public.platform_current_actor_user_id()
  ));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_pf_resolve_context.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create table if not exists public.wcm_pf_establishment (
  establishment_id uuid primary key default gen_random_uuid(),
  establishment_code text not null,
  establishment_name text not null,
  legal_entity_name text null,
  pf_office_code text not null,
  employer_pf_rate numeric(6,2) not null default 12.00,
  employee_pf_rate numeric(6,2) not null default 12.00,
  eps_rate numeric(6,2) not null default 8.33,
  epf_rate numeric(6,2) not null default 3.67,
  admin_charge_rate numeric(6,2) not null default 0.50,
  edli_rate numeric(6,2) not null default 0.50,
  wage_ceiling numeric(14,2) not null default 15000.00,
  calc_policy jsonb not null default '{}'::jsonb,
  establishment_status text not null default 'ACTIVE' check (establishment_status in ('ACTIVE','INACTIVE')),
  created_by_actor_user_id uuid null,
  updated_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_pf_establishment_code_unique unique (establishment_code),
  constraint wcm_pf_establishment_code_check check (btrim(establishment_code) <> ''),
  constraint wcm_pf_establishment_name_check check (btrim(establishment_name) <> ''),
  constraint wcm_pf_establishment_office_check check (btrim(pf_office_code) <> ''),
  constraint wcm_pf_establishment_rates_nonnegative check (employer_pf_rate >= 0 and employee_pf_rate >= 0 and eps_rate >= 0 and epf_rate >= 0 and admin_charge_rate >= 0 and edli_rate >= 0),
  constraint wcm_pf_establishment_calc_policy_check check (jsonb_typeof(calc_policy) = 'object')
);
create index if not exists idx_wcm_pf_establishment_status on public.wcm_pf_establishment (establishment_status, establishment_code);

create table if not exists public.wcm_pf_employee_enrollment (
  enrollment_id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  establishment_id uuid not null,
  uan text null,
  pf_member_id text null,
  payroll_area_id uuid null,
  wage_basis_override numeric(14,2) null,
  voluntary_pf_rate numeric(6,2) null,
  eps_eligible boolean not null default true,
  enrollment_status text not null default 'ACTIVE' check (enrollment_status in ('PENDING','ACTIVE','EXCLUDED','TRANSFER_PENDING','EXITED')),
  effective_from date not null,
  effective_to date null,
  exit_reason text null,
  enrollment_metadata jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  updated_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_pf_employee_enrollment_window_check check (effective_to is null or effective_to >= effective_from),
  constraint wcm_pf_employee_enrollment_metadata_check check (jsonb_typeof(enrollment_metadata) = 'object'),
  constraint wcm_pf_employee_enrollment_unique unique (employee_id, establishment_id, effective_from)
);
create index if not exists idx_wcm_pf_employee_enrollment_employee on public.wcm_pf_employee_enrollment (employee_id, effective_from desc);
create index if not exists idx_wcm_pf_employee_enrollment_establishment on public.wcm_pf_employee_enrollment (establishment_id, enrollment_status, effective_from desc);

create table if not exists public.wcm_pf_processing_batch (
  batch_id bigint generated always as identity primary key,
  establishment_id uuid not null,
  payroll_period date not null,
  batch_status text not null default 'REQUESTED' check (batch_status in ('REQUESTED','PROCESSING_ARREARS','PROCESSING','PROCESSED','SYNCED','FINALIZED','FAILED')),
  worker_job_id uuid null,
  requested_by_actor_user_id uuid null,
  process_started_at timestamptz null,
  process_completed_at timestamptz null,
  summary_payload jsonb not null default '{}'::jsonb,
  error_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_pf_processing_batch_period_unique unique (establishment_id, payroll_period),
  constraint wcm_pf_processing_batch_summary_check check (jsonb_typeof(summary_payload) = 'object'),
  constraint wcm_pf_processing_batch_error_check check (jsonb_typeof(error_payload) = 'object')
);
create index if not exists idx_wcm_pf_processing_batch_status on public.wcm_pf_processing_batch (batch_status, payroll_period desc);

create table if not exists public.wcm_pf_contribution_ledger (
  contribution_ledger_id uuid primary key default gen_random_uuid(),
  batch_id bigint not null,
  employee_id uuid not null,
  enrollment_id uuid not null,
  payroll_period date not null,
  wage_basis numeric(14,2) not null default 0,
  arrear_wage_basis numeric(14,2) not null default 0,
  employee_share numeric(14,2) not null default 0,
  employer_share numeric(14,2) not null default 0,
  eps_share numeric(14,2) not null default 0,
  epf_share numeric(14,2) not null default 0,
  admin_charge numeric(14,2) not null default 0,
  edli_charge numeric(14,2) not null default 0,
  sync_status text not null default 'PENDING' check (sync_status in ('PENDING','SYNCED','ERROR')),
  sync_payload jsonb not null default '{}'::jsonb,
  ledger_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_pf_contribution_ledger_unique unique (employee_id, payroll_period, batch_id),
  constraint wcm_pf_contribution_ledger_sync_check check (jsonb_typeof(sync_payload) = 'object'),
  constraint wcm_pf_contribution_ledger_metadata_check check (jsonb_typeof(ledger_metadata) = 'object')
);
create index if not exists idx_wcm_pf_contribution_ledger_batch on public.wcm_pf_contribution_ledger (batch_id, employee_id);
create index if not exists idx_wcm_pf_contribution_ledger_period on public.wcm_pf_contribution_ledger (payroll_period desc, employee_id);

create table if not exists public.wcm_pf_arrear_case (
  arrear_case_id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  establishment_id uuid not null,
  effective_period date not null,
  wage_delta numeric(14,2) not null default 0,
  employee_share_delta numeric(14,2) null,
  employer_share_delta numeric(14,2) null,
  arrear_status text not null default 'PENDING_REVIEW' check (arrear_status in ('PENDING_REVIEW','APPROVED','READY_FOR_BATCH','SETTLED','REJECTED')),
  review_notes text null,
  reviewed_by_actor_user_id uuid null,
  settled_batch_id bigint null,
  arrear_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_pf_arrear_case_metadata_check check (jsonb_typeof(arrear_metadata) = 'object')
);
create index if not exists idx_wcm_pf_arrear_case_employee_period on public.wcm_pf_arrear_case (employee_id, effective_period desc, arrear_status);
create index if not exists idx_wcm_pf_arrear_case_establishment on public.wcm_pf_arrear_case (establishment_id, effective_period desc, arrear_status);

create table if not exists public.wcm_pf_anomaly (
  anomaly_id uuid primary key default gen_random_uuid(),
  batch_id bigint not null,
  employee_id uuid not null,
  anomaly_code text not null,
  severity text not null default 'ERROR' check (severity in ('INFO','WARNING','ERROR')),
  anomaly_message text not null,
  anomaly_status text not null default 'OPEN' check (anomaly_status in ('OPEN','RESOLVED','IGNORED')),
  resolution_notes text null,
  reviewed_by_actor_user_id uuid null,
  anomaly_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_pf_anomaly_code_check check (btrim(anomaly_code) <> ''),
  constraint wcm_pf_anomaly_payload_check check (jsonb_typeof(anomaly_payload) = 'object'),
  constraint wcm_pf_anomaly_unique unique (batch_id, employee_id, anomaly_code)
);
create index if not exists idx_wcm_pf_anomaly_status on public.wcm_pf_anomaly (anomaly_status, severity, created_at desc);

create table if not exists public.wcm_pf_ecr_run (
  ecr_run_id uuid primary key default gen_random_uuid(),
  batch_id bigint not null,
  establishment_id uuid not null,
  payroll_period date not null,
  template_document_id uuid null,
  generated_document_id uuid null,
  run_status text not null default 'REQUESTED' check (run_status in ('REQUESTED','GENERATING','GENERATED','PUBLISHED','FAILED')),
  worker_job_id uuid null,
  row_count integer not null default 0,
  artifact_payload jsonb not null default '{}'::jsonb,
  error_payload jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_pf_ecr_run_artifact_check check (jsonb_typeof(artifact_payload) = 'object'),
  constraint wcm_pf_ecr_run_error_check check (jsonb_typeof(error_payload) = 'object')
);
create index if not exists idx_wcm_pf_ecr_run_status on public.wcm_pf_ecr_run (run_status, payroll_period desc);

create table if not exists public.wcm_pf_audit_event (
  audit_event_id uuid primary key default gen_random_uuid(),
  event_type text not null,
  event_status text not null,
  entity_type text not null,
  entity_id text not null,
  actor_user_id uuid null,
  employee_id uuid null,
  batch_id bigint null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  constraint wcm_pf_audit_event_payload_check check (jsonb_typeof(payload) = 'object')
);
create index if not exists idx_wcm_pf_audit_event_entity on public.wcm_pf_audit_event (entity_type, entity_id, created_at desc);

create or replace function public.platform_pf_append_audit(
  p_schema_name text,
  p_event_type text,
  p_event_status text,
  p_entity_type text,
  p_entity_id text,
  p_payload jsonb default '{}'::jsonb,
  p_actor_user_id uuid default null,
  p_employee_id uuid default null,
  p_batch_id bigint default null
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  execute format(
    'insert into %I.wcm_pf_audit_event (event_type, event_status, entity_type, entity_id, actor_user_id, employee_id, batch_id, payload) values ($1,$2,$3,$4,$5,$6,$7,$8)',
    p_schema_name
  ) using p_event_type, p_event_status, p_entity_type, p_entity_id, p_actor_user_id, p_employee_id, p_batch_id, coalesce(p_payload, '{}'::jsonb);
end;
$function$;
create or replace function public.platform_apply_pf_to_tenant(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_try_uuid(p_params->>'tenant_id');
  v_template_version text := public.platform_pf_module_template_version();
  v_dependency_result jsonb;
  v_apply_result jsonb;
  v_context jsonb;
  v_schema_name text;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false,'TENANT_ID_REQUIRED','tenant_id is required.','{}'::jsonb);
  end if;

  v_dependency_result := public.platform_apply_wcm_core_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_pf_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;

  v_dependency_result := public.platform_apply_payroll_core_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_pf_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;

  v_apply_result := public.platform_apply_template_version_to_tenant(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'template_version', v_template_version,
    'source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_apply_pf_to_tenant')
  ));
  if coalesce((v_apply_result->>'success')::boolean, false) is not true then return v_apply_result; end if;

  v_context := public.platform_pf_resolve_context(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_pf_to_tenant'));
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  if not public.platform_table_exists(v_schema_name, 'wcm_pf_establishment')
    or not public.platform_table_exists(v_schema_name, 'wcm_pf_employee_enrollment')
    or not public.platform_table_exists(v_schema_name, 'wcm_pf_processing_batch')
    or not public.platform_table_exists(v_schema_name, 'wcm_pf_contribution_ledger')
  then
    return public.platform_json_response(false,'PF_TABLES_MISSING','Expected PF tenant tables were missing after template apply.',jsonb_build_object('tenant_schema', v_schema_name));
  end if;

  return public.platform_json_response(true,'OK','PF applied to tenant schema.',jsonb_build_object('tenant_id', v_tenant_id,'tenant_schema', v_schema_name,'template_version', v_template_version));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_apply_pf_to_tenant.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
