do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    create extension pg_net with schema public;
  end if;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    create extension pg_cron with schema pg_catalog;
  end if;
end;
$$;

grant usage on schema cron to postgres, service_role;
grant select, insert, update, delete on all tables in schema cron to postgres, service_role;
grant usage, select on all sequences in schema cron to postgres, service_role;
grant execute on all functions in schema cron to postgres, service_role;

alter table public.platform_plan_catalog
  add column if not exists billing_model text,
  add column if not exists included_employee_count integer,
  add column if not exists pricing_rules jsonb not null default '{}'::jsonb,
  add column if not exists feature_entitlements jsonb not null default '{}'::jsonb;

alter table public.platform_tenant_subscription
  add column if not exists trial_started_at timestamptz,
  add column if not exists trial_ends_at timestamptz,
  add column if not exists grace_until timestamptz,
  add column if not exists wallet_required boolean not null default true;

create table if not exists public.platform_employee_usage_snapshot (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  snapshot_date date not null,
  count_basis_date date not null,
  active_employee_count integer not null,
  free_employee_count integer not null,
  billable_employee_count integer not null,
  meter_method text not null,
  snapshot_payload jsonb not null default '{}'::jsonb,
  snapshot_hash text,
  created_at timestamptz not null default timezone('utc'::text, now()),
  constraint platform_employee_usage_snapshot_tenant_id_snapshot_date_key unique (tenant_id, snapshot_date)
);

create table if not exists public.platform_billing_settlement (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  billing_cycle_id uuid references public.platform_billing_cycle(id) on delete set null,
  period_start date not null,
  period_end date not null,
  measured_peak_users integer not null,
  measured_average_users numeric,
  chargeable_users integer not null,
  unit_rate numeric not null,
  gross_amount numeric not null,
  credit_applied numeric not null default 0,
  tax_payload jsonb not null default '{}'::jsonb,
  final_amount numeric not null,
  settlement_status text not null,
  usage_snapshot_ids jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default timezone('utc'::text, now()),
  settled_at timestamptz,
  constraint platform_billing_settlement_period_unique unique (tenant_id, period_start, period_end),
  constraint platform_billing_settlement_status_check
    check (settlement_status = any (array['draft'::text, 'pending_payment'::text, 'settled'::text, 'cancelled'::text]))
);

create table if not exists public.platform_wallet_balance (
  tenant_id uuid primary key references public.platform_tenant(tenant_id) on delete cascade,
  currency_code text not null default 'INR'::text,
  available_credit numeric not null default 0,
  reserved_credit numeric not null default 0,
  last_settlement_at timestamptz,
  updated_at timestamptz not null default timezone('utc'::text, now())
);

create table if not exists public.platform_wallet_ledger (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  entry_ts timestamptz not null default timezone('utc'::text, now()),
  entry_type text not null,
  direction text not null,
  amount numeric not null,
  currency_code text not null,
  reference_type text not null,
  reference_id text not null,
  balance_after numeric not null,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid,
  constraint platform_wallet_ledger_reference_unique unique (tenant_id, reference_type, reference_id, entry_type),
  constraint platform_wallet_ledger_direction_check
    check (direction = any (array['credit'::text, 'debit'::text])),
  constraint platform_wallet_ledger_amount_check
    check (amount >= 0::numeric)
);

create table if not exists public.platform_payment_order (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  settlement_id uuid references public.platform_billing_settlement(id) on delete set null,
  invoice_id uuid references public.platform_invoice(id) on delete set null,
  provider_code text not null,
  external_order_id text,
  amount numeric not null,
  currency_code text not null,
  status text not null,
  checkout_payload jsonb not null default '{}'::jsonb,
  initiated_by uuid,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  constraint platform_payment_order_status_check
    check (status = any (array['created'::text, 'pending'::text, 'paid'::text, 'failed'::text, 'cancelled'::text, 'expired'::text]))
);

create table if not exists public.platform_payment_event (
  id bigint generated always as identity primary key,
  provider_code text not null,
  external_event_id text not null,
  external_payment_id text,
  tenant_id uuid references public.platform_tenant(tenant_id) on delete set null,
  payment_order_id uuid references public.platform_payment_order(id) on delete set null,
  event_type text not null,
  raw_payload jsonb not null default '{}'::jsonb,
  process_status text not null,
  received_at timestamptz not null default timezone('utc'::text, now()),
  processed_at timestamptz,
  error_details jsonb,
  constraint platform_payment_event_unique unique (provider_code, external_event_id),
  constraint platform_payment_event_process_status_check
    check (process_status = any (array['pending'::text, 'processed'::text, 'failed'::text, 'ignored'::text]))
);

create table if not exists public.platform_feature_gate_cache (
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  gate_code text not null,
  gate_status text not null,
  evaluated_at timestamptz not null default timezone('utc'::text, now()),
  explanation jsonb not null default '{}'::jsonb,
  source_version text,
  primary key (tenant_id, gate_code)
);

alter table public.platform_invoice
  add column if not exists settlement_id uuid references public.platform_billing_settlement(id) on delete set null,
  add column if not exists storage_path text;

create unique index if not exists platform_employee_usage_snapshot_tenant_id_snapshot_date_key
  on public.platform_employee_usage_snapshot using btree (tenant_id, snapshot_date);
create index if not exists platform_employee_usage_snapshot_tenant_snapshot_idx
  on public.platform_employee_usage_snapshot using btree (tenant_id, snapshot_date desc);

create unique index if not exists platform_billing_settlement_period_unique
  on public.platform_billing_settlement using btree (tenant_id, period_start, period_end);
create index if not exists platform_billing_settlement_tenant_period_idx
  on public.platform_billing_settlement using btree (tenant_id, period_end desc, settlement_status);

create index if not exists platform_wallet_ledger_tenant_entry_idx
  on public.platform_wallet_ledger using btree (tenant_id, entry_ts desc);
create unique index if not exists platform_wallet_ledger_reference_unique
  on public.platform_wallet_ledger using btree (tenant_id, reference_type, reference_id, entry_type);

create unique index if not exists platform_payment_order_external_order_unique
  on public.platform_payment_order using btree (provider_code, external_order_id) where (external_order_id is not null);
create index if not exists platform_payment_order_tenant_status_idx
  on public.platform_payment_order using btree (tenant_id, status, created_at desc);

create unique index if not exists platform_payment_event_unique
  on public.platform_payment_event using btree (provider_code, external_event_id);
create index if not exists platform_payment_event_tenant_received_idx
  on public.platform_payment_event using btree (tenant_id, received_at desc);

create index if not exists platform_feature_gate_cache_gate_status_idx
  on public.platform_feature_gate_cache using btree (gate_code, gate_status, evaluated_at desc);

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'platform_wallet_balance_set_updated_at'
      and tgrelid = 'public.platform_wallet_balance'::regclass
  ) then
    create trigger platform_wallet_balance_set_updated_at
      before update on public.platform_wallet_balance
      for each row
      execute function public.platform_set_updated_at();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgname = 'platform_payment_order_set_updated_at'
      and tgrelid = 'public.platform_payment_order'::regclass
  ) then
    create trigger platform_payment_order_set_updated_at
      before update on public.platform_payment_order
      for each row
      execute function public.platform_set_updated_at();
  end if;
end;
$$;

alter table public.platform_employee_usage_snapshot enable row level security;
alter table public.platform_billing_settlement enable row level security;
alter table public.platform_wallet_balance enable row level security;
alter table public.platform_wallet_ledger enable row level security;
alter table public.platform_payment_order enable row level security;
alter table public.platform_payment_event enable row level security;
alter table public.platform_feature_gate_cache enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'platform_employee_usage_snapshot'
      and policyname = 'platform_employee_usage_snapshot_service_role'
  ) then
    create policy platform_employee_usage_snapshot_service_role
      on public.platform_employee_usage_snapshot
      for all
      to service_role
      using (true)
      with check (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'platform_billing_settlement'
      and policyname = 'platform_billing_settlement_service_role'
  ) then
    create policy platform_billing_settlement_service_role
      on public.platform_billing_settlement
      for all
      to service_role
      using (true)
      with check (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'platform_wallet_balance'
      and policyname = 'platform_wallet_balance_service_role'
  ) then
    create policy platform_wallet_balance_service_role
      on public.platform_wallet_balance
      for all
      to service_role
      using (true)
      with check (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'platform_wallet_ledger'
      and policyname = 'platform_wallet_ledger_service_role'
  ) then
    create policy platform_wallet_ledger_service_role
      on public.platform_wallet_ledger
      for all
      to service_role
      using (true)
      with check (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'platform_payment_order'
      and policyname = 'platform_payment_order_service_role'
  ) then
    create policy platform_payment_order_service_role
      on public.platform_payment_order
      for all
      to service_role
      using (true)
      with check (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'platform_payment_event'
      and policyname = 'platform_payment_event_service_role'
  ) then
    create policy platform_payment_event_service_role
      on public.platform_payment_event
      for all
      to service_role
      using (true)
      with check (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'platform_feature_gate_cache'
      and policyname = 'platform_feature_gate_cache_service_role'
  ) then
    create policy platform_feature_gate_cache_service_role
      on public.platform_feature_gate_cache
      for all
      to service_role
      using (true)
      with check (true);
  end if;
end;
$$;

insert into public.platform_wallet_balance (tenant_id, currency_code)
select pts.tenant_id, coalesce(pts.currency_code, 'INR')
from public.platform_tenant_subscription pts
on conflict (tenant_id) do update
set currency_code = excluded.currency_code;

drop view if exists public.platform_rm_tenant_commercial_state;
drop view if exists public.platform_tenant_commercial_state_view;

create view public.platform_tenant_commercial_state_view as
with latest_invoice as (
  select distinct on (pi.tenant_id)
    pi.tenant_id,
    pi.id as latest_invoice_id,
    pi.invoice_no,
    pi.invoice_status,
    pi.issue_date,
    pi.due_date,
    pi.total_amount,
    pi.paid_amount,
    pi.balance_amount,
    pi.settlement_id
  from public.platform_invoice pi
  order by pi.tenant_id, pi.issue_date desc, pi.created_at desc
),
latest_settlement as (
  select distinct on (ps.tenant_id)
    ps.tenant_id,
    ps.id as latest_settlement_id,
    ps.billing_cycle_id as latest_settlement_billing_cycle_id,
    ps.period_start as latest_settlement_period_start,
    ps.period_end as latest_settlement_period_end,
    ps.chargeable_users as latest_settlement_chargeable_users,
    ps.gross_amount as latest_settlement_gross_amount,
    ps.credit_applied as latest_settlement_credit_applied,
    ps.final_amount as latest_settlement_final_amount,
    ps.settlement_status as latest_settlement_status,
    ps.settled_at as latest_settlement_settled_at
  from public.platform_billing_settlement ps
  order by ps.tenant_id, ps.period_end desc, ps.created_at desc
)
select
  pt.tenant_id,
  pt.tenant_code,
  pca.commercial_status,
  pca.dues_state,
  pca.overdue_since,
  pca.dormant_access_from,
  pca.background_stop_from,
  pca.last_invoiced_at,
  pca.last_paid_at,
  pca.last_state_synced_at,
  pts.id as subscription_id,
  pts.subscription_status,
  pts.cycle_anchor_day,
  pts.current_cycle_start,
  pts.current_cycle_end,
  pts.trial_started_at,
  pts.trial_ends_at,
  pts.grace_until,
  pts.wallet_required,
  ppc.id as plan_id,
  ppc.plan_code,
  ppc.plan_name,
  ppc.billing_cadence,
  ppc.billing_model,
  ppc.included_employee_count,
  ppc.currency_code,
  ppc.pricing_rules,
  ppc.feature_entitlements,
  pwb.available_credit,
  pwb.reserved_credit,
  li.latest_invoice_id,
  li.invoice_no as latest_invoice_no,
  li.invoice_status as latest_invoice_status,
  li.issue_date as latest_invoice_issue_date,
  li.due_date as latest_invoice_due_date,
  li.total_amount as latest_invoice_total_amount,
  li.paid_amount as latest_invoice_paid_amount,
  li.balance_amount as latest_invoice_balance_amount,
  li.settlement_id as latest_invoice_settlement_id,
  ls.latest_settlement_id,
  ls.latest_settlement_billing_cycle_id,
  ls.latest_settlement_period_start,
  ls.latest_settlement_period_end,
  ls.latest_settlement_chargeable_users,
  ls.latest_settlement_gross_amount,
  ls.latest_settlement_credit_applied,
  ls.latest_settlement_final_amount,
  ls.latest_settlement_status,
  ls.latest_settlement_settled_at
from public.platform_tenant pt
left join public.platform_tenant_commercial_account pca on pca.tenant_id = pt.tenant_id
left join public.platform_tenant_subscription pts on pts.tenant_id = pt.tenant_id
left join public.platform_plan_catalog ppc on ppc.id = pts.plan_id
left join public.platform_wallet_balance pwb on pwb.tenant_id = pt.tenant_id
left join latest_invoice li on li.tenant_id = pt.tenant_id
left join latest_settlement ls on ls.tenant_id = pt.tenant_id;

create view public.platform_rm_tenant_commercial_state as
select
  tenant_id,
  tenant_code,
  commercial_status,
  dues_state,
  overdue_since,
  dormant_access_from,
  background_stop_from,
  last_invoiced_at,
  last_paid_at,
  last_state_synced_at,
  subscription_id,
  subscription_status,
  cycle_anchor_day,
  current_cycle_start,
  current_cycle_end,
  trial_started_at,
  trial_ends_at,
  grace_until,
  wallet_required,
  plan_id,
  plan_code,
  plan_name,
  billing_cadence,
  billing_model,
  included_employee_count,
  currency_code,
  pricing_rules,
  feature_entitlements,
  available_credit,
  reserved_credit,
  latest_invoice_id,
  latest_invoice_no,
  latest_invoice_status,
  latest_invoice_issue_date,
  latest_invoice_due_date,
  latest_invoice_total_amount,
  latest_invoice_paid_amount,
  latest_invoice_balance_amount,
  latest_invoice_settlement_id,
  latest_settlement_id,
  latest_settlement_billing_cycle_id,
  latest_settlement_period_start,
  latest_settlement_period_end,
  latest_settlement_chargeable_users,
  latest_settlement_gross_amount,
  latest_settlement_credit_applied,
  latest_settlement_final_amount,
  latest_settlement_status,
  latest_settlement_settled_at
from public.platform_tenant_commercial_state_view;
