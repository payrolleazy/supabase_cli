set search_path = public, pg_temp;

create table if not exists public.wcm_fbp_benefit (
  benefit_id uuid primary key default gen_random_uuid(),
  benefit_code text not null,
  benefit_name text not null,
  benefit_category text not null default 'REIMBURSEMENT'
    check (benefit_category in ('REIMBURSEMENT', 'ALLOWANCE', 'EXEMPTION', 'OTHER')),
  tax_section text null,
  tax_regime_applicability text not null default 'BOTH'
    check (tax_regime_applicability in ('OLD_ONLY', 'NEW_ONLY', 'BOTH')),
  is_taxable boolean not null default false,
  limit_config jsonb not null default '{}'::jsonb,
  reimbursement_rules jsonb not null default '{}'::jsonb,
  proration_rules jsonb not null default '{}'::jsonb,
  display_config jsonb not null default '{}'::jsonb,
  benefit_status text not null default 'ACTIVE'
    check (benefit_status in ('ACTIVE', 'INACTIVE')),
  effective_from date not null default current_date,
  effective_to date null,
  benefit_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_fbp_benefit_code_check check (btrim(benefit_code) <> ''),
  constraint wcm_fbp_benefit_name_check check (btrim(benefit_name) <> ''),
  constraint wcm_fbp_benefit_limit_config_check check (jsonb_typeof(limit_config) = 'object'),
  constraint wcm_fbp_benefit_reimbursement_rules_check check (jsonb_typeof(reimbursement_rules) = 'object'),
  constraint wcm_fbp_benefit_proration_rules_check check (jsonb_typeof(proration_rules) = 'object'),
  constraint wcm_fbp_benefit_display_config_check check (jsonb_typeof(display_config) = 'object'),
  constraint wcm_fbp_benefit_metadata_check check (jsonb_typeof(benefit_metadata) = 'object'),
  constraint wcm_fbp_benefit_window_check check (effective_to is null or effective_to >= effective_from)
);
create unique index if not exists uq_wcm_fbp_benefit_code_lower on public.wcm_fbp_benefit (lower(benefit_code));

create table if not exists public.wcm_fbp_policy (
  policy_id uuid primary key default gen_random_uuid(),
  policy_code text not null,
  policy_name text not null,
  policy_status text not null default 'DRAFT'
    check (policy_status in ('DRAFT', 'ACTIVE', 'INACTIVE', 'RETIRED')),
  eligibility_rules jsonb not null default '{}'::jsonb,
  total_annual_limit numeric(14,2) not null default 0,
  allow_employee_customization boolean not null default false,
  declaration_mandatory boolean not null default true,
  policy_tax_regime text not null default 'BOTH'
    check (policy_tax_regime in ('OLD_ONLY', 'NEW_ONLY', 'BOTH')),
  version_no integer not null default 1,
  effective_from date not null default current_date,
  effective_to date null,
  policy_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_fbp_policy_code_check check (btrim(policy_code) <> ''),
  constraint wcm_fbp_policy_name_check check (btrim(policy_name) <> ''),
  constraint wcm_fbp_policy_limit_check check (total_annual_limit >= 0),
  constraint wcm_fbp_policy_version_check check (version_no > 0),
  constraint wcm_fbp_policy_eligibility_rules_check check (jsonb_typeof(eligibility_rules) = 'object'),
  constraint wcm_fbp_policy_metadata_check check (jsonb_typeof(policy_metadata) = 'object'),
  constraint wcm_fbp_policy_window_check check (effective_to is null or effective_to >= effective_from)
);
create unique index if not exists uq_wcm_fbp_policy_code_lower on public.wcm_fbp_policy (lower(policy_code));

create table if not exists public.wcm_fbp_policy_benefit (
  policy_benefit_id uuid primary key default gen_random_uuid(),
  policy_id uuid not null,
  benefit_id uuid not null,
  default_annual_limit numeric(14,2) not null default 0,
  is_mandatory boolean not null default false,
  is_default_selected boolean not null default false,
  override_rules jsonb not null default '{}'::jsonb,
  display_order integer not null default 100,
  benefit_status text not null default 'ACTIVE'
    check (benefit_status in ('ACTIVE', 'INACTIVE')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_fbp_policy_benefit_limit_check check (default_annual_limit >= 0),
  constraint wcm_fbp_policy_benefit_override_rules_check check (jsonb_typeof(override_rules) = 'object'),
  constraint wcm_fbp_policy_benefit_display_order_check check (display_order > 0),
  constraint wcm_fbp_policy_benefit_unique unique (policy_id, benefit_id)
);
create index if not exists idx_wcm_fbp_policy_benefit_policy on public.wcm_fbp_policy_benefit (policy_id);
create index if not exists idx_wcm_fbp_policy_benefit_benefit on public.wcm_fbp_policy_benefit (benefit_id);

create table if not exists public.wcm_fbp_employee_assignment (
  employee_assignment_id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  policy_id uuid not null,
  financial_year text not null,
  elected_tax_regime text not null default 'OLD'
    check (elected_tax_regime in ('OLD', 'NEW')),
  total_allocated_amount numeric(14,2) not null default 0,
  effective_start_date date not null,
  effective_end_date date null,
  assignment_status text not null default 'ACTIVE'
    check (assignment_status in ('ACTIVE', 'INACTIVE', 'LOCKED', 'SUPERSEDED')),
  assignment_metadata jsonb not null default '{}'::jsonb,
  created_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_fbp_employee_assignment_year_check check (financial_year ~ '^[0-9]{4}-[0-9]{4}$'),
  constraint wcm_fbp_employee_assignment_total_allocated_check check (total_allocated_amount >= 0),
  constraint wcm_fbp_employee_assignment_metadata_check check (jsonb_typeof(assignment_metadata) = 'object'),
  constraint wcm_fbp_employee_assignment_window_check check (effective_end_date is null or effective_end_date >= effective_start_date),
  constraint wcm_fbp_employee_assignment_unique unique (employee_id, financial_year, effective_start_date)
);
create index if not exists idx_wcm_fbp_employee_assignment_employee_year on public.wcm_fbp_employee_assignment (employee_id, financial_year, effective_start_date desc);
create index if not exists idx_wcm_fbp_employee_assignment_policy on public.wcm_fbp_employee_assignment (policy_id);

create table if not exists public.wcm_fbp_declaration (
  declaration_id uuid primary key default gen_random_uuid(),
  employee_assignment_id uuid not null,
  employee_id uuid not null,
  declaration_code text not null,
  financial_year text not null,
  declaration_type text not null default 'ANNUAL'
    check (declaration_type in ('ANNUAL', 'REVISION')),
  declaration_status text not null default 'DRAFT'
    check (declaration_status in ('DRAFT', 'SUBMITTED', 'HR_REVIEW', 'APPROVED', 'REJECTED', 'LOCKED')),
  total_declared_amount numeric(14,2) not null default 0,
  submitted_at timestamptz null,
  submitted_by_actor_user_id uuid null,
  reviewed_at timestamptz null,
  reviewed_by_actor_user_id uuid null,
  review_comments text null,
  locked_at timestamptz null,
  locked_reason text null,
  declaration_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_fbp_declaration_code_check check (btrim(declaration_code) <> ''),
  constraint wcm_fbp_declaration_year_check check (financial_year ~ '^[0-9]{4}-[0-9]{4}$'),
  constraint wcm_fbp_declaration_total_declared_check check (total_declared_amount >= 0),
  constraint wcm_fbp_declaration_metadata_check check (jsonb_typeof(declaration_metadata) = 'object')
);
create unique index if not exists uq_wcm_fbp_declaration_code_lower on public.wcm_fbp_declaration (lower(declaration_code));
create index if not exists idx_wcm_fbp_declaration_employee_year on public.wcm_fbp_declaration (employee_id, financial_year, created_at desc);
create index if not exists idx_wcm_fbp_declaration_status on public.wcm_fbp_declaration (declaration_status, updated_at desc);

create table if not exists public.wcm_fbp_declaration_item (
  declaration_item_id uuid primary key default gen_random_uuid(),
  declaration_id uuid not null,
  benefit_id uuid not null,
  linked_component_id bigint null,
  declared_annual_amount numeric(14,2) not null default 0,
  declared_monthly_amount numeric(14,2) not null default 0,
  utilized_amount numeric(14,2) not null default 0,
  pending_reimbursement_amount numeric(14,2) not null default 0,
  balance_amount numeric(14,2) not null default 0,
  item_status text not null default 'ACTIVE'
    check (item_status in ('ACTIVE', 'REMOVED', 'LOCKED')),
  item_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_fbp_declaration_item_amounts_check check (declared_annual_amount >= 0 and declared_monthly_amount >= 0 and utilized_amount >= 0 and pending_reimbursement_amount >= 0 and balance_amount >= 0),
  constraint wcm_fbp_declaration_item_metadata_check check (jsonb_typeof(item_metadata) = 'object'),
  constraint wcm_fbp_declaration_item_unique unique (declaration_id, benefit_id)
);
create index if not exists idx_wcm_fbp_declaration_item_declaration on public.wcm_fbp_declaration_item (declaration_id);
create index if not exists idx_wcm_fbp_declaration_item_benefit on public.wcm_fbp_declaration_item (benefit_id);
create index if not exists idx_wcm_fbp_declaration_item_component on public.wcm_fbp_declaration_item (linked_component_id);

create table if not exists public.wcm_fbp_claim (
  claim_id uuid primary key default gen_random_uuid(),
  declaration_item_id uuid not null,
  employee_id uuid not null,
  claim_code text not null,
  financial_year text not null,
  expense_date date not null,
  expense_description text not null,
  merchant_name text null,
  claimed_amount numeric(14,2) not null,
  approved_amount numeric(14,2) not null default 0,
  rejected_amount numeric(14,2) not null default 0,
  claim_status text not null default 'UNDER_REVIEW'
    check (claim_status in ('PENDING_UPLOAD', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'CANCELLED')),
  approver_level_1_actor_user_id uuid null,
  approver_level_1_at timestamptz null,
  approver_level_1_comments text null,
  approver_level_2_actor_user_id uuid null,
  approver_level_2_at timestamptz null,
  approver_level_2_comments text null,
  payment_reference text null,
  claim_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_fbp_claim_code_check check (btrim(claim_code) <> ''),
  constraint wcm_fbp_claim_year_check check (financial_year ~ '^[0-9]{4}-[0-9]{4}$'),
  constraint wcm_fbp_claim_description_check check (btrim(expense_description) <> ''),
  constraint wcm_fbp_claim_amounts_check check (claimed_amount > 0 and approved_amount >= 0 and rejected_amount >= 0),
  constraint wcm_fbp_claim_metadata_check check (jsonb_typeof(claim_metadata) = 'object')
);
create unique index if not exists uq_wcm_fbp_claim_code_lower on public.wcm_fbp_claim (lower(claim_code));
create index if not exists idx_wcm_fbp_claim_employee_status on public.wcm_fbp_claim (employee_id, claim_status, expense_date desc);
create index if not exists idx_wcm_fbp_claim_declaration_item on public.wcm_fbp_claim (declaration_item_id);

create table if not exists public.wcm_fbp_claim_document_binding (
  claim_document_binding_id uuid primary key default gen_random_uuid(),
  claim_id uuid not null,
  document_id uuid not null references public.platform_document_record(document_id) on delete cascade,
  binding_status text not null default 'ACTIVE'
    check (binding_status in ('ACTIVE', 'REMOVED')),
  bound_by_actor_user_id uuid null,
  binding_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_fbp_claim_document_binding_metadata_check check (jsonb_typeof(binding_metadata) = 'object'),
  constraint wcm_fbp_claim_document_binding_unique unique (claim_id, document_id)
);
create index if not exists idx_wcm_fbp_claim_document_binding_claim on public.wcm_fbp_claim_document_binding (claim_id);

create table if not exists public.wcm_fbp_monthly_ledger (
  monthly_ledger_id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  declaration_item_id uuid not null,
  payroll_period date not null,
  financial_year text not null,
  monthly_deduction_amount numeric(14,2) not null default 0,
  reimbursed_amount numeric(14,2) not null default 0,
  is_prorated boolean not null default false,
  proration_factor numeric(8,4) null,
  working_days_in_month integer null,
  actual_working_days integer null,
  payroll_batch_id uuid null,
  ledger_status text not null default 'PROCESSED'
    check (ledger_status in ('PROCESSED', 'REVERSED')),
  processed_at timestamptz null,
  ledger_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_fbp_monthly_ledger_year_check check (financial_year ~ '^[0-9]{4}-[0-9]{4}$'),
  constraint wcm_fbp_monthly_ledger_amounts_check check (monthly_deduction_amount >= 0 and reimbursed_amount >= 0),
  constraint wcm_fbp_monthly_ledger_proration_check check (proration_factor is null or proration_factor >= 0),
  constraint wcm_fbp_monthly_ledger_workdays_check check ((working_days_in_month is null or working_days_in_month >= 0) and (actual_working_days is null or actual_working_days >= 0)),
  constraint wcm_fbp_monthly_ledger_metadata_check check (jsonb_typeof(ledger_metadata) = 'object'),
  constraint wcm_fbp_monthly_ledger_unique unique (declaration_item_id, payroll_period)
);
create index if not exists idx_wcm_fbp_monthly_ledger_employee_period on public.wcm_fbp_monthly_ledger (employee_id, payroll_period desc);
create index if not exists idx_wcm_fbp_monthly_ledger_payroll_batch on public.wcm_fbp_monthly_ledger (payroll_batch_id);

create table if not exists public.wcm_fbp_yearend_settlement (
  yearend_settlement_id uuid primary key default gen_random_uuid(),
  declaration_id uuid not null,
  employee_id uuid not null,
  financial_year text not null,
  total_declared numeric(14,2) not null default 0,
  total_utilized numeric(14,2) not null default 0,
  unutilized_amount numeric(14,2) not null default 0,
  taxable_unutilized_amount numeric(14,2) not null default 0,
  settlement_type text not null
    check (settlement_type in ('LAPSE', 'CARRY_FORWARD', 'CASH_OUT', 'SPECIAL_ALLOWANCE')),
  settlement_status text not null default 'PROCESSED'
    check (settlement_status in ('PENDING', 'PROCESSED', 'REVERSED')),
  processed_in_payroll_period date null,
  processed_in_payroll_batch_id uuid null,
  processed_at timestamptz null,
  settlement_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_fbp_yearend_settlement_year_check check (financial_year ~ '^[0-9]{4}-[0-9]{4}$'),
  constraint wcm_fbp_yearend_settlement_amounts_check check (total_declared >= 0 and total_utilized >= 0 and unutilized_amount >= 0 and taxable_unutilized_amount >= 0),
  constraint wcm_fbp_yearend_settlement_metadata_check check (jsonb_typeof(settlement_metadata) = 'object'),
  constraint wcm_fbp_yearend_settlement_unique unique (declaration_id, settlement_type)
);
create index if not exists idx_wcm_fbp_yearend_settlement_employee_year on public.wcm_fbp_yearend_settlement (employee_id, financial_year);

create table if not exists public.wcm_fbp_audit_event (
  audit_event_id bigint generated always as identity primary key,
  benefit_id uuid null,
  policy_id uuid null,
  employee_assignment_id uuid null,
  declaration_id uuid null,
  claim_id uuid null,
  yearend_settlement_id uuid null,
  event_type text not null,
  event_source text not null,
  event_details jsonb not null default '{}'::jsonb,
  actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint wcm_fbp_audit_event_type_check check (btrim(event_type) <> ''),
  constraint wcm_fbp_audit_event_source_check check (btrim(event_source) <> ''),
  constraint wcm_fbp_audit_event_details_check check (jsonb_typeof(event_details) = 'object')
);
create index if not exists idx_wcm_fbp_audit_event_declaration on public.wcm_fbp_audit_event (declaration_id, created_at desc, audit_event_id desc);
create index if not exists idx_wcm_fbp_audit_event_claim on public.wcm_fbp_audit_event (claim_id, created_at desc, audit_event_id desc);

create or replace function public.platform_fbp_module_template_version()
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select 'fbp_v1'::text;
$function$;

create or replace function public.platform_fbp_try_date(p_value text)
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

create or replace function public.platform_fbp_try_numeric(p_value text)
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

create or replace function public.platform_fbp_financial_year(p_effective_on date)
returns text
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_effective_on date := coalesce(p_effective_on, current_date);
  v_year integer := extract(year from v_effective_on)::integer;
  v_month integer := extract(month from v_effective_on)::integer;
begin
  if v_month >= 4 then
    return format('%s-%s', v_year, v_year + 1);
  end if;
  return format('%s-%s', v_year - 1, v_year);
end;
$function$;

create or replace function public.platform_fbp_regime_matches(p_applicability text, p_selected_regime text)
returns boolean
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select case coalesce(upper(p_applicability), 'BOTH')
    when 'BOTH' then true
    when 'OLD_ONLY' then coalesce(upper(p_selected_regime), 'OLD') = 'OLD'
    when 'NEW_ONLY' then coalesce(upper(p_selected_regime), 'OLD') = 'NEW'
    else false
  end;
$function$;

create or replace function public.platform_fbp_append_audit(
  p_schema_name text,
  p_event_type text,
  p_event_source text,
  p_event_details jsonb,
  p_benefit_id uuid default null,
  p_policy_id uuid default null,
  p_employee_assignment_id uuid default null,
  p_declaration_id uuid default null,
  p_claim_id uuid default null,
  p_yearend_settlement_id uuid default null,
  p_actor_user_id uuid default null
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  execute format(
    'insert into %I.wcm_fbp_audit_event (benefit_id, policy_id, employee_assignment_id, declaration_id, claim_id, yearend_settlement_id, event_type, event_source, event_details, actor_user_id) values ($1,$2,$3,$4,$5,$6,$7,$8,coalesce($9,''{}''::jsonb),$10)',
    p_schema_name
  ) using p_benefit_id, p_policy_id, p_employee_assignment_id, p_declaration_id, p_claim_id, p_yearend_settlement_id, p_event_type, p_event_source, p_event_details, p_actor_user_id;
end;
$function$;
create or replace function public.platform_fbp_resolve_context(p_params jsonb default '{}'::jsonb)
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
      or not public.platform_table_exists(v_current_schema, 'wcm_component')
      or not public.platform_table_exists(v_current_schema, 'wcm_employee_pay_structure_assignment')
      or not public.platform_table_exists(v_current_schema, 'wcm_fbp_benefit')
      or not public.platform_table_exists(v_current_schema, 'wcm_fbp_policy')
      or not public.platform_table_exists(v_current_schema, 'wcm_fbp_policy_benefit')
      or not public.platform_table_exists(v_current_schema, 'wcm_fbp_employee_assignment')
      or not public.platform_table_exists(v_current_schema, 'wcm_fbp_declaration')
      or not public.platform_table_exists(v_current_schema, 'wcm_fbp_declaration_item')
      or not public.platform_table_exists(v_current_schema, 'wcm_fbp_claim')
      or not public.platform_table_exists(v_current_schema, 'wcm_fbp_claim_document_binding')
      or not public.platform_table_exists(v_current_schema, 'wcm_fbp_monthly_ledger')
      or not public.platform_table_exists(v_current_schema, 'wcm_fbp_yearend_settlement')
      or not public.platform_table_exists(v_current_schema, 'wcm_fbp_audit_event')
    then
      return public.platform_json_response(false,'FBP_TEMPLATE_NOT_APPLIED','FBP is not applied to the current tenant schema.',jsonb_build_object('tenant_id', v_current_tenant_id,'tenant_schema', v_current_schema));
    end if;

    return public.platform_json_response(true,'OK','FBP execution context resolved.',jsonb_build_object('tenant_id', v_current_tenant_id,'tenant_schema', v_current_schema,'actor_user_id', public.platform_current_actor_user_id()));
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
    'source', coalesce(nullif(btrim(v_params->>'source'), ''), 'platform_fbp_resolve_context')
  ));
  if coalesce((v_context_result->>'success')::boolean, false) is not true then return v_context_result; end if;

  v_details := coalesce(v_context_result->'details', '{}'::jsonb);
  if not public.platform_table_exists(v_details->>'tenant_schema', 'wcm_fbp_benefit') then
    return public.platform_json_response(false,'FBP_TEMPLATE_NOT_APPLIED','FBP is not applied to the requested tenant schema.',jsonb_build_object('tenant_id', public.platform_try_uuid(v_details->>'tenant_id'),'tenant_schema', v_details->>'tenant_schema'));
  end if;

  return public.platform_json_response(true,'OK','FBP execution context resolved.',jsonb_build_object('tenant_id', public.platform_try_uuid(v_details->>'tenant_id'),'tenant_schema', v_details->>'tenant_schema','actor_user_id', public.platform_current_actor_user_id()));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_fbp_resolve_context.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_fbp_recalculate_item_internal(p_schema_name text, p_declaration_item_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  execute format(
    'update %I.wcm_fbp_declaration_item set balance_amount = greatest(0, declared_annual_amount - utilized_amount - pending_reimbursement_amount), updated_at = timezone(''utc'', now()) where declaration_item_id = $1',
    p_schema_name
  ) using p_declaration_item_id;
end;
$function$;

create or replace function public.platform_fbp_sync_to_payroll_internal(p_schema_name text, p_declaration_id uuid, p_actor_user_id uuid default null)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_employee_id uuid;
  v_assignment_id uuid;
  v_synced_count integer := 0;
  v_override_value jsonb;
  r_item record;
begin
  execute format(
    'select employee_id from %I.wcm_fbp_declaration where declaration_id = $1 and declaration_status = ''APPROVED''',
    p_schema_name
  ) into v_employee_id using p_declaration_id;

  if v_employee_id is null then
    raise exception 'Approved declaration % not found for FBP payroll sync.', p_declaration_id;
  end if;

  execute format(
    'select employee_pay_structure_assignment_id from %I.wcm_employee_pay_structure_assignment where employee_id = $1 and assignment_status = ''ACTIVE'' and effective_from <= current_date and (effective_end_date is null or effective_end_date >= current_date) order by effective_from desc, created_at desc limit 1',
    p_schema_name
  ) into v_assignment_id using v_employee_id;

  if v_assignment_id is null then
    raise exception 'No active payroll assignment found for employee %.', v_employee_id;
  end if;

  for r_item in execute format(
    'select di.declaration_item_id, di.declared_monthly_amount, b.benefit_code from %I.wcm_fbp_declaration_item di join %I.wcm_fbp_benefit b on b.benefit_id = di.benefit_id where di.declaration_id = $1 and di.item_status = ''ACTIVE'' and di.linked_component_id is not null',
    p_schema_name, p_schema_name
  ) using p_declaration_id loop
    v_override_value := jsonb_build_object(
      'calculation', jsonb_build_object('method', 'FLAT_AMOUNT', 'value', r_item.declared_monthly_amount),
      'declaration_item_id', r_item.declaration_item_id,
      'synced_at', timezone('utc', now())
    );

    execute format(
      'update %I.wcm_employee_pay_structure_assignment set override_inputs = jsonb_set(coalesce(override_inputs,''{}''::jsonb), $2, $3, true), updated_at = timezone(''utc'', now()) where employee_pay_structure_assignment_id = $1',
      p_schema_name
    ) using v_assignment_id, array['fbp', lower(r_item.benefit_code)], v_override_value;

    v_synced_count := v_synced_count + 1;
  end loop;

  perform public.platform_fbp_append_audit(p_schema_name,'FBP_SYNCED_TO_PAYROLL','FBP',jsonb_build_object('declaration_id', p_declaration_id,'employee_id', v_employee_id,'synced_components', v_synced_count),null,null,null,p_declaration_id,null,null,p_actor_user_id);
  return v_synced_count;
end;
$function$;

create or replace function public.platform_apply_fbp_to_tenant(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_template_version text := public.platform_fbp_module_template_version();
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
    return public.platform_json_response(false,'TENANT_ID_REQUIRED','tenant_id is required.', '{}'::jsonb);
  end if;

  v_dependency_result := public.platform_apply_payroll_core_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_fbp_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;

  v_apply_result := public.platform_apply_template_version_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'template_version', v_template_version,'source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_apply_fbp_to_tenant')));
  if coalesce((v_apply_result->>'success')::boolean, false) is not true then return v_apply_result; end if;

  v_context := public.platform_fbp_resolve_context(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_fbp_to_tenant'));
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_policy_benefit' and c.conname = 'wcm_fbp_policy_benefit_policy_fk') then
    execute format('alter table %I.wcm_fbp_policy_benefit add constraint wcm_fbp_policy_benefit_policy_fk foreign key (policy_id) references %I.wcm_fbp_policy(policy_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_policy_benefit' and c.conname = 'wcm_fbp_policy_benefit_benefit_fk') then
    execute format('alter table %I.wcm_fbp_policy_benefit add constraint wcm_fbp_policy_benefit_benefit_fk foreign key (benefit_id) references %I.wcm_fbp_benefit(benefit_id) on delete restrict', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_employee_assignment' and c.conname = 'wcm_fbp_employee_assignment_employee_fk') then
    execute format('alter table %I.wcm_fbp_employee_assignment add constraint wcm_fbp_employee_assignment_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_employee_assignment' and c.conname = 'wcm_fbp_employee_assignment_policy_fk') then
    execute format('alter table %I.wcm_fbp_employee_assignment add constraint wcm_fbp_employee_assignment_policy_fk foreign key (policy_id) references %I.wcm_fbp_policy(policy_id) on delete restrict', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_declaration' and c.conname = 'wcm_fbp_declaration_assignment_fk') then
    execute format('alter table %I.wcm_fbp_declaration add constraint wcm_fbp_declaration_assignment_fk foreign key (employee_assignment_id) references %I.wcm_fbp_employee_assignment(employee_assignment_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_declaration' and c.conname = 'wcm_fbp_declaration_employee_fk') then
    execute format('alter table %I.wcm_fbp_declaration add constraint wcm_fbp_declaration_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_declaration_item' and c.conname = 'wcm_fbp_declaration_item_declaration_fk') then
    execute format('alter table %I.wcm_fbp_declaration_item add constraint wcm_fbp_declaration_item_declaration_fk foreign key (declaration_id) references %I.wcm_fbp_declaration(declaration_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_declaration_item' and c.conname = 'wcm_fbp_declaration_item_benefit_fk') then
    execute format('alter table %I.wcm_fbp_declaration_item add constraint wcm_fbp_declaration_item_benefit_fk foreign key (benefit_id) references %I.wcm_fbp_benefit(benefit_id) on delete restrict', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_declaration_item' and c.conname = 'wcm_fbp_declaration_item_component_fk') then
    execute format('alter table %I.wcm_fbp_declaration_item add constraint wcm_fbp_declaration_item_component_fk foreign key (linked_component_id) references %I.wcm_component(component_id) on delete set null', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_claim' and c.conname = 'wcm_fbp_claim_declaration_item_fk') then
    execute format('alter table %I.wcm_fbp_claim add constraint wcm_fbp_claim_declaration_item_fk foreign key (declaration_item_id) references %I.wcm_fbp_declaration_item(declaration_item_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_claim' and c.conname = 'wcm_fbp_claim_employee_fk') then
    execute format('alter table %I.wcm_fbp_claim add constraint wcm_fbp_claim_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_claim_document_binding' and c.conname = 'wcm_fbp_claim_document_binding_claim_fk') then
    execute format('alter table %I.wcm_fbp_claim_document_binding add constraint wcm_fbp_claim_document_binding_claim_fk foreign key (claim_id) references %I.wcm_fbp_claim(claim_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_monthly_ledger' and c.conname = 'wcm_fbp_monthly_ledger_employee_fk') then
    execute format('alter table %I.wcm_fbp_monthly_ledger add constraint wcm_fbp_monthly_ledger_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_monthly_ledger' and c.conname = 'wcm_fbp_monthly_ledger_item_fk') then
    execute format('alter table %I.wcm_fbp_monthly_ledger add constraint wcm_fbp_monthly_ledger_item_fk foreign key (declaration_item_id) references %I.wcm_fbp_declaration_item(declaration_item_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_monthly_ledger' and c.conname = 'wcm_fbp_monthly_ledger_batch_fk') then
    execute format('alter table %I.wcm_fbp_monthly_ledger add constraint wcm_fbp_monthly_ledger_batch_fk foreign key (payroll_batch_id) references %I.wcm_payroll_batch(payroll_batch_id) on delete set null', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_yearend_settlement' and c.conname = 'wcm_fbp_yearend_settlement_declaration_fk') then
    execute format('alter table %I.wcm_fbp_yearend_settlement add constraint wcm_fbp_yearend_settlement_declaration_fk foreign key (declaration_id) references %I.wcm_fbp_declaration(declaration_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_yearend_settlement' and c.conname = 'wcm_fbp_yearend_settlement_employee_fk') then
    execute format('alter table %I.wcm_fbp_yearend_settlement add constraint wcm_fbp_yearend_settlement_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;
  if not exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid join pg_namespace n on n.oid = t.relnamespace where n.nspname = v_schema_name and t.relname = 'wcm_fbp_yearend_settlement' and c.conname = 'wcm_fbp_yearend_settlement_batch_fk') then
    execute format('alter table %I.wcm_fbp_yearend_settlement add constraint wcm_fbp_yearend_settlement_batch_fk foreign key (processed_in_payroll_batch_id) references %I.wcm_payroll_batch(payroll_batch_id) on delete set null', v_schema_name, v_schema_name);
  end if;

  foreach v_table_name in array array['wcm_fbp_benefit','wcm_fbp_policy','wcm_fbp_policy_benefit','wcm_fbp_employee_assignment','wcm_fbp_declaration','wcm_fbp_declaration_item','wcm_fbp_claim','wcm_fbp_claim_document_binding','wcm_fbp_monthly_ledger','wcm_fbp_yearend_settlement','wcm_fbp_audit_event'] loop
    if not public.platform_table_exists(v_schema_name, v_table_name) then
      return public.platform_json_response(false,'FBP_TEMPLATE_APPLY_INCOMPLETE','One or more FBP tables are missing after template apply.',jsonb_build_object('tenant_id', v_tenant_id,'tenant_schema', v_schema_name,'missing_table', v_table_name));
    end if;
  end loop;

  return public.platform_json_response(true,'OK','FBP applied to tenant schema.',jsonb_build_object('tenant_id', v_tenant_id,'tenant_schema', v_schema_name,'template_version', v_template_version));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_apply_fbp_to_tenant.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
