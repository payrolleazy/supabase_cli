set search_path = public, pg_temp;

create or replace function public.platform_ptax_module_template_version()
returns text
language sql
immutable
as $$
  select 'ptax_v1'::text;
$$;

create or replace function public.platform_ptax_try_numeric(p_value text)
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

create or replace function public.platform_ptax_try_date(p_value text)
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

create or replace function public.platform_ptax_resolve_context(p_params jsonb default '{}'::jsonb)
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
      'source', coalesce(nullif(btrim(v_params->>'source'), ''), 'platform_ptax_resolve_context')
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
    return public.platform_json_response(false,'TENANT_SCHEMA_NOT_FOUND','Unable to resolve tenant schema for PTAX context.',jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  return public.platform_json_response(true,'OK','PTAX execution context resolved.',jsonb_build_object(
    'tenant_id', v_tenant_id,
    'tenant_schema', v_schema_name,
    'actor_user_id', public.platform_current_actor_user_id()
  ));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_ptax_resolve_context.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create table if not exists public.wcm_ptax_configuration (
  configuration_id uuid primary key default gen_random_uuid(),
  state_code text not null,
  effective_from date not null,
  effective_to date null,
  slabs jsonb not null default '[]'::jsonb,
  deduction_frequency text not null default 'MONTHLY' check (deduction_frequency in ('MONTHLY','HALF_YEARLY','ANNUAL')),
  frequency_months integer[] not null default '{}'::integer[],
  configuration_status text not null default 'ACTIVE' check (configuration_status in ('ACTIVE','INACTIVE')),
  configuration_version integer not null default 1,
  statutory_reference text null,
  version_notes text null,
  config_metadata jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  updated_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_ptax_configuration_state_check check (btrim(state_code) <> ''),
  constraint wcm_ptax_configuration_window_check check (effective_to is null or effective_to >= effective_from),
  constraint wcm_ptax_configuration_slabs_check check (jsonb_typeof(slabs) = 'array'),
  constraint wcm_ptax_configuration_metadata_check check (jsonb_typeof(config_metadata) = 'object'),
  constraint wcm_ptax_configuration_version_check check (configuration_version > 0),
  constraint wcm_ptax_configuration_unique unique (state_code, effective_from)
);
create index if not exists idx_wcm_ptax_configuration_state_status on public.wcm_ptax_configuration (state_code, configuration_status, effective_from desc);
create index if not exists idx_wcm_ptax_configuration_frequency on public.wcm_ptax_configuration (deduction_frequency, effective_from desc);

create table if not exists public.wcm_ptax_employee_state_profile (
  state_profile_id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  state_code text not null,
  resident_state_code text null,
  work_state_code text null,
  source_kind text not null default 'MANUAL' check (source_kind in ('MANUAL','HR_ADMIN','MIGRATED','SYSTEM')),
  effective_from date not null,
  effective_to date null,
  profile_status text not null default 'ACTIVE' check (profile_status in ('ACTIVE','INACTIVE')),
  notes text null,
  profile_metadata jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  updated_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_ptax_employee_state_profile_state_check check (btrim(state_code) <> ''),
  constraint wcm_ptax_employee_state_profile_window_check check (effective_to is null or effective_to >= effective_from),
  constraint wcm_ptax_employee_state_profile_metadata_check check (jsonb_typeof(profile_metadata) = 'object'),
  constraint wcm_ptax_employee_state_profile_unique unique (employee_id, effective_from)
);
create index if not exists idx_wcm_ptax_state_profile_employee on public.wcm_ptax_employee_state_profile (employee_id, effective_from desc);
create index if not exists idx_wcm_ptax_state_profile_state on public.wcm_ptax_employee_state_profile (state_code, profile_status, effective_from desc);

create table if not exists public.wcm_ptax_wage_component_mapping (
  wage_component_mapping_id uuid primary key default gen_random_uuid(),
  state_code text not null,
  component_code text not null,
  is_ptax_eligible boolean not null default true,
  effective_from date not null,
  effective_to date null,
  mapping_metadata jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  updated_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_ptax_wage_component_mapping_state_check check (btrim(state_code) <> ''),
  constraint wcm_ptax_wage_component_mapping_component_check check (btrim(component_code) <> ''),
  constraint wcm_ptax_wage_component_mapping_window_check check (effective_to is null or effective_to >= effective_from),
  constraint wcm_ptax_wage_component_mapping_metadata_check check (jsonb_typeof(mapping_metadata) = 'object'),
  constraint wcm_ptax_wage_component_mapping_unique unique (state_code, component_code, effective_from)
);
create index if not exists idx_wcm_ptax_wage_component_mapping_state on public.wcm_ptax_wage_component_mapping (state_code, effective_from desc);
create index if not exists idx_wcm_ptax_wage_component_mapping_component on public.wcm_ptax_wage_component_mapping (component_code, effective_from desc);

create table if not exists public.wcm_ptax_processing_batch (
  batch_id bigint generated always as identity primary key,
  state_code text not null,
  payroll_period date not null,
  batch_status text not null default 'REQUESTED' check (batch_status in ('REQUESTED','PROCESSING','PROCESSED','SYNCED','FAILED','CANCELLED')),
  worker_job_id uuid null,
  requested_employee_ids jsonb not null default '[]'::jsonb,
  requested_by_actor_user_id uuid null,
  process_started_at timestamptz null,
  process_completed_at timestamptz null,
  summary_payload jsonb not null default '{}'::jsonb,
  error_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_ptax_processing_batch_state_check check (btrim(state_code) <> ''),
  constraint wcm_ptax_processing_batch_requested_check check (jsonb_typeof(requested_employee_ids) = 'array'),
  constraint wcm_ptax_processing_batch_summary_check check (jsonb_typeof(summary_payload) = 'object'),
  constraint wcm_ptax_processing_batch_error_check check (jsonb_typeof(error_payload) = 'object'),
  constraint wcm_ptax_processing_batch_unique unique (state_code, payroll_period)
);
create index if not exists idx_wcm_ptax_processing_batch_status on public.wcm_ptax_processing_batch (batch_status, payroll_period desc);
create index if not exists idx_wcm_ptax_processing_batch_state_period on public.wcm_ptax_processing_batch (state_code, payroll_period desc);

create table if not exists public.wcm_ptax_monthly_ledger (
  contribution_ledger_id uuid primary key default gen_random_uuid(),
  batch_id bigint not null,
  employee_id uuid not null,
  payroll_period date not null,
  state_code text not null,
  deduction_frequency text not null,
  taxable_wages numeric(14,2) not null default 0,
  deduction_amount numeric(14,2) not null default 0,
  sync_status text not null default 'PENDING' check (sync_status in ('PENDING','SYNCED','ERROR','SKIPPED')),
  slab_details jsonb not null default '{}'::jsonb,
  sync_payload jsonb not null default '{}'::jsonb,
  ledger_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_ptax_monthly_ledger_state_check check (btrim(state_code) <> ''),
  constraint wcm_ptax_monthly_ledger_slab_check check (jsonb_typeof(slab_details) = 'object'),
  constraint wcm_ptax_monthly_ledger_sync_check check (jsonb_typeof(sync_payload) = 'object'),
  constraint wcm_ptax_monthly_ledger_metadata_check check (jsonb_typeof(ledger_metadata) = 'object'),
  constraint wcm_ptax_monthly_ledger_unique unique (employee_id, payroll_period, batch_id)
);
create index if not exists idx_wcm_ptax_monthly_ledger_batch on public.wcm_ptax_monthly_ledger (batch_id, employee_id);
create index if not exists idx_wcm_ptax_monthly_ledger_period on public.wcm_ptax_monthly_ledger (payroll_period desc, employee_id);
create index if not exists idx_wcm_ptax_monthly_ledger_sync on public.wcm_ptax_monthly_ledger (sync_status, payroll_period desc);
create index if not exists idx_wcm_ptax_monthly_ledger_state on public.wcm_ptax_monthly_ledger (state_code, payroll_period desc);

create table if not exists public.wcm_ptax_arrear_case (
  arrear_case_id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  state_code text not null,
  from_period date not null,
  to_period date not null,
  revised_state_code text null,
  override_amount numeric(14,2) null,
  arrear_status text not null default 'PENDING_REVIEW' check (arrear_status in ('PENDING_REVIEW','PENDING_APPROVAL','APPROVED','REJECTED','FAILED','CANCELLED','PROCESSED')),
  review_notes text null,
  reviewed_by_actor_user_id uuid null,
  target_payroll_period date null,
  case_metadata jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  updated_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_ptax_arrear_case_state_check check (btrim(state_code) <> ''),
  constraint wcm_ptax_arrear_case_period_check check (to_period >= from_period),
  constraint wcm_ptax_arrear_case_metadata_check check (jsonb_typeof(case_metadata) = 'object')
);
create index if not exists idx_wcm_ptax_arrear_case_employee on public.wcm_ptax_arrear_case (employee_id, from_period desc, arrear_status);
create index if not exists idx_wcm_ptax_arrear_case_status on public.wcm_ptax_arrear_case (arrear_status, target_payroll_period desc nulls last, updated_at desc);

create table if not exists public.wcm_ptax_arrear_computation (
  arrear_computation_id uuid primary key default gen_random_uuid(),
  arrear_case_id uuid not null,
  payroll_period date not null,
  state_code text not null,
  original_taxable_wages numeric(14,2) not null default 0,
  revised_taxable_wages numeric(14,2) not null default 0,
  original_deduction numeric(14,2) not null default 0,
  revised_deduction numeric(14,2) not null default 0,
  delta_deduction numeric(14,2) not null default 0,
  computation_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_ptax_arrear_computation_state_check check (btrim(state_code) <> ''),
  constraint wcm_ptax_arrear_computation_payload_check check (jsonb_typeof(computation_payload) = 'object'),
  constraint wcm_ptax_arrear_computation_unique unique (arrear_case_id, payroll_period)
);
create index if not exists idx_wcm_ptax_arrear_computation_case on public.wcm_ptax_arrear_computation (arrear_case_id, payroll_period);
create index if not exists idx_wcm_ptax_arrear_computation_delta on public.wcm_ptax_arrear_computation (delta_deduction, payroll_period desc);

create table if not exists public.wcm_ptax_audit_event (
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
  constraint wcm_ptax_audit_event_payload_check check (jsonb_typeof(payload) = 'object')
);
create index if not exists idx_wcm_ptax_audit_event_entity on public.wcm_ptax_audit_event (entity_type, entity_id, created_at desc);

create or replace function public.platform_ptax_append_audit(
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
    'insert into %I.wcm_ptax_audit_event (event_type, event_status, entity_type, entity_id, actor_user_id, employee_id, batch_id, payload) values ($1,$2,$3,$4,$5,$6,$7,$8)',
    p_schema_name
  ) using p_event_type, p_event_status, p_entity_type, p_entity_id, p_actor_user_id, p_employee_id, p_batch_id, coalesce(p_payload, '{}'::jsonb);
end;
$function$;

create or replace function public.platform_ptax_calculate_from_slabs(
  p_eligible_wages numeric,
  p_slabs jsonb,
  p_payroll_period date
)
returns jsonb
language plpgsql
immutable
as $function$
declare
  v_period date := date_trunc('month', coalesce(p_payroll_period, current_date)::timestamp)::date;
  v_month integer := extract(month from v_period);
  v_item jsonb;
  v_min numeric;
  v_max numeric;
  v_deduction numeric;
begin
  if p_slabs is null or jsonb_typeof(p_slabs) <> 'array' then
    return jsonb_build_object('matched', false, 'deduction_amount', 0, 'slab', null, 'reason', 'INVALID_SLABS');
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_slabs)
    order by coalesce(public.platform_ptax_try_numeric(coalesce(value->>'from', value->>'min_amount')), 0), coalesce(public.platform_ptax_try_numeric(coalesce(value->>'to', value->>'max_amount')), 999999999)
  loop
    v_min := coalesce(public.platform_ptax_try_numeric(coalesce(v_item->>'from', v_item->>'min_amount')), 0);
    v_max := public.platform_ptax_try_numeric(coalesce(v_item->>'to', v_item->>'max_amount'));
    if coalesce(p_eligible_wages, 0) >= v_min and (v_max is null or coalesce(p_eligible_wages, 0) <= v_max) then
      v_deduction := coalesce(
        case when v_month = 2 then public.platform_ptax_try_numeric(v_item->>'feb_deduction') else null end,
        public.platform_ptax_try_numeric(v_item->>'deduction'),
        public.platform_ptax_try_numeric(v_item->>'deduction_amount'),
        0
      );
      return jsonb_build_object('matched', true, 'deduction_amount', v_deduction, 'slab', v_item, 'matched_min_amount', v_min, 'matched_max_amount', v_max);
    end if;
  end loop;

  return jsonb_build_object('matched', false, 'deduction_amount', 0, 'slab', null, 'reason', 'NO_MATCHING_SLAB');
end;
$function$;

create or replace function public.platform_ptax_frequency_applies(
  p_deduction_frequency text,
  p_frequency_months integer[],
  p_payroll_period date
)
returns boolean
language plpgsql
immutable
as $function$
declare
  v_frequency text := upper(coalesce(nullif(btrim(p_deduction_frequency), ''), 'MONTHLY'));
  v_month integer := extract(month from date_trunc('month', coalesce(p_payroll_period, current_date)::timestamp)::date);
begin
  if v_frequency = 'MONTHLY' then
    return true;
  end if;

  if array_length(coalesce(p_frequency_months, '{}'::integer[]), 1) is not null then
    return v_month = any(p_frequency_months);
  end if;

  if v_frequency = 'HALF_YEARLY' then
    return v_month in (4, 10);
  end if;

  return false;
end;
$function$;

create or replace function public.platform_ptax_resolve_employee_state_internal(
  p_schema_name text,
  p_employee_id uuid,
  p_payroll_period date
)
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_state_code text;
begin
  execute format(
    'select state_code
       from %I.wcm_ptax_employee_state_profile
      where employee_id = $1
        and profile_status = ''ACTIVE''
        and effective_from <= $2
        and (effective_to is null or effective_to >= $2)
      order by effective_from desc, created_at desc
      limit 1',
    p_schema_name
  ) into v_state_code using p_employee_id, p_payroll_period;

  return v_state_code;
end;
$function$;;
