set search_path = public, pg_temp;

create or replace function public.platform_esic_module_template_version()
returns text
language sql
immutable
as $$
  select 'esic_v1'::text;
$$;

create or replace function public.platform_esic_try_numeric(p_value text)
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

create or replace function public.platform_esic_try_date(p_value text)
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

create or replace function public.platform_esic_resolve_context(p_params jsonb default '{}'::jsonb)
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
      'source', coalesce(nullif(btrim(v_params->>'source'), ''), 'platform_esic_resolve_context')
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
    return public.platform_json_response(false,'TENANT_SCHEMA_NOT_FOUND','Unable to resolve tenant schema for ESIC context.',jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  return public.platform_json_response(true,'OK','ESIC execution context resolved.',jsonb_build_object(
    'tenant_id', v_tenant_id,
    'tenant_schema', v_schema_name,
    'actor_user_id', public.platform_current_actor_user_id()
  ));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_esic_resolve_context.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create table if not exists public.wcm_esic_configuration (
  configuration_id uuid primary key default gen_random_uuid(),
  state_code text not null,
  effective_from date not null,
  effective_to date null,
  wage_ceiling numeric(14,2) not null default 21000.00,
  employee_contribution_rate numeric(6,2) not null default 0.75,
  employer_contribution_rate numeric(6,2) not null default 3.25,
  configuration_status text not null default 'ACTIVE' check (configuration_status in ('ACTIVE','INACTIVE')),
  statutory_reference text null,
  version_notes text null,
  config_metadata jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  updated_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_esic_configuration_state_check check (btrim(state_code) <> ''),
  constraint wcm_esic_configuration_window_check check (effective_to is null or effective_to >= effective_from),
  constraint wcm_esic_configuration_rate_check check (employee_contribution_rate >= 0 and employer_contribution_rate >= 0 and wage_ceiling >= 0),
  constraint wcm_esic_configuration_metadata_check check (jsonb_typeof(config_metadata) = 'object'),
  constraint wcm_esic_configuration_unique unique (state_code, effective_from)
);
create index if not exists idx_wcm_esic_configuration_state_status on public.wcm_esic_configuration (state_code, configuration_status, effective_from desc);

create table if not exists public.wcm_esic_establishment (
  establishment_id uuid primary key default gen_random_uuid(),
  establishment_code text not null,
  establishment_name text not null,
  registration_code text not null,
  state_code text not null,
  address_payload jsonb not null default '{}'::jsonb,
  contact_person text null,
  contact_email text null,
  contact_phone text null,
  registration_date date null,
  coverage_start_date date null,
  establishment_status text not null default 'ACTIVE' check (establishment_status in ('ACTIVE','INACTIVE')),
  establishment_metadata jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  updated_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_esic_establishment_code_unique unique (establishment_code),
  constraint wcm_esic_establishment_registration_unique unique (registration_code),
  constraint wcm_esic_establishment_code_check check (btrim(establishment_code) <> ''),
  constraint wcm_esic_establishment_name_check check (btrim(establishment_name) <> ''),
  constraint wcm_esic_establishment_registration_check check (btrim(registration_code) <> ''),
  constraint wcm_esic_establishment_state_check check (btrim(state_code) <> ''),
  constraint wcm_esic_establishment_address_check check (jsonb_typeof(address_payload) = 'object'),
  constraint wcm_esic_establishment_metadata_check check (jsonb_typeof(establishment_metadata) = 'object')
);
create index if not exists idx_wcm_esic_establishment_status on public.wcm_esic_establishment (establishment_status, state_code, establishment_code);

create table if not exists public.wcm_esic_employee_registration (
  registration_id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  establishment_id uuid not null,
  ip_number text null,
  registration_date date not null,
  effective_from date not null,
  effective_to date null,
  exit_date date null,
  wage_basis_override numeric(14,2) null,
  registration_status text not null default 'ACTIVE' check (registration_status in ('PENDING','ACTIVE','EXEMPT','SUSPENDED','EXITED')),
  previous_status text null,
  status_changed_at timestamptz null,
  status_changed_by_actor_user_id uuid null,
  exemption_reason text null,
  nominee_details jsonb not null default '[]'::jsonb,
  family_details jsonb not null default '[]'::jsonb,
  registration_metadata jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  updated_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_esic_employee_registration_window_check check (effective_to is null or effective_to >= effective_from),
  constraint wcm_esic_employee_registration_nominee_check check (jsonb_typeof(nominee_details) = 'array'),
  constraint wcm_esic_employee_registration_family_check check (jsonb_typeof(family_details) = 'array'),
  constraint wcm_esic_employee_registration_metadata_check check (jsonb_typeof(registration_metadata) = 'object'),
  constraint wcm_esic_employee_registration_unique unique (employee_id, establishment_id, registration_date)
);
create index if not exists idx_wcm_esic_employee_registration_employee on public.wcm_esic_employee_registration (employee_id, registration_status, effective_from desc);
create index if not exists idx_wcm_esic_employee_registration_establishment on public.wcm_esic_employee_registration (establishment_id, registration_status, effective_from desc);

create table if not exists public.wcm_esic_employee_benefit_period (
  benefit_period_id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  contribution_period_start date not null,
  contribution_period_end date not null,
  benefit_period_start date not null,
  benefit_period_end date not null,
  total_days_worked numeric(10,2) not null default 0,
  total_wages_paid numeric(14,2) not null default 0,
  minimum_days_required integer not null default 78,
  is_eligible boolean not null default false,
  eligibility_details jsonb not null default '{}'::jsonb,
  last_calculated_at timestamptz null,
  calculated_by_actor_user_id uuid null,
  calculation_version text not null default 'esic_v1',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_esic_employee_benefit_period_window_check check (contribution_period_end >= contribution_period_start and benefit_period_end >= benefit_period_start),
  constraint wcm_esic_employee_benefit_period_eligibility_check check (jsonb_typeof(eligibility_details) = 'object'),
  constraint wcm_esic_employee_benefit_period_unique unique (employee_id, contribution_period_start)
);
create index if not exists idx_wcm_esic_benefit_period_employee on public.wcm_esic_employee_benefit_period (employee_id, contribution_period_start desc);

create table if not exists public.wcm_esic_wage_component_mapping (
  wage_component_mapping_id uuid primary key default gen_random_uuid(),
  component_code text not null,
  is_esic_eligible boolean not null default true,
  component_category text null,
  inclusion_reason text null,
  effective_from date not null,
  effective_to date null,
  mapping_metadata jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  updated_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_esic_wage_component_mapping_code_check check (btrim(component_code) <> ''),
  constraint wcm_esic_wage_component_mapping_window_check check (effective_to is null or effective_to >= effective_from),
  constraint wcm_esic_wage_component_mapping_metadata_check check (jsonb_typeof(mapping_metadata) = 'object'),
  constraint wcm_esic_wage_component_mapping_unique unique (component_code, effective_from)
);
create index if not exists idx_wcm_esic_wage_component_mapping_effective on public.wcm_esic_wage_component_mapping (component_code, effective_from desc);

create table if not exists public.wcm_esic_processing_batch (
  batch_id bigint generated always as identity primary key,
  establishment_id uuid not null,
  payroll_period date not null,
  return_period text not null,
  batch_status text not null default 'REQUESTED' check (batch_status in ('REQUESTED','PROCESSING','PROCESSED','SYNCED','RECONCILED','FAILED')),
  worker_job_id uuid null,
  requested_by_actor_user_id uuid null,
  process_started_at timestamptz null,
  process_completed_at timestamptz null,
  summary_payload jsonb not null default '{}'::jsonb,
  error_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_esic_processing_batch_unique unique (establishment_id, payroll_period),
  constraint wcm_esic_processing_batch_summary_check check (jsonb_typeof(summary_payload) = 'object'),
  constraint wcm_esic_processing_batch_error_check check (jsonb_typeof(error_payload) = 'object')
);
create index if not exists idx_wcm_esic_processing_batch_status on public.wcm_esic_processing_batch (batch_status, payroll_period desc);

create table if not exists public.wcm_esic_contribution_ledger (
  contribution_ledger_id uuid primary key default gen_random_uuid(),
  batch_id bigint not null,
  employee_id uuid not null,
  registration_id uuid not null,
  payroll_period date not null,
  ip_number text null,
  gross_wages numeric(14,2) not null default 0,
  eligible_wages numeric(14,2) not null default 0,
  arrear_wages_included numeric(14,2) not null default 0,
  employee_contribution numeric(14,2) not null default 0,
  employer_contribution numeric(14,2) not null default 0,
  total_contribution numeric(14,2) not null default 0,
  calendar_days integer not null default 0,
  worked_days numeric(10,2) not null default 0,
  absent_days numeric(10,2) not null default 0,
  benefit_period_start date null,
  benefit_period_end date null,
  sync_status text not null default 'PENDING' check (sync_status in ('PENDING','SYNCED','ERROR')),
  sync_payload jsonb not null default '{}'::jsonb,
  warning_messages text[] not null default '{}'::text[],
  ledger_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_esic_contribution_ledger_unique unique (employee_id, payroll_period, batch_id),
  constraint wcm_esic_contribution_ledger_sync_check check (jsonb_typeof(sync_payload) = 'object'),
  constraint wcm_esic_contribution_ledger_metadata_check check (jsonb_typeof(ledger_metadata) = 'object')
);
create index if not exists idx_wcm_esic_contribution_ledger_batch on public.wcm_esic_contribution_ledger (batch_id, employee_id);
create index if not exists idx_wcm_esic_contribution_ledger_period on public.wcm_esic_contribution_ledger (payroll_period desc, employee_id);

create index if not exists idx_wcm_esic_contribution_ledger_registration on public.wcm_esic_contribution_ledger (registration_id, payroll_period desc);

create table if not exists public.wcm_esic_challan_run (
  challan_run_id uuid primary key default gen_random_uuid(),
  batch_id bigint not null,
  establishment_id uuid not null,
  payroll_period date not null,
  return_period text not null,
  run_status text not null default 'REQUESTED' check (run_status in ('REQUESTED','GENERATING','GENERATED','SUBMITTED','RECONCILED','FAILED')),
  reconciliation_status text not null default 'OPEN' check (reconciliation_status in ('OPEN','MATCHED','MISMATCH','LATE')),
  worker_job_id uuid null,
  generated_document_id uuid null,
  payment_proof_document_id uuid null,
  submission_reference text null,
  payment_reference text null,
  payment_amount numeric(14,2) null,
  payment_date date null,
  due_date date null,
  late_payment_days integer null,
  discrepancy_amount numeric(14,2) null,
  row_count integer not null default 0,
  total_employees integer not null default 0,
  total_wages numeric(14,2) not null default 0,
  total_employee_contribution numeric(14,2) not null default 0,
  total_employer_contribution numeric(14,2) not null default 0,
  total_contribution numeric(14,2) not null default 0,
  run_payload jsonb not null default '{}'::jsonb,
  error_payload jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_esic_challan_run_unique unique (batch_id, return_period),
  constraint wcm_esic_challan_run_payload_check check (jsonb_typeof(run_payload) = 'object'),
  constraint wcm_esic_challan_run_error_check check (jsonb_typeof(error_payload) = 'object')
);
create index if not exists idx_wcm_esic_challan_run_status on public.wcm_esic_challan_run (run_status, payroll_period desc);
create index if not exists idx_wcm_esic_challan_run_establishment on public.wcm_esic_challan_run (establishment_id, payroll_period desc);

create table if not exists public.wcm_esic_audit_event (
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
  constraint wcm_esic_audit_event_payload_check check (jsonb_typeof(payload) = 'object')
);
create index if not exists idx_wcm_esic_audit_event_entity on public.wcm_esic_audit_event (entity_type, entity_id, created_at desc);

create or replace function public.platform_esic_append_audit(
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
    'insert into %I.wcm_esic_audit_event (event_type, event_status, entity_type, entity_id, actor_user_id, employee_id, batch_id, payload) values ($1,$2,$3,$4,$5,$6,$7,$8)',
    p_schema_name
  ) using p_event_type, p_event_status, p_entity_type, p_entity_id, p_actor_user_id, p_employee_id, p_batch_id, coalesce(p_payload, '{}'::jsonb);
end;
$function$;

create or replace function public.platform_esic_benefit_period_window(p_payroll_period date)
returns jsonb
language plpgsql
immutable
as $function$
declare
  v_period date := date_trunc('month', p_payroll_period::timestamp)::date;
  v_year integer := extract(year from v_period);
  v_month integer := extract(month from v_period);
  v_contribution_start date;
  v_contribution_end date;
  v_benefit_start date;
  v_benefit_end date;
begin
  if v_month between 4 and 9 then
    v_contribution_start := make_date(v_year, 4, 1);
    v_contribution_end := make_date(v_year, 9, 30);
    v_benefit_start := make_date(v_year + 1, 1, 1);
    v_benefit_end := make_date(v_year + 1, 6, 30);
  elsif v_month >= 10 then
    v_contribution_start := make_date(v_year, 10, 1);
    v_contribution_end := make_date(v_year + 1, 3, 31);
    v_benefit_start := make_date(v_year + 1, 7, 1);
    v_benefit_end := make_date(v_year + 1, 12, 31);
  else
    v_contribution_start := make_date(v_year - 1, 10, 1);
    v_contribution_end := make_date(v_year, 3, 31);
    v_benefit_start := make_date(v_year, 7, 1);
    v_benefit_end := make_date(v_year, 12, 31);
  end if;

  return jsonb_build_object(
    'contribution_period_start', v_contribution_start,
    'contribution_period_end', v_contribution_end,
    'benefit_period_start', v_benefit_start,
    'benefit_period_end', v_benefit_end
  );
end;
$function$;

create or replace function public.platform_apply_esic_to_tenant(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_try_uuid(p_params->>'tenant_id');
  v_template_version text := public.platform_esic_module_template_version();
  v_dependency_result jsonb;
  v_apply_result jsonb;
  v_context jsonb;
  v_schema_name text;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false,'TENANT_ID_REQUIRED','tenant_id is required.','{}'::jsonb);
  end if;

  v_dependency_result := public.platform_apply_wcm_core_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_esic_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;

  v_dependency_result := public.platform_apply_payroll_core_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_esic_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;

  v_apply_result := public.platform_apply_template_version_to_tenant(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'template_version', v_template_version,
    'source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_apply_esic_to_tenant')
  ));
  if coalesce((v_apply_result->>'success')::boolean, false) is not true then return v_apply_result; end if;

  v_context := public.platform_esic_resolve_context(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_esic_to_tenant'));
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  if not public.platform_table_exists(v_schema_name, 'wcm_esic_configuration')
    or not public.platform_table_exists(v_schema_name, 'wcm_esic_establishment')
    or not public.platform_table_exists(v_schema_name, 'wcm_esic_employee_registration')
    or not public.platform_table_exists(v_schema_name, 'wcm_esic_processing_batch')
    or not public.platform_table_exists(v_schema_name, 'wcm_esic_contribution_ledger')
    or not public.platform_table_exists(v_schema_name, 'wcm_esic_challan_run')
  then
    return public.platform_json_response(false,'ESIC_TABLES_MISSING','Expected ESIC tenant tables were missing after template apply.',jsonb_build_object('tenant_schema', v_schema_name));
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_esic_employee_registration'
      and c.conname = 'wcm_esic_employee_registration_employee_fk'
  ) then
    execute format('alter table %I.wcm_esic_employee_registration add constraint wcm_esic_employee_registration_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_esic_employee_benefit_period'
      and c.conname = 'wcm_esic_benefit_period_employee_fk'
  ) then
    execute format('alter table %I.wcm_esic_employee_benefit_period add constraint wcm_esic_benefit_period_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_esic_contribution_ledger'
      and c.conname = 'wcm_esic_contribution_ledger_employee_fk'
  ) then
    execute format('alter table %I.wcm_esic_contribution_ledger add constraint wcm_esic_contribution_ledger_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_esic_employee_registration'
      and c.conname = 'wcm_esic_employee_registration_establishment_fk'
  ) then
    execute format('alter table %I.wcm_esic_employee_registration add constraint wcm_esic_employee_registration_establishment_fk foreign key (establishment_id) references %I.wcm_esic_establishment(establishment_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_esic_processing_batch'
      and c.conname = 'wcm_esic_processing_batch_establishment_fk'
  ) then
    execute format('alter table %I.wcm_esic_processing_batch add constraint wcm_esic_processing_batch_establishment_fk foreign key (establishment_id) references %I.wcm_esic_establishment(establishment_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_esic_contribution_ledger'
      and c.conname = 'wcm_esic_contribution_ledger_registration_fk'
  ) then
    execute format('alter table %I.wcm_esic_contribution_ledger add constraint wcm_esic_contribution_ledger_registration_fk foreign key (registration_id) references %I.wcm_esic_employee_registration(registration_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_esic_contribution_ledger'
      and c.conname = 'wcm_esic_contribution_ledger_batch_fk'
  ) then
    execute format('alter table %I.wcm_esic_contribution_ledger add constraint wcm_esic_contribution_ledger_batch_fk foreign key (batch_id) references %I.wcm_esic_processing_batch(batch_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_esic_challan_run'
      and c.conname = 'wcm_esic_challan_run_batch_fk'
  ) then
    execute format('alter table %I.wcm_esic_challan_run add constraint wcm_esic_challan_run_batch_fk foreign key (batch_id) references %I.wcm_esic_processing_batch(batch_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_esic_challan_run'
      and c.conname = 'wcm_esic_challan_run_establishment_fk'
  ) then
    execute format('alter table %I.wcm_esic_challan_run add constraint wcm_esic_challan_run_establishment_fk foreign key (establishment_id) references %I.wcm_esic_establishment(establishment_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  return public.platform_json_response(true,'OK','ESIC applied to tenant schema.',jsonb_build_object('tenant_id', v_tenant_id,'tenant_schema', v_schema_name,'template_version', v_template_version));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_apply_esic_to_tenant.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
