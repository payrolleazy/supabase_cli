create sequence if not exists public.platform_invoice_no_seq;

create table if not exists public.platform_plan_catalog (
  id uuid primary key default gen_random_uuid(),
  plan_code text not null unique,
  plan_name text not null,
  status text not null default 'active' check (status in ('draft', 'active', 'retired')),
  billing_cadence text not null default 'monthly' check (billing_cadence in ('monthly')),
  currency_code text not null default 'INR',
  description text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.platform_plan_catalog enable row level security;

drop policy if exists platform_plan_catalog_service_role_all on public.platform_plan_catalog;
create policy platform_plan_catalog_service_role_all
on public.platform_plan_catalog
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_plan_catalog_set_updated_at on public.platform_plan_catalog;
create trigger trg_platform_plan_catalog_set_updated_at
before update on public.platform_plan_catalog
for each row
execute function public.platform_set_updated_at();

create table if not exists public.platform_plan_metric_rate (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.platform_plan_catalog(id) on delete cascade,
  metric_code text not null,
  billing_method text not null default 'per_unit' check (billing_method in ('per_unit')),
  unit_price numeric(18,2) not null check (unit_price >= 0),
  currency_code text not null default 'INR',
  effective_from date not null,
  effective_to date null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_plan_metric_rate_effective_window_chk
    check (effective_to is null or effective_to >= effective_from),
  constraint platform_plan_metric_rate_unique unique (plan_id, metric_code, effective_from)
);

create index if not exists idx_platform_plan_metric_rate_lookup
on public.platform_plan_metric_rate (plan_id, metric_code, effective_from desc, effective_to);

alter table public.platform_plan_metric_rate enable row level security;

drop policy if exists platform_plan_metric_rate_service_role_all on public.platform_plan_metric_rate;
create policy platform_plan_metric_rate_service_role_all
on public.platform_plan_metric_rate
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_plan_metric_rate_set_updated_at on public.platform_plan_metric_rate;
create trigger trg_platform_plan_metric_rate_set_updated_at
before update on public.platform_plan_metric_rate
for each row
execute function public.platform_set_updated_at();

create table if not exists public.platform_tenant_commercial_account (
  tenant_id uuid primary key references public.platform_tenant(tenant_id) on delete cascade,
  commercial_status text not null default 'unconfigured' check (commercial_status in ('unconfigured', 'clear', 'dormant_access_blocked', 'dormant_background_blocked', 'disabled', 'terminated')),
  dues_state text not null default 'clear' check (dues_state in ('clear', 'due', 'overdue')),
  overdue_since date null,
  dormant_access_from timestamptz null,
  background_stop_from timestamptz null,
  last_invoiced_at timestamptz null,
  last_paid_at timestamptz null,
  last_state_synced_at timestamptz not null default timezone('utc', now()),
  notes text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.platform_tenant_commercial_account enable row level security;

drop policy if exists platform_tenant_commercial_account_service_role_all on public.platform_tenant_commercial_account;
create policy platform_tenant_commercial_account_service_role_all
on public.platform_tenant_commercial_account
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_tenant_commercial_account_set_updated_at on public.platform_tenant_commercial_account;
create trigger trg_platform_tenant_commercial_account_set_updated_at
before update on public.platform_tenant_commercial_account
for each row
execute function public.platform_set_updated_at();

create table if not exists public.platform_tenant_subscription (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null unique references public.platform_tenant(tenant_id) on delete cascade,
  plan_id uuid not null references public.platform_plan_catalog(id),
  subscription_status text not null default 'active' check (subscription_status in ('active', 'paused', 'cancelled', 'suspended')),
  billing_owner_user_id uuid null,
  currency_code text not null default 'INR',
  cycle_anchor_day integer not null default 1 check (cycle_anchor_day between 1 and 28),
  current_cycle_start date null,
  current_cycle_end date null,
  auto_renew boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_platform_tenant_subscription_plan_id
on public.platform_tenant_subscription (plan_id);

alter table public.platform_tenant_subscription enable row level security;

drop policy if exists platform_tenant_subscription_service_role_all on public.platform_tenant_subscription;
create policy platform_tenant_subscription_service_role_all
on public.platform_tenant_subscription
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_tenant_subscription_set_updated_at on public.platform_tenant_subscription;
create trigger trg_platform_tenant_subscription_set_updated_at
before update on public.platform_tenant_subscription
for each row
execute function public.platform_set_updated_at();;
