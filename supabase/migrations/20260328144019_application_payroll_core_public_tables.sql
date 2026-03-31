set search_path = public, pg_temp;

create table if not exists public.wcm_payroll_area (
  payroll_area_id uuid primary key default gen_random_uuid(),
  area_code text not null,
  area_name text not null,
  payroll_frequency text not null default 'MONTHLY'
    check (payroll_frequency in ('MONTHLY', 'BIWEEKLY', 'WEEKLY')),
  currency_code text not null default 'INR',
  country_code text null,
  area_status text not null default 'ACTIVE'
    check (area_status in ('ACTIVE', 'INACTIVE')),
  area_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_payroll_area_code_check check (btrim(area_code) <> ''),
  constraint wcm_payroll_area_name_check check (btrim(area_name) <> ''),
  constraint wcm_payroll_area_metadata_check check (jsonb_typeof(area_metadata) = 'object')
);
create unique index if not exists uq_wcm_payroll_area_code_lower on public.wcm_payroll_area (lower(area_code));

create table if not exists public.wcm_component (
  component_id bigint generated always as identity primary key,
  component_code text not null,
  component_name text not null,
  component_kind text not null check (component_kind in ('EARNING', 'DEDUCTION', 'EMPLOYER_CONTRIBUTION', 'INFO')),
  calculation_method text not null check (calculation_method in ('FIXED', 'INPUT', 'PERCENTAGE', 'DERIVED', 'FORMULA')),
  payslip_label text null,
  is_taxable boolean not null default false,
  is_proratable boolean not null default false,
  display_order integer not null default 100,
  component_status text not null default 'ACTIVE' check (component_status in ('ACTIVE', 'INACTIVE')),
  default_rule_definition jsonb not null default '{}'::jsonb,
  component_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_component_code_check check (btrim(component_code) <> ''),
  constraint wcm_component_name_check check (btrim(component_name) <> ''),
  constraint wcm_component_display_order_check check (display_order > 0),
  constraint wcm_component_default_rule_definition_check check (jsonb_typeof(default_rule_definition) = 'object'),
  constraint wcm_component_metadata_check check (jsonb_typeof(component_metadata) = 'object')
);
create unique index if not exists uq_wcm_component_code_lower on public.wcm_component (lower(component_code));

create table if not exists public.wcm_component_dependency (
  component_dependency_id bigint generated always as identity primary key,
  component_id bigint not null,
  depends_on_component_id bigint not null,
  dependency_kind text not null default 'REQUIRES' check (dependency_kind in ('REQUIRES', 'SEQUENCE_BEFORE')),
  dependency_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  constraint wcm_component_dependency_self_check check (component_id <> depends_on_component_id),
  constraint wcm_component_dependency_metadata_check check (jsonb_typeof(dependency_metadata) = 'object'),
  constraint wcm_component_dependency_unique unique (component_id, depends_on_component_id)
);
create index if not exists idx_wcm_component_dependency_component on public.wcm_component_dependency (component_id);
create index if not exists idx_wcm_component_dependency_depends_on on public.wcm_component_dependency (depends_on_component_id);

create table if not exists public.wcm_component_rule_template (
  component_rule_template_id uuid primary key default gen_random_uuid(),
  template_code text not null,
  template_name text not null,
  component_id bigint null,
  template_status text not null default 'ACTIVE' check (template_status in ('ACTIVE', 'INACTIVE')),
  rule_definition jsonb not null default '{}'::jsonb,
  template_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_component_rule_template_code_check check (btrim(template_code) <> ''),
  constraint wcm_component_rule_template_name_check check (btrim(template_name) <> ''),
  constraint wcm_component_rule_template_rule_definition_check check (jsonb_typeof(rule_definition) = 'object'),
  constraint wcm_component_rule_template_metadata_check check (jsonb_typeof(template_metadata) = 'object')
);
create unique index if not exists uq_wcm_component_rule_template_code_lower on public.wcm_component_rule_template (lower(template_code));
create index if not exists idx_wcm_component_rule_template_component on public.wcm_component_rule_template (component_id);

create table if not exists public.wcm_pay_structure (
  pay_structure_id uuid primary key default gen_random_uuid(),
  payroll_area_id uuid not null,
  structure_code text not null,
  structure_name text not null,
  structure_status text not null default 'DRAFT' check (structure_status in ('DRAFT', 'ACTIVE', 'INACTIVE', 'RETIRED')),
  active_version_no integer not null default 0,
  effective_from date not null default current_date,
  effective_to date null,
  structure_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_pay_structure_code_check check (btrim(structure_code) <> ''),
  constraint wcm_pay_structure_name_check check (btrim(structure_name) <> ''),
  constraint wcm_pay_structure_window_check check (effective_to is null or effective_to >= effective_from),
  constraint wcm_pay_structure_active_version_no_check check (active_version_no >= 0),
  constraint wcm_pay_structure_metadata_check check (jsonb_typeof(structure_metadata) = 'object')
);
create unique index if not exists uq_wcm_pay_structure_code_lower on public.wcm_pay_structure (lower(structure_code));
create index if not exists idx_wcm_pay_structure_payroll_area on public.wcm_pay_structure (payroll_area_id);

create table if not exists public.wcm_pay_structure_component (
  pay_structure_component_id uuid primary key default gen_random_uuid(),
  pay_structure_id uuid not null,
  component_id bigint not null,
  staged_rule_definition jsonb not null default '{}'::jsonb,
  eligibility_rule_definition jsonb not null default '{}'::jsonb,
  display_order integer not null default 100,
  component_status text not null default 'ACTIVE' check (component_status in ('ACTIVE', 'INACTIVE')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_pay_structure_component_display_order_check check (display_order > 0),
  constraint wcm_pay_structure_component_rule_definition_check check (jsonb_typeof(staged_rule_definition) = 'object'),
  constraint wcm_pay_structure_component_eligibility_definition_check check (jsonb_typeof(eligibility_rule_definition) = 'object'),
  constraint wcm_pay_structure_component_unique unique (pay_structure_id, component_id)
);

create table if not exists public.wcm_pay_structure_version (
  pay_structure_version_id uuid primary key default gen_random_uuid(),
  pay_structure_id uuid not null,
  version_no integer not null,
  version_status text not null default 'DRAFT' check (version_status in ('DRAFT', 'ACTIVE', 'SUPERSEDED', 'RETIRED')),
  version_snapshot jsonb not null default '{}'::jsonb,
  activated_at timestamptz null,
  activated_by_actor_user_id uuid null,
  version_notes text null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_pay_structure_version_no_check check (version_no > 0),
  constraint wcm_pay_structure_version_snapshot_check check (jsonb_typeof(version_snapshot) = 'object'),
  constraint wcm_pay_structure_version_unique unique (pay_structure_id, version_no)
);

create table if not exists public.wcm_employee_pay_structure_assignment (
  employee_pay_structure_assignment_id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  pay_structure_id uuid not null,
  pay_structure_version_id uuid not null,
  effective_from date not null,
  effective_to date null,
  assignment_status text not null default 'ACTIVE' check (assignment_status in ('ACTIVE', 'INACTIVE', 'SUPERSEDED')),
  override_inputs jsonb not null default '{}'::jsonb,
  assigned_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_employee_pay_structure_assignment_window_check check (effective_to is null or effective_to >= effective_from),
  constraint wcm_employee_pay_structure_assignment_override_inputs_check check (jsonb_typeof(override_inputs) = 'object'),
  constraint wcm_employee_pay_structure_assignment_unique unique (employee_id, pay_structure_id, effective_from)
);
create index if not exists idx_wcm_employee_pay_structure_assignment_effective on public.wcm_employee_pay_structure_assignment (employee_id, effective_from desc, employee_pay_structure_assignment_id desc);
create index if not exists idx_wcm_employee_pay_structure_assignment_structure on public.wcm_employee_pay_structure_assignment (pay_structure_id);
create index if not exists idx_wcm_employee_pay_structure_assignment_version on public.wcm_employee_pay_structure_assignment (pay_structure_version_id);

create table if not exists public.wcm_payroll_input_entry (
  payroll_input_entry_id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  payroll_period date not null,
  component_code text not null,
  input_source text not null default 'MANUAL' check (input_source in ('MANUAL', 'TPS', 'STATUTORY', 'FBP', 'FNF', 'PREVIEW_OVERRIDE', 'SYSTEM')),
  source_record_id text not null default '',
  source_batch_id bigint null,
  numeric_value numeric(14,2) null,
  text_value text null,
  json_value jsonb null,
  source_metadata jsonb not null default '{}'::jsonb,
  input_status text not null default 'VALIDATED' check (input_status in ('VALIDATED', 'APPLIED', 'SUPERSEDED', 'REJECTED')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_payroll_input_entry_component_code_check check (btrim(component_code) <> ''),
  constraint wcm_payroll_input_entry_source_metadata_check check (jsonb_typeof(source_metadata) = 'object'),
  constraint wcm_payroll_input_entry_unique unique (employee_id, payroll_period, component_code, input_source, source_record_id)
);
create index if not exists idx_wcm_payroll_input_entry_period_employee on public.wcm_payroll_input_entry (payroll_period desc, employee_id, component_code);
create index if not exists idx_wcm_payroll_input_entry_employee_period on public.wcm_payroll_input_entry (employee_id, payroll_period desc, component_code);

create table if not exists public.wcm_payroll_batch (
  payroll_batch_id uuid primary key default gen_random_uuid(),
  payroll_period date not null,
  payroll_area_id uuid not null,
  processing_type text not null check (processing_type in ('FULL', 'ADHOC', 'CORRECTION', 'PREVIEW_SIMULATION')),
  batch_status text not null default 'DRAFT' check (batch_status in ('DRAFT', 'QUEUED', 'PROCESSING', 'PROCESSED', 'FINALIZED', 'FAILED', 'CANCELLED')),
  request_scope jsonb not null default '{}'::jsonb,
  total_employees integer not null default 0,
  processed_employees integer not null default 0,
  failed_employees integer not null default 0,
  summary_metrics jsonb not null default '{}'::jsonb,
  last_error text null,
  requested_by_actor_user_id uuid null,
  processed_by_actor_user_id uuid null,
  finalized_by_actor_user_id uuid null,
  requested_at timestamptz not null default timezone('utc', now()),
  processed_at timestamptz null,
  finalized_at timestamptz null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_payroll_batch_request_scope_check check (jsonb_typeof(request_scope) = 'object'),
  constraint wcm_payroll_batch_summary_metrics_check check (jsonb_typeof(summary_metrics) = 'object'),
  constraint wcm_payroll_batch_total_employees_check check (total_employees >= 0),
  constraint wcm_payroll_batch_processed_employees_check check (processed_employees >= 0),
  constraint wcm_payroll_batch_failed_employees_check check (failed_employees >= 0)
);
create index if not exists idx_wcm_payroll_batch_period_status on public.wcm_payroll_batch (payroll_period desc, batch_status, processing_type);
create index if not exists idx_wcm_payroll_batch_area on public.wcm_payroll_batch (payroll_area_id);

create table if not exists public.wcm_component_calculation_result (
  calculation_result_id uuid primary key default gen_random_uuid(),
  payroll_batch_id uuid not null,
  employee_id uuid not null,
  payroll_period date not null,
  component_id bigint null,
  component_code text not null,
  component_name text not null,
  component_kind text not null check (component_kind in ('EARNING', 'DEDUCTION', 'EMPLOYER_CONTRIBUTION', 'INFO')),
  calculation_method text not null check (calculation_method in ('FIXED', 'INPUT', 'PERCENTAGE', 'DERIVED', 'FORMULA')),
  display_order integer not null default 100,
  calculated_amount numeric(14,2) not null default 0,
  quantity numeric(14,4) null,
  result_status text not null default 'CALCULATED' check (result_status in ('CALCULATED', 'PREVIEW', 'REVERSED')),
  source_lineage jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_component_calculation_result_source_lineage_check check (jsonb_typeof(source_lineage) = 'object'),
  constraint wcm_component_calculation_result_unique unique (payroll_batch_id, employee_id, component_code)
);
create index if not exists idx_wcm_component_calculation_result_period_employee on public.wcm_component_calculation_result (payroll_period desc, employee_id, payroll_batch_id);
create index if not exists idx_wcm_component_calculation_result_employee on public.wcm_component_calculation_result (employee_id, payroll_period desc, payroll_batch_id);

create table if not exists public.wcm_preview_simulation (
  preview_simulation_id uuid primary key default gen_random_uuid(),
  employee_id uuid not null,
  payroll_period date not null,
  pay_structure_id uuid null,
  source_batch_id uuid null,
  preview_status text not null default 'QUEUED' check (preview_status in ('QUEUED', 'PROCESSING', 'COMPLETED', 'FAILED')),
  request_payload jsonb not null default '{}'::jsonb,
  result_snapshot jsonb not null default '{}'::jsonb,
  requested_by_actor_user_id uuid null,
  completed_at timestamptz null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_preview_simulation_request_payload_check check (jsonb_typeof(request_payload) = 'object'),
  constraint wcm_preview_simulation_result_snapshot_check check (jsonb_typeof(result_snapshot) = 'object')
);
create index if not exists idx_wcm_preview_simulation_employee_period on public.wcm_preview_simulation (employee_id, payroll_period desc, preview_simulation_id desc);
create index if not exists idx_wcm_preview_simulation_structure on public.wcm_preview_simulation (pay_structure_id);
create index if not exists idx_wcm_preview_simulation_source_batch on public.wcm_preview_simulation (source_batch_id);

create table if not exists public.wcm_payslip_run (
  payslip_run_id uuid primary key default gen_random_uuid(),
  payroll_batch_id uuid not null,
  payroll_period date not null,
  run_status text not null default 'QUEUED' check (run_status in ('QUEUED', 'PROCESSING', 'COMPLETED', 'FAILED')),
  requested_by_actor_user_id uuid null,
  completed_at timestamptz null,
  run_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_payslip_run_metadata_check check (jsonb_typeof(run_metadata) = 'object')
);
create index if not exists idx_wcm_payslip_run_period_status on public.wcm_payslip_run (payroll_period desc, run_status, payslip_run_id desc);
create index if not exists idx_wcm_payslip_run_batch on public.wcm_payslip_run (payroll_batch_id);

create table if not exists public.wcm_payslip_item (
  payslip_item_id uuid primary key default gen_random_uuid(),
  payslip_run_id uuid not null,
  payroll_batch_id uuid not null,
  employee_id uuid not null,
  item_status text not null default 'QUEUED' check (item_status in ('QUEUED', 'PROCESSING', 'COMPLETED', 'FAILED', 'DEAD_LETTER')),
  artifact_status text not null default 'PENDING_GENERATION' check (artifact_status in ('PENDING_GENERATION', 'PAYLOAD_READY', 'FAILED')),
  generated_document_id uuid null,
  render_payload jsonb not null default '{}'::jsonb,
  failure_count integer not null default 0,
  last_error text null,
  completed_at timestamptz null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_payslip_item_render_payload_check check (jsonb_typeof(render_payload) = 'object'),
  constraint wcm_payslip_item_failure_count_check check (failure_count >= 0),
  constraint wcm_payslip_item_unique unique (payslip_run_id, employee_id)
);
create index if not exists idx_wcm_payslip_item_status_run on public.wcm_payslip_item (payslip_run_id, item_status, payslip_item_id);
create index if not exists idx_wcm_payslip_item_batch on public.wcm_payslip_item (payroll_batch_id);
create index if not exists idx_wcm_payslip_item_employee on public.wcm_payslip_item (employee_id);

create table if not exists public.wcm_payslip_audit_event (
  payslip_audit_event_id bigint generated always as identity primary key,
  payslip_run_id uuid null,
  payslip_item_id uuid null,
  payroll_batch_id uuid null,
  employee_id uuid null,
  event_type text not null,
  event_source text not null,
  event_details jsonb not null default '{}'::jsonb,
  actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint wcm_payslip_audit_event_type_check check (btrim(event_type) <> ''),
  constraint wcm_payslip_audit_event_source_check check (btrim(event_source) <> ''),
  constraint wcm_payslip_audit_event_details_check check (jsonb_typeof(event_details) = 'object')
);
create index if not exists idx_wcm_payslip_audit_event_run_created on public.wcm_payslip_audit_event (payslip_run_id, created_at desc, payslip_audit_event_id desc);
create index if not exists idx_wcm_payslip_audit_event_item on public.wcm_payslip_audit_event (payslip_item_id);
create index if not exists idx_wcm_payslip_audit_event_batch on public.wcm_payslip_audit_event (payroll_batch_id);
create index if not exists idx_wcm_payslip_audit_event_employee on public.wcm_payslip_audit_event (employee_id);;
