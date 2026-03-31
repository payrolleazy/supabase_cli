
set search_path = public, pg_temp;

create or replace function public.platform_lwf_module_template_version()
returns text
language sql
immutable
as $$
  select 'lwf_v1'::text;
$$;

create or replace function public.platform_lwf_try_numeric(p_value text)
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

create or replace function public.platform_lwf_try_date(p_value text)
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

create or replace function public.platform_lwf_resolve_context(p_params jsonb default '{}'::jsonb)
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
      'source', coalesce(nullif(btrim(v_params->>'source'), ''), 'platform_lwf_resolve_context')
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
    return public.platform_json_response(false,'TENANT_SCHEMA_NOT_FOUND','Unable to resolve tenant schema for LWF context.',jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  return public.platform_json_response(true,'OK','LWF execution context resolved.',jsonb_build_object(
    'tenant_id', v_tenant_id,
    'tenant_schema', v_schema_name,
    'actor_user_id', public.platform_current_actor_user_id()
  ));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_lwf_resolve_context.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create table if not exists public.wcm_lwf_configuration (
  configuration_id uuid primary key default gen_random_uuid(),
  state_code text not null,
  effective_from date not null,
  effective_to date null,
  deduction_frequency text not null default 'MONTHLY' check (deduction_frequency in ('MONTHLY','QUARTERLY','HALF_YEARLY','ANNUAL','CUSTOM')),
  deduction_months integer[] not null default '{}'::integer[],
  contribution_rules jsonb not null default '{}'::jsonb,
  configuration_status text not null default 'ACTIVE' check (configuration_status in ('ACTIVE','INACTIVE')),
  configuration_version integer not null default 1,
  statutory_reference text null,
  configuration_metadata jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  updated_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_lwf_configuration_state_check check (btrim(state_code) <> ''),
  constraint wcm_lwf_configuration_window_check check (effective_to is null or effective_to >= effective_from),
  constraint wcm_lwf_configuration_rules_check check (jsonb_typeof(contribution_rules) = 'object'),
  constraint wcm_lwf_configuration_metadata_check check (jsonb_typeof(configuration_metadata) = 'object'),
  constraint wcm_lwf_configuration_version_check check (configuration_version > 0),
  constraint wcm_lwf_configuration_unique unique (state_code, effective_from)
);
create index if not exists idx_wcm_lwf_configuration_state_status on public.wcm_lwf_configuration (state_code, configuration_status, effective_from desc);
create index if not exists idx_wcm_lwf_configuration_frequency on public.wcm_lwf_configuration (deduction_frequency, effective_from desc);

create table if not exists public.wcm_lwf_wage_component_mapping (
  wage_component_mapping_id uuid primary key default gen_random_uuid(),
  state_code text not null,
  component_code text not null,
  is_lwf_eligible boolean not null default true,
  effective_from date not null,
  effective_to date null,
  mapping_metadata jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  updated_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_lwf_wage_component_mapping_state_check check (btrim(state_code) <> ''),
  constraint wcm_lwf_wage_component_mapping_component_check check (btrim(component_code) <> ''),
  constraint wcm_lwf_wage_component_mapping_window_check check (effective_to is null or effective_to >= effective_from),
  constraint wcm_lwf_wage_component_mapping_metadata_check check (jsonb_typeof(mapping_metadata) = 'object'),
  constraint wcm_lwf_wage_component_mapping_unique unique (state_code, component_code, effective_from)
);
create index if not exists idx_wcm_lwf_mapping_state on public.wcm_lwf_wage_component_mapping (state_code, effective_from desc);
create index if not exists idx_wcm_lwf_mapping_component on public.wcm_lwf_wage_component_mapping (component_code, effective_from desc);

create table if not exists public.wcm_lwf_processing_batch (
  batch_id bigint generated always as identity primary key,
  state_code text not null,
  payroll_period date not null,
  batch_source text not null default 'MANUAL' check (batch_source in ('MANUAL','PAYROLL_COMPLETION','FNF')),
  source_batch_id uuid null,
  source_batch_ref text null,
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
  constraint wcm_lwf_processing_batch_state_check check (btrim(state_code) <> ''),
  constraint wcm_lwf_processing_batch_requested_check check (jsonb_typeof(requested_employee_ids) = 'array'),
  constraint wcm_lwf_processing_batch_summary_check check (jsonb_typeof(summary_payload) = 'object'),
  constraint wcm_lwf_processing_batch_error_check check (jsonb_typeof(error_payload) = 'object')
);
create index if not exists idx_wcm_lwf_processing_batch_state_period on public.wcm_lwf_processing_batch (state_code, payroll_period desc);
create index if not exists idx_wcm_lwf_processing_batch_status on public.wcm_lwf_processing_batch (batch_status, payroll_period desc);
create index if not exists idx_wcm_lwf_processing_batch_source on public.wcm_lwf_processing_batch (source_batch_id);

create table if not exists public.wcm_lwf_period_ledger (
  contribution_ledger_id uuid primary key default gen_random_uuid(),
  batch_id bigint not null,
  employee_id uuid not null,
  payroll_period date not null,
  state_code text not null,
  eligible_wages numeric(14,2) not null default 0,
  system_employee_contribution numeric(14,2) not null default 0,
  system_employer_contribution numeric(14,2) not null default 0,
  final_employee_contribution numeric(14,2) not null default 0,
  final_employer_contribution numeric(14,2) not null default 0,
  override_status text not null default 'NONE' check (override_status in ('NONE','MANUAL')),
  override_reason text null,
  overridden_by_actor_user_id uuid null,
  overridden_at timestamptz null,
  sync_status text not null default 'PENDING' check (sync_status in ('PENDING','SYNCED','ERROR','SKIPPED')),
  calculation_payload jsonb not null default '{}'::jsonb,
  sync_payload jsonb not null default '{}'::jsonb,
  ledger_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_lwf_period_ledger_state_check check (btrim(state_code) <> ''),
  constraint wcm_lwf_period_ledger_calc_check check (jsonb_typeof(calculation_payload) = 'object'),
  constraint wcm_lwf_period_ledger_sync_check check (jsonb_typeof(sync_payload) = 'object'),
  constraint wcm_lwf_period_ledger_metadata_check check (jsonb_typeof(ledger_metadata) = 'object'),
  constraint wcm_lwf_period_ledger_unique unique (employee_id, payroll_period, batch_id)
);
create index if not exists idx_wcm_lwf_period_ledger_batch on public.wcm_lwf_period_ledger (batch_id, employee_id);
create index if not exists idx_wcm_lwf_period_ledger_period on public.wcm_lwf_period_ledger (payroll_period desc, employee_id);
create index if not exists idx_wcm_lwf_period_ledger_sync on public.wcm_lwf_period_ledger (sync_status, payroll_period desc);
create index if not exists idx_wcm_lwf_period_ledger_state on public.wcm_lwf_period_ledger (state_code, payroll_period desc);

create table if not exists public.wcm_lwf_dead_letter_entry (
  dead_letter_id uuid primary key default gen_random_uuid(),
  batch_id bigint not null,
  employee_id uuid null,
  error_code text not null,
  error_message text not null,
  payload jsonb not null default '{}'::jsonb,
  resolution_status text not null default 'OPEN' check (resolution_status in ('OPEN','RETRIED','DISMISSED','RESOLVED')),
  resolved_by_actor_user_id uuid null,
  resolved_at timestamptz null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_lwf_dead_letter_payload_check check (jsonb_typeof(payload) = 'object')
);
create index if not exists idx_wcm_lwf_dead_letter_batch on public.wcm_lwf_dead_letter_entry (batch_id, resolution_status, created_at desc);
create index if not exists idx_wcm_lwf_dead_letter_employee on public.wcm_lwf_dead_letter_entry (employee_id, created_at desc);

create table if not exists public.wcm_lwf_audit_event (
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
  constraint wcm_lwf_audit_payload_check check (jsonb_typeof(payload) = 'object')
);
create index if not exists idx_wcm_lwf_audit_entity on public.wcm_lwf_audit_event (entity_type, entity_id, created_at desc);

create table if not exists public.wcm_lwf_compliance_summary (
  summary_id uuid primary key default gen_random_uuid(),
  state_code text not null,
  payroll_period date not null,
  total_employees integer not null default 0,
  overridden_count integer not null default 0,
  synced_count integer not null default 0,
  total_eligible_wages numeric(14,2) not null default 0,
  total_employee_contribution numeric(14,2) not null default 0,
  total_employer_contribution numeric(14,2) not null default 0,
  total_liability numeric(14,2) not null default 0,
  summary_payload jsonb not null default '{}'::jsonb,
  refreshed_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_lwf_compliance_summary_state_check check (btrim(state_code) <> ''),
  constraint wcm_lwf_compliance_summary_payload_check check (jsonb_typeof(summary_payload) = 'object'),
  constraint wcm_lwf_compliance_summary_unique unique (state_code, payroll_period)
);
create index if not exists idx_wcm_lwf_compliance_summary_period on public.wcm_lwf_compliance_summary (payroll_period desc, state_code);

alter table public.wcm_lwf_configuration enable row level security;
alter table public.wcm_lwf_wage_component_mapping enable row level security;
alter table public.wcm_lwf_processing_batch enable row level security;
alter table public.wcm_lwf_period_ledger enable row level security;
alter table public.wcm_lwf_dead_letter_entry enable row level security;
alter table public.wcm_lwf_audit_event enable row level security;
alter table public.wcm_lwf_compliance_summary enable row level security;

create or replace function public.platform_lwf_append_audit(
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
    'insert into %I.wcm_lwf_audit_event (event_type, event_status, entity_type, entity_id, actor_user_id, employee_id, batch_id, payload) values ($1,$2,$3,$4,$5,$6,$7,$8)',
    p_schema_name
  ) using p_event_type, p_event_status, p_entity_type, p_entity_id, p_actor_user_id, p_employee_id, p_batch_id, coalesce(p_payload, '{}'::jsonb);
end;
$function$;

create or replace function public.platform_lwf_frequency_applies(
  p_deduction_frequency text,
  p_deduction_months integer[],
  p_payroll_period date,
  p_is_fnf boolean default false,
  p_deduct_on_exit boolean default false
)
returns boolean
language plpgsql
immutable
as $function$
declare
  v_frequency text := upper(coalesce(nullif(btrim(p_deduction_frequency), ''), 'MONTHLY'));
  v_month integer := extract(month from date_trunc('month', coalesce(p_payroll_period, current_date)::timestamp)::date);
begin
  if coalesce(p_is_fnf, false) = true and coalesce(p_deduct_on_exit, false) = true then
    return true;
  end if;

  if array_length(coalesce(p_deduction_months, '{}'::integer[]), 1) is not null then
    return v_month = any(p_deduction_months);
  end if;

  if v_frequency = 'MONTHLY' then
    return true;
  elsif v_frequency = 'QUARTERLY' then
    return v_month in (3, 6, 9, 12);
  elsif v_frequency = 'HALF_YEARLY' then
    return v_month in (6, 12);
  elsif v_frequency = 'ANNUAL' then
    return v_month = 12;
  end if;

  return false;
end;
$function$;

create or replace function public.platform_lwf_resolve_employee_state_internal(
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
$function$;

create or replace function public.platform_lwf_get_employee_wages_internal(
  p_schema_name text,
  p_employee_id uuid,
  p_payroll_period date,
  p_state_code text
)
returns numeric
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_amount numeric;
begin
  execute format(
    'with eligible_components as (
       select distinct component_code
         from %I.wcm_lwf_wage_component_mapping
        where state_code = $1
          and is_lwf_eligible = true
          and effective_from <= $2
          and (effective_to is null or effective_to >= $2)
     )
     select coalesce(sum(r.calculated_amount), 0)
       from %I.wcm_component_calculation_result r
       join eligible_components ec on ec.component_code = r.component_code
      where r.employee_id = $3
        and r.payroll_period = $2
        and r.result_status in (''CALCULATED'',''PREVIEW'')',
    p_schema_name, p_schema_name
  ) into v_amount using p_state_code, p_payroll_period, p_employee_id;

  return coalesce(v_amount, 0);
end;
$function$;

create or replace function public.platform_lwf_calculate_contribution_internal(
  p_schema_name text,
  p_employee_id uuid,
  p_payroll_period date,
  p_is_fnf boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_state_code text;
  v_config record;
  v_rules jsonb;
  v_eligible_wages numeric := 0;
  v_employee_share numeric := 0;
  v_employer_share numeric := 0;
  v_wage_threshold numeric;
  v_share_mode text;
  v_should_apply boolean := false;
  v_deduct_on_exit boolean := false;
  v_zero_wage_handling text := 'SKIP';
  v_employee_amount numeric := 0;
  v_employer_amount numeric := 0;
begin
  v_state_code := public.platform_lwf_resolve_employee_state_internal(p_schema_name, p_employee_id, p_payroll_period);
  if v_state_code is null or btrim(v_state_code) = '' then
    return public.platform_json_response(false,'STATE_NOT_RESOLVED','Unable to resolve state for LWF calculation.',jsonb_build_object('employee_id', p_employee_id,'payroll_period', p_payroll_period));
  end if;

  execute format(
    'select configuration_id, state_code, effective_from, effective_to, deduction_frequency, deduction_months, contribution_rules
       from %I.wcm_lwf_configuration
      where state_code = $1
        and configuration_status = ''ACTIVE''
        and effective_from <= $2
        and (effective_to is null or effective_to >= $2)
      order by effective_from desc, created_at desc
      limit 1',
    p_schema_name
  ) into v_config using v_state_code, p_payroll_period;

  if v_config.configuration_id is null then
    return public.platform_json_response(false,'CONFIGURATION_NOT_FOUND','No active LWF configuration found for the resolved state.',jsonb_build_object('employee_id', p_employee_id,'state_code', v_state_code,'payroll_period', p_payroll_period));
  end if;

  v_rules := coalesce(v_config.contribution_rules, '{}'::jsonb);
  v_eligible_wages := public.platform_lwf_get_employee_wages_internal(p_schema_name, p_employee_id, p_payroll_period, v_state_code);
  v_employee_share := coalesce(public.platform_lwf_try_numeric(v_rules->>'employee_share'), 0);
  v_employer_share := coalesce(public.platform_lwf_try_numeric(v_rules->>'employer_share'), 0);
  v_wage_threshold := public.platform_lwf_try_numeric(v_rules->>'wage_threshold');
  v_share_mode := upper(coalesce(nullif(btrim(v_rules->>'share_mode'), ''), 'FIXED'));
  v_deduct_on_exit := lower(coalesce(v_rules->>'deduct_on_exit', 'false')) = 'true';
  v_zero_wage_handling := upper(coalesce(nullif(btrim(v_rules->>'zero_wage_handling'), ''), 'SKIP'));
  v_should_apply := public.platform_lwf_frequency_applies(v_config.deduction_frequency, v_config.deduction_months, p_payroll_period, p_is_fnf, v_deduct_on_exit);

  if v_wage_threshold is not null and v_eligible_wages > v_wage_threshold then
    v_should_apply := false;
  end if;

  if coalesce(v_eligible_wages, 0) <= 0 and v_zero_wage_handling <> 'DEDUCT_ANYWAY' then
    v_should_apply := false;
  end if;

  if v_should_apply then
    if v_share_mode = 'PERCENTAGE' then
      v_employee_amount := round(coalesce(v_eligible_wages, 0) * coalesce(v_employee_share, 0) / 100.0, 2);
      v_employer_amount := round(coalesce(v_eligible_wages, 0) * coalesce(v_employer_share, 0) / 100.0, 2);
    else
      v_employee_amount := round(coalesce(v_employee_share, 0), 2);
      v_employer_amount := round(coalesce(v_employer_share, 0), 2);
    end if;
  else
    v_employee_amount := 0;
    v_employer_amount := 0;
  end if;

  return public.platform_json_response(true,'OK','LWF contribution calculated.',jsonb_build_object(
    'employee_id', p_employee_id,
    'payroll_period', p_payroll_period,
    'state_code', v_state_code,
    'configuration_id', v_config.configuration_id,
    'deduction_frequency', v_config.deduction_frequency,
    'deduction_months', coalesce(to_jsonb(v_config.deduction_months), '[]'::jsonb),
    'eligible_wages', round(coalesce(v_eligible_wages, 0), 2),
    'should_apply', v_should_apply,
    'employee_contribution', v_employee_amount,
    'employer_contribution', v_employer_amount,
    'contribution_rules', v_rules,
    'wage_threshold', v_wage_threshold,
    'share_mode', v_share_mode
  ));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_lwf_calculate_contribution_internal.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm,'employee_id', p_employee_id));
end;
$function$;

create or replace function public.platform_lwf_sync_to_payroll_internal(
  p_schema_name text,
  p_tenant_id uuid,
  p_employee_id uuid,
  p_payroll_period date,
  p_batch_id bigint,
  p_source_record_id text,
  p_employee_contribution numeric,
  p_employer_contribution numeric
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_result jsonb;
  v_component jsonb;
  v_components jsonb := jsonb_build_array(
    jsonb_build_object('component_code', 'LWF_DEDUCTION', 'numeric_value', round(coalesce(p_employee_contribution, 0), 2)),
    jsonb_build_object('component_code', 'LWF_EMPLOYER_CONTRIB', 'numeric_value', round(coalesce(p_employer_contribution, 0), 2))
  );
begin
  for v_component in select * from jsonb_array_elements(v_components)
  loop
    v_result := public.platform_upsert_payroll_input_entry(jsonb_build_object(
      'tenant_id', p_tenant_id,
      'employee_id', p_employee_id,
      'payroll_period', p_payroll_period,
      'component_code', v_component->>'component_code',
      'input_source', 'STATUTORY',
      'source_record_id', p_source_record_id,
      'source_batch_id', p_batch_id,
      'numeric_value', public.platform_lwf_try_numeric(v_component->>'numeric_value'),
      'source_metadata', jsonb_build_object('module', 'LWF', 'tenant_schema', p_schema_name, 'batch_id', p_batch_id),
      'input_status', 'VALIDATED'
    ));
    if coalesce((v_result->>'success')::boolean, false) is not true then
      return v_result;
    end if;
  end loop;

  return public.platform_json_response(true,'OK','LWF contributions synced to payroll input.',jsonb_build_object('employee_id', p_employee_id,'payroll_period', p_payroll_period,'batch_id', p_batch_id));
end;
$function$;

create or replace function public.platform_refresh_lwf_compliance_summary_internal(
  p_schema_name text,
  p_payroll_period date,
  p_state_code text
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_total_employees integer := 0;
  v_overridden_count integer := 0;
  v_synced_count integer := 0;
  v_total_eligible_wages numeric := 0;
  v_total_employee_contribution numeric := 0;
  v_total_employer_contribution numeric := 0;
begin
  execute format(
    'select
        count(distinct employee_id),
        count(*) filter (where override_status = ''MANUAL''),
        count(*) filter (where sync_status = ''SYNCED''),
        coalesce(sum(eligible_wages), 0),
        coalesce(sum(final_employee_contribution), 0),
        coalesce(sum(final_employer_contribution), 0)
       from %I.wcm_lwf_period_ledger
      where payroll_period = $1
        and state_code = $2',
    p_schema_name
  ) into
    v_total_employees,
    v_overridden_count,
    v_synced_count,
    v_total_eligible_wages,
    v_total_employee_contribution,
    v_total_employer_contribution
  using p_payroll_period, p_state_code;

  execute format(
    'insert into %I.wcm_lwf_compliance_summary (
       state_code, payroll_period, total_employees, overridden_count, synced_count,
       total_eligible_wages, total_employee_contribution, total_employer_contribution, total_liability,
       summary_payload, refreshed_at, updated_at
     ) values (
       $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,timezone(''utc'', now()),timezone(''utc'', now())
     )
     on conflict (state_code, payroll_period) do update
       set total_employees = excluded.total_employees,
           overridden_count = excluded.overridden_count,
           synced_count = excluded.synced_count,
           total_eligible_wages = excluded.total_eligible_wages,
           total_employee_contribution = excluded.total_employee_contribution,
           total_employer_contribution = excluded.total_employer_contribution,
           total_liability = excluded.total_liability,
           summary_payload = excluded.summary_payload,
           refreshed_at = excluded.refreshed_at,
           updated_at = excluded.updated_at',
    p_schema_name
  ) using
    p_state_code,
    p_payroll_period,
    coalesce(v_total_employees, 0),
    coalesce(v_overridden_count, 0),
    coalesce(v_synced_count, 0),
    round(coalesce(v_total_eligible_wages, 0), 2),
    round(coalesce(v_total_employee_contribution, 0), 2),
    round(coalesce(v_total_employer_contribution, 0), 2),
    round(coalesce(v_total_employee_contribution, 0) + coalesce(v_total_employer_contribution, 0), 2),
    jsonb_build_object(
      'state_code', p_state_code,
      'payroll_period', p_payroll_period,
      'total_employees', coalesce(v_total_employees, 0),
      'overridden_count', coalesce(v_overridden_count, 0),
      'synced_count', coalesce(v_synced_count, 0)
    );
end;
$function$;

create or replace function public.platform_apply_lwf_to_tenant(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_try_uuid(p_params->>'tenant_id');
  v_template_version text := public.platform_lwf_module_template_version();
  v_dependency_result jsonb;
  v_apply_result jsonb;
  v_context jsonb;
  v_schema_name text;
  v_table_name text;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false,'TENANT_ID_REQUIRED','tenant_id is required.','{}'::jsonb);
  end if;

  v_dependency_result := public.platform_apply_wcm_core_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_lwf_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;
  v_dependency_result := public.platform_apply_payroll_core_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_lwf_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;
  v_dependency_result := public.platform_apply_ptax_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_lwf_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;

  v_apply_result := public.platform_apply_template_version_to_tenant(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'template_version', v_template_version,
    'source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_apply_lwf_to_tenant')
  ));
  if coalesce((v_apply_result->>'success')::boolean, false) is not true then
    return v_apply_result;
  end if;

  v_context := public.platform_lwf_resolve_context(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_lwf_to_tenant'));
  if coalesce((v_context->>'success')::boolean, false) is not true then
    return v_context;
  end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  foreach v_table_name in array array['wcm_lwf_configuration','wcm_lwf_wage_component_mapping','wcm_lwf_processing_batch','wcm_lwf_period_ledger','wcm_lwf_dead_letter_entry','wcm_lwf_audit_event','wcm_lwf_compliance_summary'] loop
    if not public.platform_table_exists(v_schema_name, v_table_name) then
      return public.platform_json_response(false,'LWF_TABLES_MISSING','Expected LWF tenant tables were missing after template apply.',jsonb_build_object('tenant_schema', v_schema_name, 'missing_table', v_table_name));
    end if;
    execute format('alter table %I.%I enable row level security', v_schema_name, v_table_name);
  end loop;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_lwf_processing_batch'
      and c.conname = 'wcm_lwf_processing_batch_source_batch_fk'
  ) then
    execute format('alter table %I.wcm_lwf_processing_batch add constraint wcm_lwf_processing_batch_source_batch_fk foreign key (source_batch_id) references %I.wcm_payroll_batch(payroll_batch_id) on delete set null', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_lwf_period_ledger'
      and c.conname = 'wcm_lwf_period_ledger_batch_fk'
  ) then
    execute format('alter table %I.wcm_lwf_period_ledger add constraint wcm_lwf_period_ledger_batch_fk foreign key (batch_id) references %I.wcm_lwf_processing_batch(batch_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_lwf_period_ledger'
      and c.conname = 'wcm_lwf_period_ledger_employee_fk'
  ) then
    execute format('alter table %I.wcm_lwf_period_ledger add constraint wcm_lwf_period_ledger_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_lwf_dead_letter_entry'
      and c.conname = 'wcm_lwf_dead_letter_batch_fk'
  ) then
    execute format('alter table %I.wcm_lwf_dead_letter_entry add constraint wcm_lwf_dead_letter_batch_fk foreign key (batch_id) references %I.wcm_lwf_processing_batch(batch_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_lwf_dead_letter_entry'
      and c.conname = 'wcm_lwf_dead_letter_employee_fk'
  ) then
    execute format('alter table %I.wcm_lwf_dead_letter_entry add constraint wcm_lwf_dead_letter_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete set null', v_schema_name, v_schema_name);
  end if;

  execute format('create index if not exists idx_%s_lwf_period_ledger_employee_cover on %I.wcm_lwf_period_ledger (employee_id, payroll_period desc, batch_id)', replace(v_schema_name, '-', '_'), v_schema_name);
  execute format('create index if not exists idx_%s_lwf_dead_letter_batch_cover on %I.wcm_lwf_dead_letter_entry (batch_id, resolution_status, created_at desc)', replace(v_schema_name, '-', '_'), v_schema_name);
  execute format('create index if not exists idx_%s_lwf_summary_state_cover on %I.wcm_lwf_compliance_summary (state_code, payroll_period desc)', replace(v_schema_name, '-', '_'), v_schema_name);

  return public.platform_json_response(true,'OK','LWF applied to tenant.',jsonb_build_object('tenant_id', v_tenant_id, 'tenant_schema', v_schema_name, 'template_version', v_template_version));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_apply_lwf_to_tenant.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;
create or replace function public.platform_upsert_lwf_configuration(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_configuration_id uuid;
  v_state_code text := upper(btrim(coalesce(p_params->>'state_code', '')));
  v_effective_from date := public.platform_lwf_try_date(p_params->>'effective_from');
  v_effective_to date := public.platform_lwf_try_date(p_params->>'effective_to');
  v_deduction_frequency text := upper(coalesce(nullif(btrim(p_params->>'deduction_frequency'), ''), 'MONTHLY'));
  v_deduction_months integer[] := '{}'::integer[];
  v_contribution_rules jsonb := coalesce(p_params->'contribution_rules', '{}'::jsonb);
  v_configuration_status text := upper(coalesce(nullif(btrim(p_params->>'configuration_status'), ''), 'ACTIVE'));
  v_configuration_version integer := greatest(coalesce((p_params->>'configuration_version')::integer, 1), 1);
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  if v_state_code = '' then return public.platform_json_response(false,'STATE_CODE_REQUIRED','state_code is required.','{}'::jsonb); end if;
  if v_effective_from is null then return public.platform_json_response(false,'EFFECTIVE_FROM_REQUIRED','effective_from is required.','{}'::jsonb); end if;
  if jsonb_typeof(v_contribution_rules) <> 'object' then return public.platform_json_response(false,'INVALID_CONTRIBUTION_RULES','contribution_rules must be a JSON object.','{}'::jsonb); end if;
  if public.platform_lwf_try_numeric(v_contribution_rules->>'employee_share') is null then return public.platform_json_response(false,'EMPLOYEE_SHARE_REQUIRED','employee_share must be numeric.','{}'::jsonb); end if;
  if public.platform_lwf_try_numeric(v_contribution_rules->>'employer_share') is null then return public.platform_json_response(false,'EMPLOYER_SHARE_REQUIRED','employer_share must be numeric.','{}'::jsonb); end if;

  v_schema_name := v_context->'details'->>'tenant_schema';
  if jsonb_typeof(coalesce(p_params->'deduction_months', '[]'::jsonb)) = 'array' then
    select coalesce(array_agg(value::text::integer), '{}'::integer[])
      into v_deduction_months
    from jsonb_array_elements_text(coalesce(p_params->'deduction_months', '[]'::jsonb));
  end if;

  execute format(
    'insert into %I.wcm_lwf_configuration (state_code, effective_from, effective_to, deduction_frequency, deduction_months, contribution_rules, configuration_status, configuration_version, statutory_reference, configuration_metadata, created_by_actor_user_id, updated_by_actor_user_id)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$11)
     on conflict (state_code, effective_from) do update
       set effective_to = excluded.effective_to,
           deduction_frequency = excluded.deduction_frequency,
           deduction_months = excluded.deduction_months,
           contribution_rules = excluded.contribution_rules,
           configuration_status = excluded.configuration_status,
           configuration_version = excluded.configuration_version,
           statutory_reference = excluded.statutory_reference,
           configuration_metadata = excluded.configuration_metadata,
           updated_by_actor_user_id = excluded.updated_by_actor_user_id,
           updated_at = timezone(''utc'', now())
     returning configuration_id',
    v_schema_name
  ) into v_configuration_id using
    v_state_code,
    v_effective_from,
    v_effective_to,
    v_deduction_frequency,
    v_deduction_months,
    v_contribution_rules,
    v_configuration_status,
    v_configuration_version,
    nullif(btrim(p_params->>'statutory_reference'), ''),
    coalesce(p_params->'configuration_metadata', '{}'::jsonb),
    v_actor_user_id;

  perform public.platform_lwf_append_audit(v_schema_name, 'CONFIGURATION_UPSERTED', 'SUCCESS', 'wcm_lwf_configuration', v_configuration_id::text, jsonb_build_object('state_code', v_state_code, 'effective_from', v_effective_from), v_actor_user_id);

  return public.platform_json_response(true,'OK','LWF configuration upserted.',jsonb_build_object('configuration_id', v_configuration_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_upsert_lwf_configuration.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_upsert_lwf_wage_component_mapping(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_mapping_id uuid;
  v_state_code text := upper(btrim(coalesce(p_params->>'state_code', '')));
  v_component_code text := upper(btrim(coalesce(p_params->>'component_code', '')));
  v_effective_from date := public.platform_lwf_try_date(p_params->>'effective_from');
  v_effective_to date := public.platform_lwf_try_date(p_params->>'effective_to');
  v_is_lwf_eligible boolean := coalesce((p_params->>'is_lwf_eligible')::boolean, true);
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  if v_state_code = '' then return public.platform_json_response(false,'STATE_CODE_REQUIRED','state_code is required.','{}'::jsonb); end if;
  if v_component_code = '' then return public.platform_json_response(false,'COMPONENT_CODE_REQUIRED','component_code is required.','{}'::jsonb); end if;
  if v_effective_from is null then return public.platform_json_response(false,'EFFECTIVE_FROM_REQUIRED','effective_from is required.','{}'::jsonb); end if;

  v_schema_name := v_context->'details'->>'tenant_schema';

  execute format(
    'insert into %I.wcm_lwf_wage_component_mapping (state_code, component_code, is_lwf_eligible, effective_from, effective_to, mapping_metadata, created_by_actor_user_id, updated_by_actor_user_id)
     values ($1,$2,$3,$4,$5,$6,$7,$7)
     on conflict (state_code, component_code, effective_from) do update
       set is_lwf_eligible = excluded.is_lwf_eligible,
           effective_to = excluded.effective_to,
           mapping_metadata = excluded.mapping_metadata,
           updated_by_actor_user_id = excluded.updated_by_actor_user_id,
           updated_at = timezone(''utc'', now())
     returning wage_component_mapping_id',
    v_schema_name
  ) into v_mapping_id using
    v_state_code,
    v_component_code,
    v_is_lwf_eligible,
    v_effective_from,
    v_effective_to,
    coalesce(p_params->'mapping_metadata', '{}'::jsonb),
    v_actor_user_id;

  perform public.platform_lwf_append_audit(v_schema_name, 'WAGE_MAPPING_UPSERTED', 'SUCCESS', 'wcm_lwf_wage_component_mapping', v_mapping_id::text, jsonb_build_object('state_code', v_state_code, 'component_code', v_component_code, 'is_lwf_eligible', v_is_lwf_eligible), v_actor_user_id);

  return public.platform_json_response(true,'OK','LWF wage-component mapping upserted.',jsonb_build_object('wage_component_mapping_id', v_mapping_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_upsert_lwf_wage_component_mapping.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_request_lwf_batch(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context(p_params);
  v_schema_name text;
  v_tenant_id uuid;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_state_code text := upper(btrim(coalesce(p_params->>'state_code', '')));
  v_payroll_period date := date_trunc('month', coalesce(public.platform_lwf_try_date(p_params->>'payroll_period'), current_date)::timestamp)::date;
  v_batch_source text := upper(coalesce(nullif(btrim(p_params->>'batch_source'), ''), 'MANUAL'));
  v_source_batch_id uuid := public.platform_try_uuid(p_params->>'source_batch_id');
  v_source_batch_ref text := nullif(btrim(coalesce(p_params->>'source_batch_ref', case when v_source_batch_id is not null then v_source_batch_id::text else '' end)), '');
  v_requested_employee_ids jsonb := coalesce(p_params->'requested_employee_ids', '[]'::jsonb);
  v_existing_batch_id bigint;
  v_batch_id bigint;
  v_job_result jsonb;
  v_job_id uuid;
  v_config_id uuid;
  v_source_batch record;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  if v_state_code = '' then return public.platform_json_response(false,'STATE_CODE_REQUIRED','state_code is required.','{}'::jsonb); end if;
  if jsonb_typeof(v_requested_employee_ids) <> 'array' then return public.platform_json_response(false,'INVALID_REQUESTED_EMPLOYEE_IDS','requested_employee_ids must be a JSON array.','{}'::jsonb); end if;

  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');

  execute format(
    'select configuration_id
       from %I.wcm_lwf_configuration
      where state_code = $1
        and configuration_status = ''ACTIVE''
        and effective_from <= $2
        and (effective_to is null or effective_to >= $2)
      order by effective_from desc
      limit 1',
    v_schema_name
  ) into v_config_id using v_state_code, v_payroll_period;
  if v_config_id is null then
    return public.platform_json_response(false,'CONFIGURATION_NOT_FOUND','No active LWF configuration found for the requested state and period.',jsonb_build_object('state_code', v_state_code, 'payroll_period', v_payroll_period));
  end if;
  if v_batch_source not in ('MANUAL','PAYROLL_COMPLETION','FNF') then
    return public.platform_json_response(false,'INVALID_BATCH_SOURCE','batch_source must be MANUAL, PAYROLL_COMPLETION, or FNF.',jsonb_build_object('batch_source', v_batch_source));
  end if;

  if v_source_batch_id is not null then
    execute format(
      'select payroll_batch_id, payroll_period, batch_status
         from %I.wcm_payroll_batch
        where payroll_batch_id = $1',
      v_schema_name
    ) into v_source_batch using v_source_batch_id;
    if v_source_batch.payroll_batch_id is null then
      return public.platform_json_response(false,'SOURCE_BATCH_NOT_FOUND','Source payroll batch was not found.',jsonb_build_object('source_batch_id', v_source_batch_id));
    end if;
    if v_batch_source = 'PAYROLL_COMPLETION' and v_source_batch.batch_status not in ('PROCESSED','FINALIZED') then
      return public.platform_json_response(false,'SOURCE_BATCH_NOT_READY','Source payroll batch must be PROCESSED or FINALIZED before LWF scheduling.',jsonb_build_object('source_batch_id', v_source_batch_id, 'batch_status', v_source_batch.batch_status));
    end if;
  end if;

  if v_source_batch_id is not null and jsonb_array_length(v_requested_employee_ids) = 0 then
    execute format(
      'select coalesce(jsonb_agg(distinct employee_id::text order by employee_id::text), ''[]''::jsonb)
         from %I.wcm_component_calculation_result
        where payroll_batch_id = $1
          and payroll_period = $2',
      v_schema_name
    ) into v_requested_employee_ids using v_source_batch_id, v_payroll_period;
  end if;

  if jsonb_array_length(v_requested_employee_ids) = 0 then
    if v_source_batch_id is not null then
      return public.platform_json_response(false,'SOURCE_BATCH_EMPLOYEES_NOT_FOUND','No payroll-result employees were found for the requested LWF source batch.',jsonb_build_object('source_batch_id', v_source_batch_id, 'payroll_period', v_payroll_period));
    end if;
    return public.platform_json_response(false,'REQUESTED_EMPLOYEE_IDS_REQUIRED','requested_employee_ids is required when source_batch_id is not supplied.','{}'::jsonb);
  end if;

  execute format(
    'select batch_id
       from %I.wcm_lwf_processing_batch
      where state_code = $1
        and payroll_period = $2
        and batch_source = $3
        and coalesce(source_batch_ref, '''') = coalesce($4, '''')
        and batch_status in (''REQUESTED'',''PROCESSING'')
      order by batch_id desc
      limit 1',
    v_schema_name
  ) into v_existing_batch_id using v_state_code, v_payroll_period, v_batch_source, v_source_batch_ref;

  if v_existing_batch_id is not null then
    return public.platform_json_response(true,'OK','Active LWF batch already exists.',jsonb_build_object('batch_id', v_existing_batch_id));
  end if;

  execute format(
    'insert into %I.wcm_lwf_processing_batch (state_code, payroll_period, batch_source, source_batch_id, source_batch_ref, requested_employee_ids, requested_by_actor_user_id, batch_status, summary_payload, error_payload)
     values ($1,$2,$3,$4,$5,$6,$7,''REQUESTED'',''{}''::jsonb,''{}''::jsonb)
     returning batch_id',
    v_schema_name
  ) into v_batch_id using v_state_code, v_payroll_period, v_batch_source, v_source_batch_id, v_source_batch_ref, v_requested_employee_ids, v_actor_user_id;

  v_job_result := public.platform_async_enqueue_job(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'worker_code', 'lwf_period_worker',
    'job_type', 'lwf_period_process',
    'payload', jsonb_build_object('batch_id', v_batch_id),
    'idempotency_key', format('lwf:%s:%s:%s:%s', v_state_code, v_payroll_period, v_batch_source, coalesce(v_source_batch_ref, v_batch_id::text)),
    'deduplication_key', format('lwf:%s:%s:%s:%s', v_state_code, v_payroll_period, v_batch_source, coalesce(v_source_batch_ref, v_batch_id::text)),
    'origin_source', 'platform_request_lwf_batch',
    'metadata', jsonb_build_object('module', 'LWF', 'batch_id', v_batch_id, 'state_code', v_state_code, 'payroll_period', v_payroll_period)
  ));
  if coalesce((v_job_result->>'success')::boolean, false) is true then
    v_job_id := public.platform_try_uuid(v_job_result->'details'->>'job_id');
    if v_job_id is not null then
      execute format('update %I.wcm_lwf_processing_batch set worker_job_id = $2, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name) using v_batch_id, v_job_id;
    end if;

    perform public.platform_lwf_append_audit(v_schema_name, 'BATCH_REQUESTED', 'SUCCESS', 'wcm_lwf_processing_batch', v_batch_id::text, jsonb_build_object('state_code', v_state_code, 'payroll_period', v_payroll_period, 'batch_source', v_batch_source, 'job_id', v_job_id), v_actor_user_id, null, v_batch_id);

    return public.platform_json_response(true,'OK','LWF batch requested.',jsonb_build_object('batch_id', v_batch_id, 'worker_job_id', v_job_id, 'state_code', v_state_code, 'payroll_period', v_payroll_period));
  end if;

  execute format(
    'update %I.wcm_lwf_processing_batch
        set batch_status = ''FAILED'',
            error_payload = $2,
            updated_at = timezone(''utc'', now())
      where batch_id = $1',
    v_schema_name
  ) using v_batch_id, jsonb_build_object('enqueue_result', coalesce(v_job_result, '{}'::jsonb));

  perform public.platform_lwf_append_audit(v_schema_name, 'BATCH_REQUEST_FAILED', 'FAILED', 'wcm_lwf_processing_batch', v_batch_id::text, jsonb_build_object('state_code', v_state_code, 'payroll_period', v_payroll_period, 'batch_source', v_batch_source, 'enqueue_result', coalesce(v_job_result, '{}'::jsonb)), v_actor_user_id, null, v_batch_id);

  return public.platform_json_response(false,'ASYNC_ENQUEUE_FAILED','LWF batch request could not be enqueued on the shared async spine.',jsonb_build_object('batch_id', v_batch_id, 'enqueue_result', coalesce(v_job_result, '{}'::jsonb)));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_request_lwf_batch.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;
create or replace function public.platform_schedule_lwf_from_payroll(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context(p_params);
  v_schema_name text;
  v_tenant_id uuid;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_source_batch_id uuid := public.platform_try_uuid(p_params->>'source_batch_id');
  v_source_batch record;
  v_state_groups jsonb := '{}'::jsonb;
  v_employee_id uuid;
  v_state_code text;
  v_batches jsonb := '[]'::jsonb;
  v_state_key text;
  v_employee_list jsonb;
  v_batch_result jsonb;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  if v_source_batch_id is null then return public.platform_json_response(false,'SOURCE_BATCH_ID_REQUIRED','source_batch_id is required.','{}'::jsonb); end if;

  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');

  execute format(
    'select payroll_batch_id, payroll_period, batch_status
       from %I.wcm_payroll_batch
      where payroll_batch_id = $1',
    v_schema_name
  ) into v_source_batch using v_source_batch_id;
  if v_source_batch.payroll_batch_id is null then
    return public.platform_json_response(false,'SOURCE_BATCH_NOT_FOUND','Source payroll batch was not found.',jsonb_build_object('source_batch_id', v_source_batch_id));
  end if;
  if v_source_batch.batch_status not in ('PROCESSED','FINALIZED') then
    return public.platform_json_response(false,'SOURCE_BATCH_NOT_READY','Source payroll batch must be PROCESSED or FINALIZED before LWF scheduling.',jsonb_build_object('source_batch_id', v_source_batch_id, 'batch_status', v_source_batch.batch_status));
  end if;

  for v_employee_id in
    execute format(
      'select distinct employee_id
         from %I.wcm_component_calculation_result
        where payroll_batch_id = $1
          and payroll_period = $2
        order by employee_id',
      v_schema_name
    ) using v_source_batch_id, v_source_batch.payroll_period
  loop
    v_state_code := public.platform_lwf_resolve_employee_state_internal(v_schema_name, v_employee_id, v_source_batch.payroll_period);
    if v_state_code is null or btrim(v_state_code) = '' then
      continue;
    end if;

    if coalesce(v_state_groups ? v_state_code, false) then
      v_state_groups := jsonb_set(v_state_groups, array[v_state_code], (coalesce(v_state_groups->v_state_code, '[]'::jsonb) || to_jsonb(v_employee_id::text)), true);
    else
      v_state_groups := jsonb_set(v_state_groups, array[v_state_code], jsonb_build_array(v_employee_id::text), true);
    end if;
  end loop;

  for v_state_key, v_employee_list in
    select key, value
    from jsonb_each(v_state_groups)
  loop
    v_batch_result := public.platform_request_lwf_batch(jsonb_build_object(
      'tenant_id', v_tenant_id,
      'state_code', v_state_key,
      'payroll_period', v_source_batch.payroll_period,
      'batch_source', 'PAYROLL_COMPLETION',
      'source_batch_id', v_source_batch_id,
      'source_batch_ref', format('%s:%s', v_source_batch_id, v_state_key),
      'requested_employee_ids', v_employee_list,
      'actor_user_id', v_actor_user_id
    ));
    v_batches := v_batches || jsonb_build_array(coalesce(v_batch_result->'details', '{}'::jsonb) || jsonb_build_object('state_code', v_state_key, 'success', coalesce((v_batch_result->>'success')::boolean, false)));
  end loop;

  return public.platform_json_response(true,'OK','LWF scheduling from payroll completed.',jsonb_build_object('source_batch_id', v_source_batch_id, 'batches', v_batches));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_schedule_lwf_from_payroll.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_process_lwf_batch_job(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context(p_params);
  v_schema_name text;
  v_tenant_id uuid;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_batch_id bigint := nullif(p_params->>'batch_id', '')::bigint;
  v_batch record;
  v_employee_id uuid;
  v_requested_count integer := 0;
  v_processed_count integer := 0;
  v_synced_count integer := 0;
  v_error_count integer := 0;
  v_calc_result jsonb;
  v_details jsonb;
  v_ledger_id uuid;
  v_sync_result jsonb;
  v_final_employee numeric;
  v_final_employer numeric;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  if v_batch_id is null then return public.platform_json_response(false,'BATCH_ID_REQUIRED','batch_id is required.','{}'::jsonb); end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');

  execute format('select * from %I.wcm_lwf_processing_batch where batch_id = $1', v_schema_name) into v_batch using v_batch_id;
  if v_batch.batch_id is null then
    return public.platform_json_response(false,'BATCH_NOT_FOUND','LWF batch was not found.',jsonb_build_object('batch_id', v_batch_id));
  end if;
  if v_batch.batch_status not in ('REQUESTED','FAILED') then
    return public.platform_json_response(false,'BATCH_NOT_PROCESSABLE','Only REQUESTED or FAILED batches can be processed.',jsonb_build_object('batch_id', v_batch_id, 'batch_status', v_batch.batch_status));
  end if;

  execute format('update %I.wcm_lwf_processing_batch set batch_status = ''PROCESSING'', process_started_at = timezone(''utc'', now()), process_completed_at = null, error_payload = ''{}''::jsonb, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name)
    using v_batch_id;

  if jsonb_array_length(coalesce(v_batch.requested_employee_ids, '[]'::jsonb)) > 0 then
    for v_employee_id in
      select public.platform_try_uuid(value)
      from jsonb_array_elements_text(v_batch.requested_employee_ids)
    loop
      continue when v_employee_id is null;
      v_requested_count := v_requested_count + 1;
      v_calc_result := public.platform_lwf_calculate_contribution_internal(v_schema_name, v_employee_id, v_batch.payroll_period, v_batch.batch_source = 'FNF');
      if coalesce((v_calc_result->>'success')::boolean, false) is not true then
        v_error_count := v_error_count + 1;
        execute format(
          'insert into %I.wcm_lwf_dead_letter_entry (batch_id, employee_id, error_code, error_message, payload)
           values ($1,$2,$3,$4,$5)',
          v_schema_name
        ) using v_batch_id, v_employee_id, coalesce(v_calc_result->>'code', 'CALCULATION_FAILED'), coalesce(v_calc_result->>'message', 'LWF calculation failed.'), coalesce(v_calc_result->'details', '{}'::jsonb);
        continue;
      end if;

      v_details := coalesce(v_calc_result->'details', '{}'::jsonb);
      if coalesce(v_details->>'state_code', '') <> v_batch.state_code then
        v_error_count := v_error_count + 1;
        execute format(
          'insert into %I.wcm_lwf_dead_letter_entry (batch_id, employee_id, error_code, error_message, payload)
           values ($1,$2,''STATE_MISMATCH'',''Resolved state did not match the requested batch state.'',$3)',
          v_schema_name
        ) using v_batch_id, v_employee_id, v_details;
        continue;
      end if;

      execute format(
        'insert into %I.wcm_lwf_period_ledger (
           batch_id, employee_id, payroll_period, state_code, eligible_wages,
           system_employee_contribution, system_employer_contribution,
           final_employee_contribution, final_employer_contribution,
           override_status, sync_status, calculation_payload, sync_payload, ledger_metadata
         ) values (
           $1,$2,$3,$4,$5,$6,$7,$6,$7,''NONE'',''PENDING'',$8,''{}''::jsonb,jsonb_build_object(''batch_source'', $9))
         on conflict (employee_id, payroll_period, batch_id) do update
           set state_code = excluded.state_code,
               eligible_wages = excluded.eligible_wages,
               system_employee_contribution = excluded.system_employee_contribution,
               system_employer_contribution = excluded.system_employer_contribution,
               final_employee_contribution = case when %I.wcm_lwf_period_ledger.override_status = ''MANUAL'' then %I.wcm_lwf_period_ledger.final_employee_contribution else excluded.final_employee_contribution end,
               final_employer_contribution = case when %I.wcm_lwf_period_ledger.override_status = ''MANUAL'' then %I.wcm_lwf_period_ledger.final_employer_contribution else excluded.final_employer_contribution end,
               calculation_payload = excluded.calculation_payload,
               ledger_metadata = excluded.ledger_metadata,
               updated_at = timezone(''utc'', now())
         returning contribution_ledger_id, final_employee_contribution, final_employer_contribution',
        v_schema_name, v_schema_name, v_schema_name, v_schema_name
      ) into v_ledger_id, v_final_employee, v_final_employer using
        v_batch_id,
        v_employee_id,
        v_batch.payroll_period,
        v_batch.state_code,
        round(coalesce(public.platform_lwf_try_numeric(v_details->>'eligible_wages'), 0), 2),
        round(coalesce(public.platform_lwf_try_numeric(v_details->>'employee_contribution'), 0), 2),
        round(coalesce(public.platform_lwf_try_numeric(v_details->>'employer_contribution'), 0), 2),
        v_details,
        v_batch.batch_source;

      v_sync_result := public.platform_lwf_sync_to_payroll_internal(v_schema_name, v_tenant_id, v_employee_id, v_batch.payroll_period, v_batch_id, v_ledger_id::text, v_final_employee, v_final_employer);
      if coalesce((v_sync_result->>'success')::boolean, false) is not true then
        v_error_count := v_error_count + 1;
        execute format(
          'update %I.wcm_lwf_period_ledger
              set sync_status = ''ERROR'',
                  sync_payload = $2,
                  updated_at = timezone(''utc'', now())
            where contribution_ledger_id = $1',
          v_schema_name
        ) using v_ledger_id, coalesce(v_sync_result->'details', '{}'::jsonb);
        execute format(
          'insert into %I.wcm_lwf_dead_letter_entry (batch_id, employee_id, error_code, error_message, payload)
           values ($1,$2,''PAYROLL_SYNC_FAILED'',''LWF payroll sync failed.'',$3)',
          v_schema_name
        ) using v_batch_id, v_employee_id, coalesce(v_sync_result->'details', '{}'::jsonb);
        continue;
      end if;

      execute format(
        'update %I.wcm_lwf_period_ledger
            set sync_status = ''SYNCED'',
                sync_payload = $2,
                updated_at = timezone(''utc'', now())
          where contribution_ledger_id = $1',
        v_schema_name
      ) using v_ledger_id, coalesce(v_sync_result->'details', '{}'::jsonb);

      v_processed_count := v_processed_count + 1;
      v_synced_count := v_synced_count + 1;
    end loop;
  end if;

  execute format(
    'update %I.wcm_lwf_processing_batch
        set batch_status = $2,
            process_completed_at = timezone(''utc'', now()),
            summary_payload = jsonb_build_object(''requested_count'', $3, ''processed_count'', $4, ''synced_count'', $5, ''error_count'', $6),
            error_payload = case when $6 > 0 then jsonb_build_object(''error_count'', $6) else ''{}''::jsonb end,
            updated_at = timezone(''utc'', now())
      where batch_id = $1',
    v_schema_name
  ) using v_batch_id, case when v_error_count > 0 then 'FAILED' else 'SYNCED' end, v_requested_count, v_processed_count, v_synced_count, v_error_count;

  perform public.platform_refresh_lwf_compliance_summary_internal(v_schema_name, v_batch.payroll_period, v_batch.state_code);
  perform public.platform_lwf_append_audit(v_schema_name, 'BATCH_PROCESSED', case when v_error_count > 0 then 'PARTIAL_FAILURE' else 'SUCCESS' end, 'wcm_lwf_processing_batch', v_batch_id::text, jsonb_build_object('requested_count', v_requested_count, 'processed_count', v_processed_count, 'synced_count', v_synced_count, 'error_count', v_error_count), v_actor_user_id, null, v_batch_id);

  return public.platform_json_response(true,'OK','LWF batch processed.',jsonb_build_object('batch_id', v_batch_id, 'processed_count', v_processed_count, 'synced_count', v_synced_count, 'error_count', v_error_count, 'batch_status', case when v_error_count > 0 then 'FAILED' else 'SYNCED' end));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_process_lwf_batch_job.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm,'batch_id', v_batch_id));
end;
$function$;

create or replace function public.platform_request_lwf_retry_batch(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context(p_params);
  v_schema_name text;
  v_tenant_id uuid;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_batch_id bigint := nullif(p_params->>'batch_id', '')::bigint;
  v_batch record;
  v_job_result jsonb;
  v_job_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  if v_batch_id is null then return public.platform_json_response(false,'BATCH_ID_REQUIRED','batch_id is required.','{}'::jsonb); end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');

  execute format('select * from %I.wcm_lwf_processing_batch where batch_id = $1', v_schema_name) into v_batch using v_batch_id;
  if v_batch.batch_id is null then
    return public.platform_json_response(false,'BATCH_NOT_FOUND','LWF batch was not found.',jsonb_build_object('batch_id', v_batch_id));
  end if;
  if v_batch.batch_status not in ('FAILED','CANCELLED') then
    return public.platform_json_response(false,'BATCH_NOT_RETRYABLE','Only FAILED or CANCELLED batches can be retried.',jsonb_build_object('batch_id', v_batch_id, 'batch_status', v_batch.batch_status));
  end if;

  execute format(
    'update %I.wcm_lwf_processing_batch
        set batch_status = ''REQUESTED'',
            process_started_at = null,
            process_completed_at = null,
            error_payload = ''{}''::jsonb,
            updated_at = timezone(''utc'', now())
      where batch_id = $1',
    v_schema_name
  ) using v_batch_id;

  v_job_result := public.platform_async_enqueue_job(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'worker_code', 'lwf_period_worker',
    'job_type', 'lwf_period_process',
    'payload', jsonb_build_object('batch_id', v_batch_id),
    'idempotency_key', format('lwf-retry:%s', v_batch_id),
    'deduplication_key', format('lwf:%s:%s:%s:%s', v_batch.state_code, v_batch.payroll_period, v_batch.batch_source, coalesce(v_batch.source_batch_ref, v_batch_id::text)),
    'origin_source', 'platform_request_lwf_retry_batch',
    'metadata', jsonb_build_object('module', 'LWF', 'batch_id', v_batch_id, 'retry', true)
  ));
  v_job_id := public.platform_try_uuid(v_job_result->'details'->>'job_id');
  if v_job_id is not null then
    execute format('update %I.wcm_lwf_processing_batch set worker_job_id = $2, updated_at = timezone(''utc'', now()) where batch_id = $1', v_schema_name) using v_batch_id, v_job_id;
  end if;

  perform public.platform_lwf_append_audit(v_schema_name, 'BATCH_RETRY_REQUESTED', 'SUCCESS', 'wcm_lwf_processing_batch', v_batch_id::text, jsonb_build_object('worker_job_id', v_job_id), v_actor_user_id, null, v_batch_id);

  return public.platform_json_response(true,'OK','LWF batch retry requested.',jsonb_build_object('batch_id', v_batch_id, 'worker_job_id', v_job_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_request_lwf_retry_batch.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_cancel_lwf_batch(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_batch_id bigint := nullif(p_params->>'batch_id', '')::bigint;
  v_batch record;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  if v_batch_id is null then return public.platform_json_response(false,'BATCH_ID_REQUIRED','batch_id is required.','{}'::jsonb); end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  execute format('select * from %I.wcm_lwf_processing_batch where batch_id = $1', v_schema_name) into v_batch using v_batch_id;
  if v_batch.batch_id is null then
    return public.platform_json_response(false,'BATCH_NOT_FOUND','LWF batch was not found.',jsonb_build_object('batch_id', v_batch_id));
  end if;
  if v_batch.batch_status not in ('REQUESTED','FAILED') then
    return public.platform_json_response(false,'BATCH_NOT_CANCELLABLE','Only REQUESTED or FAILED batches can be cancelled.',jsonb_build_object('batch_id', v_batch_id, 'batch_status', v_batch.batch_status));
  end if;

  execute format(
    'update %I.wcm_lwf_processing_batch
        set batch_status = ''CANCELLED'',
            updated_at = timezone(''utc'', now())
      where batch_id = $1',
    v_schema_name
  ) using v_batch_id;

  perform public.platform_lwf_append_audit(v_schema_name, 'BATCH_CANCELLED', 'SUCCESS', 'wcm_lwf_processing_batch', v_batch_id::text, '{}'::jsonb, v_actor_user_id, null, v_batch_id);
  return public.platform_json_response(true,'OK','LWF batch cancelled.',jsonb_build_object('batch_id', v_batch_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_cancel_lwf_batch.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_apply_lwf_override(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context(p_params);
  v_schema_name text;
  v_tenant_id uuid;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_ledger_id uuid := public.platform_try_uuid(p_params->>'contribution_ledger_id');
  v_ledger record;
  v_final_employee numeric := public.platform_lwf_try_numeric(p_params->>'final_employee_contribution');
  v_final_employer numeric := public.platform_lwf_try_numeric(p_params->>'final_employer_contribution');
  v_reason text := nullif(btrim(coalesce(p_params->>'override_reason', '')), '');
  v_sync_result jsonb;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  if v_ledger_id is null then return public.platform_json_response(false,'CONTRIBUTION_LEDGER_ID_REQUIRED','contribution_ledger_id is required.','{}'::jsonb); end if;
  if v_final_employee is null or v_final_employer is null then return public.platform_json_response(false,'OVERRIDE_VALUES_REQUIRED','Both final_employee_contribution and final_employer_contribution are required.','{}'::jsonb); end if;
  if v_final_employee < 0 or v_final_employer < 0 then return public.platform_json_response(false,'OVERRIDE_VALUES_INVALID','LWF override contributions cannot be negative.','{}'::jsonb); end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');

  execute format('select * from %I.wcm_lwf_period_ledger where contribution_ledger_id = $1', v_schema_name) into v_ledger using v_ledger_id;
  if v_ledger.contribution_ledger_id is null then
    return public.platform_json_response(false,'LEDGER_NOT_FOUND','LWF contribution ledger record was not found.',jsonb_build_object('contribution_ledger_id', v_ledger_id));
  end if;

  execute format(
    'update %I.wcm_lwf_period_ledger
        set final_employee_contribution = $2,
            final_employer_contribution = $3,
            override_status = ''MANUAL'',
            override_reason = $4,
            overridden_by_actor_user_id = $5,
            overridden_at = timezone(''utc'', now()),
            updated_at = timezone(''utc'', now())
      where contribution_ledger_id = $1',
    v_schema_name
  ) using v_ledger_id, round(v_final_employee, 2), round(v_final_employer, 2), v_reason, v_actor_user_id;

  v_sync_result := public.platform_lwf_sync_to_payroll_internal(v_schema_name, v_tenant_id, v_ledger.employee_id, v_ledger.payroll_period, v_ledger.batch_id, v_ledger_id::text, round(v_final_employee, 2), round(v_final_employer, 2));
  if coalesce((v_sync_result->>'success')::boolean, false) is not true then
    return v_sync_result;
  end if;

  execute format(
    'update %I.wcm_lwf_period_ledger
        set sync_status = ''SYNCED'',
            sync_payload = $2,
            updated_at = timezone(''utc'', now())
      where contribution_ledger_id = $1',
    v_schema_name
  ) using v_ledger_id, coalesce(v_sync_result->'details', '{}'::jsonb);

  perform public.platform_refresh_lwf_compliance_summary_internal(v_schema_name, v_ledger.payroll_period, v_ledger.state_code);
  perform public.platform_lwf_append_audit(v_schema_name, 'OVERRIDE_APPLIED', 'SUCCESS', 'wcm_lwf_period_ledger', v_ledger_id::text, jsonb_build_object('final_employee_contribution', round(v_final_employee, 2), 'final_employer_contribution', round(v_final_employer, 2), 'override_reason', v_reason), v_actor_user_id, v_ledger.employee_id, v_ledger.batch_id);

  return public.platform_json_response(true,'OK','LWF override applied.',jsonb_build_object('contribution_ledger_id', v_ledger_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_apply_lwf_override.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;
create or replace function public.platform_remove_lwf_override(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context(p_params);
  v_schema_name text;
  v_tenant_id uuid;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_ledger_id uuid := public.platform_try_uuid(p_params->>'contribution_ledger_id');
  v_ledger record;
  v_sync_result jsonb;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  if v_ledger_id is null then return public.platform_json_response(false,'CONTRIBUTION_LEDGER_ID_REQUIRED','contribution_ledger_id is required.','{}'::jsonb); end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');

  execute format('select * from %I.wcm_lwf_period_ledger where contribution_ledger_id = $1', v_schema_name) into v_ledger using v_ledger_id;
  if v_ledger.contribution_ledger_id is null then
    return public.platform_json_response(false,'LEDGER_NOT_FOUND','LWF contribution ledger record was not found.',jsonb_build_object('contribution_ledger_id', v_ledger_id));
  end if;

  execute format(
    'update %I.wcm_lwf_period_ledger
        set final_employee_contribution = system_employee_contribution,
            final_employer_contribution = system_employer_contribution,
            override_status = ''NONE'',
            override_reason = null,
            overridden_by_actor_user_id = null,
            overridden_at = null,
            updated_at = timezone(''utc'', now())
      where contribution_ledger_id = $1',
    v_schema_name
  ) using v_ledger_id;

  execute format('select * from %I.wcm_lwf_period_ledger where contribution_ledger_id = $1', v_schema_name) into v_ledger using v_ledger_id;
  v_sync_result := public.platform_lwf_sync_to_payroll_internal(v_schema_name, v_tenant_id, v_ledger.employee_id, v_ledger.payroll_period, v_ledger.batch_id, v_ledger_id::text, v_ledger.final_employee_contribution, v_ledger.final_employer_contribution);
  if coalesce((v_sync_result->>'success')::boolean, false) is not true then
    return v_sync_result;
  end if;

  execute format(
    'update %I.wcm_lwf_period_ledger
        set sync_status = ''SYNCED'',
            sync_payload = $2,
            updated_at = timezone(''utc'', now())
      where contribution_ledger_id = $1',
    v_schema_name
  ) using v_ledger_id, coalesce(v_sync_result->'details', '{}'::jsonb);

  perform public.platform_refresh_lwf_compliance_summary_internal(v_schema_name, v_ledger.payroll_period, v_ledger.state_code);
  perform public.platform_lwf_append_audit(v_schema_name, 'OVERRIDE_REMOVED', 'SUCCESS', 'wcm_lwf_period_ledger', v_ledger_id::text, '{}'::jsonb, v_actor_user_id, v_ledger.employee_id, v_ledger.batch_id);

  return public.platform_json_response(true,'OK','LWF override removed.',jsonb_build_object('contribution_ledger_id', v_ledger_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_remove_lwf_override.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_lwf_configuration_catalog_rows()
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
  v_context jsonb := public.platform_lwf_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, configuration_id, state_code, effective_from, effective_to, deduction_frequency, configuration_status, configuration_version, updated_at
       from %I.wcm_lwf_configuration
      order by state_code, effective_from desc',
    v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_lwf_configuration_catalog as select * from public.platform_lwf_configuration_catalog_rows();

create or replace function public.platform_lwf_batch_catalog_rows()
returns table (
  tenant_id uuid,
  batch_id bigint,
  state_code text,
  payroll_period date,
  batch_source text,
  batch_status text,
  requested_count integer,
  processed_count integer,
  synced_count integer,
  error_count integer,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, batch_id, state_code, payroll_period, batch_source, batch_status,
            coalesce((summary_payload->>''requested_count'')::integer, 0),
            coalesce((summary_payload->>''processed_count'')::integer, 0),
            coalesce((summary_payload->>''synced_count'')::integer, 0),
            coalesce((summary_payload->>''error_count'')::integer, 0),
            updated_at
       from %I.wcm_lwf_processing_batch
      order by payroll_period desc, batch_id desc',
    v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_lwf_batch_catalog as select * from public.platform_lwf_batch_catalog_rows();

create or replace function public.platform_lwf_contribution_ledger_rows()
returns table (
  tenant_id uuid,
  contribution_ledger_id uuid,
  batch_id bigint,
  employee_id uuid,
  employee_code text,
  payroll_period date,
  state_code text,
  eligible_wages numeric,
  final_employee_contribution numeric,
  final_employer_contribution numeric,
  override_status text,
  sync_status text
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, l.contribution_ledger_id, l.batch_id, l.employee_id, e.employee_code, l.payroll_period, l.state_code, l.eligible_wages, l.final_employee_contribution, l.final_employer_contribution, l.override_status, l.sync_status
       from %I.wcm_lwf_period_ledger l
       join %I.wcm_employee e on e.employee_id = l.employee_id
      order by l.payroll_period desc, e.employee_code',
    v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_lwf_contribution_ledger as select * from public.platform_lwf_contribution_ledger_rows();

create or replace function public.platform_lwf_dead_letter_queue_rows()
returns table (
  tenant_id uuid,
  dead_letter_id uuid,
  batch_id bigint,
  employee_id uuid,
  employee_code text,
  error_code text,
  resolution_status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, d.dead_letter_id, d.batch_id, d.employee_id, e.employee_code, d.error_code, d.resolution_status, d.created_at
       from %I.wcm_lwf_dead_letter_entry d
       left join %I.wcm_employee e on e.employee_id = d.employee_id
      order by d.created_at desc, d.dead_letter_id desc',
    v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_lwf_dead_letter_queue as select * from public.platform_lwf_dead_letter_queue_rows();

create or replace function public.platform_lwf_compliance_summary_rows()
returns table (
  tenant_id uuid,
  summary_id uuid,
  state_code text,
  payroll_period date,
  total_employees integer,
  overridden_count integer,
  synced_count integer,
  total_eligible_wages numeric,
  total_employee_contribution numeric,
  total_employer_contribution numeric,
  total_liability numeric,
  refreshed_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_lwf_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, summary_id, state_code, payroll_period, total_employees, overridden_count, synced_count, total_eligible_wages, total_employee_contribution, total_employer_contribution, total_liability, refreshed_at
       from %I.wcm_lwf_compliance_summary
      order by payroll_period desc, state_code',
    v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_lwf_compliance_summary as select * from public.platform_lwf_compliance_summary_rows();

revoke all on function public.platform_lwf_module_template_version() from public, anon, authenticated;
revoke all on function public.platform_lwf_try_numeric(text) from public, anon, authenticated;
revoke all on function public.platform_lwf_try_date(text) from public, anon, authenticated;
revoke all on function public.platform_lwf_resolve_context(jsonb) from public, anon, authenticated;
revoke all on function public.platform_lwf_append_audit(text,text,text,text,text,jsonb,uuid,uuid,bigint) from public, anon, authenticated;
revoke all on function public.platform_lwf_frequency_applies(text,integer[],date,boolean,boolean) from public, anon, authenticated;
revoke all on function public.platform_lwf_resolve_employee_state_internal(text,uuid,date) from public, anon, authenticated;
revoke all on function public.platform_lwf_get_employee_wages_internal(text,uuid,date,text) from public, anon, authenticated;
revoke all on function public.platform_lwf_calculate_contribution_internal(text,uuid,date,boolean) from public, anon, authenticated;
revoke all on function public.platform_lwf_sync_to_payroll_internal(text,uuid,uuid,date,bigint,text,numeric,numeric) from public, anon, authenticated;
revoke all on function public.platform_refresh_lwf_compliance_summary_internal(text,date,text) from public, anon, authenticated;
revoke all on function public.platform_apply_lwf_to_tenant(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_lwf_configuration(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_lwf_wage_component_mapping(jsonb) from public, anon, authenticated;
revoke all on function public.platform_request_lwf_batch(jsonb) from public, anon, authenticated;
revoke all on function public.platform_schedule_lwf_from_payroll(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_lwf_batch_job(jsonb) from public, anon, authenticated;
revoke all on function public.platform_request_lwf_retry_batch(jsonb) from public, anon, authenticated;
revoke all on function public.platform_cancel_lwf_batch(jsonb) from public, anon, authenticated;
revoke all on function public.platform_apply_lwf_override(jsonb) from public, anon, authenticated;
revoke all on function public.platform_remove_lwf_override(jsonb) from public, anon, authenticated;
revoke all on function public.platform_lwf_configuration_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_lwf_batch_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_lwf_contribution_ledger_rows() from public, anon, authenticated;
revoke all on function public.platform_lwf_dead_letter_queue_rows() from public, anon, authenticated;
revoke all on function public.platform_lwf_compliance_summary_rows() from public, anon, authenticated;

grant execute on function public.platform_lwf_module_template_version() to service_role;
grant execute on function public.platform_lwf_resolve_context(jsonb) to service_role;
grant execute on function public.platform_apply_lwf_to_tenant(jsonb) to service_role;
grant execute on function public.platform_upsert_lwf_configuration(jsonb) to service_role;
grant execute on function public.platform_upsert_lwf_wage_component_mapping(jsonb) to service_role;
grant execute on function public.platform_request_lwf_batch(jsonb) to service_role;
grant execute on function public.platform_schedule_lwf_from_payroll(jsonb) to service_role;
grant execute on function public.platform_process_lwf_batch_job(jsonb) to service_role;
grant execute on function public.platform_request_lwf_retry_batch(jsonb) to service_role;
grant execute on function public.platform_cancel_lwf_batch(jsonb) to service_role;
grant execute on function public.platform_apply_lwf_override(jsonb) to service_role;
grant execute on function public.platform_remove_lwf_override(jsonb) to service_role;
grant execute on function public.platform_lwf_configuration_catalog_rows() to service_role;
grant execute on function public.platform_lwf_batch_catalog_rows() to service_role;
grant execute on function public.platform_lwf_contribution_ledger_rows() to service_role;
grant execute on function public.platform_lwf_dead_letter_queue_rows() to service_role;
grant execute on function public.platform_lwf_compliance_summary_rows() to service_role;

grant select on public.platform_rm_lwf_configuration_catalog to service_role;
grant select on public.platform_rm_lwf_batch_catalog to service_role;
grant select on public.platform_rm_lwf_contribution_ledger to service_role;
grant select on public.platform_rm_lwf_dead_letter_queue to service_role;
grant select on public.platform_rm_lwf_compliance_summary to service_role;

do $$
declare
  v_template_version text := public.platform_lwf_module_template_version();
  v_result jsonb;
begin
  v_result := public.platform_register_template_version(jsonb_build_object(
    'template_version', v_template_version,
    'template_scope', 'module',
    'module_code', 'LWF',
    'template_status', 'released',
    'description', 'LWF tenant-owned labour-welfare-fund statutory engine baseline.',
    'metadata', jsonb_build_object('slice', 'LWF', 'module_code', 'LWF')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'LWF template version registration failed: %', v_result::text; end if;

  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'LWF','source_schema_name', 'public','source_table_name', 'wcm_lwf_configuration','target_table_name', 'wcm_lwf_configuration','clone_order', 100,'notes', jsonb_build_object('slice', 'LWF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'LWF configuration table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'LWF','source_schema_name', 'public','source_table_name', 'wcm_lwf_wage_component_mapping','target_table_name', 'wcm_lwf_wage_component_mapping','clone_order', 110,'notes', jsonb_build_object('slice', 'LWF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'LWF mapping table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'LWF','source_schema_name', 'public','source_table_name', 'wcm_lwf_processing_batch','target_table_name', 'wcm_lwf_processing_batch','clone_order', 120,'notes', jsonb_build_object('slice', 'LWF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'LWF batch table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'LWF','source_schema_name', 'public','source_table_name', 'wcm_lwf_period_ledger','target_table_name', 'wcm_lwf_period_ledger','clone_order', 130,'notes', jsonb_build_object('slice', 'LWF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'LWF ledger table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'LWF','source_schema_name', 'public','source_table_name', 'wcm_lwf_dead_letter_entry','target_table_name', 'wcm_lwf_dead_letter_entry','clone_order', 140,'notes', jsonb_build_object('slice', 'LWF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'LWF dead-letter table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'LWF','source_schema_name', 'public','source_table_name', 'wcm_lwf_audit_event','target_table_name', 'wcm_lwf_audit_event','clone_order', 150,'notes', jsonb_build_object('slice', 'LWF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'LWF audit table registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'LWF','source_schema_name', 'public','source_table_name', 'wcm_lwf_compliance_summary','target_table_name', 'wcm_lwf_compliance_summary','clone_order', 160,'notes', jsonb_build_object('slice', 'LWF','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'LWF compliance-summary table registration failed: %', v_result::text; end if;

  v_result := public.platform_register_async_worker(jsonb_build_object(
    'worker_code', 'lwf_period_worker',
    'module_code', 'LWF',
    'dispatch_mode', 'db_inline_handler',
    'handler_contract', 'platform_process_lwf_batch_job',
    'is_active', true,
    'max_batch_size', 4,
    'default_lease_seconds', 600,
    'heartbeat_grace_seconds', 900,
    'retry_backoff_policy', jsonb_build_object('base_seconds', 90, 'multiplier', 2, 'max_seconds', 3600),
    'metadata', jsonb_build_object('slice', 'LWF', 'notes', 'First clean LWF worker on shared F04 spine.')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'LWF period worker registration failed: %', v_result::text; end if;
end;
$$;



;
