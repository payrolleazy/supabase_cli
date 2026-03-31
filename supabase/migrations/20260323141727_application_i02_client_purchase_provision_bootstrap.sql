create table if not exists public.platform_client_provision_request (
  provision_request_id uuid primary key default gen_random_uuid(),
  request_key text not null unique,
  company_name text not null,
  legal_name text null,
  primary_contact_name text null,
  primary_work_email text not null,
  primary_mobile text null,
  selected_plan_code text not null,
  currency_code text not null default 'INR',
  country_code text null,
  timezone text null,
  request_source text not null default 'public',
  provisioning_status text not null default 'intent_captured'
    check (
      provisioning_status in (
        'intent_captured',
        'awaiting_purchase',
        'checkout_created',
        'payment_pending',
        'payment_failed',
        'payment_cancelled',
        'payment_expired',
        'payment_paid',
        'activation_ready',
        'credential_setup_required',
        'identity_created',
        'tenant_created',
        'owner_role_bound',
        'commercial_seeded',
        'setup_seeded',
        'ready_for_signin',
        'failed'
      )
    ),
  next_action text not null default 'purchase',
  tenant_id uuid null references public.platform_tenant(tenant_id) on delete set null,
  owner_actor_user_id uuid null,
  decision_reason text null,
  provider_customer_ref text null,
  source_ip text null,
  user_agent text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_client_provision_request_request_key_check check (btrim(request_key) <> ''),
  constraint platform_client_provision_request_company_name_check check (btrim(company_name) <> ''),
  constraint platform_client_provision_request_primary_work_email_check check (btrim(primary_work_email) <> ''),
  constraint platform_client_provision_request_selected_plan_code_check check (btrim(selected_plan_code) <> ''),
  constraint platform_client_provision_request_request_source_check check (btrim(request_source) <> ''),
  constraint platform_client_provision_request_metadata_check check (jsonb_typeof(metadata) = 'object')
);

create index if not exists idx_platform_client_provision_request_email_status
on public.platform_client_provision_request (lower(primary_work_email), provisioning_status, created_at desc);

create index if not exists idx_platform_client_provision_request_plan_status
on public.platform_client_provision_request (selected_plan_code, provisioning_status);

create index if not exists idx_platform_client_provision_request_tenant_id
on public.platform_client_provision_request (tenant_id);

create index if not exists idx_platform_client_provision_request_owner_actor
on public.platform_client_provision_request (owner_actor_user_id);

alter table public.platform_client_provision_request enable row level security;
drop policy if exists platform_client_provision_request_service_role_all on public.platform_client_provision_request;
create policy platform_client_provision_request_service_role_all
on public.platform_client_provision_request
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_client_provision_request_set_updated_at on public.platform_client_provision_request;
create trigger trg_platform_client_provision_request_set_updated_at
before update on public.platform_client_provision_request
for each row
execute function public.platform_set_updated_at();

create table if not exists public.platform_client_provision_event (
  event_id bigint generated always as identity primary key,
  provision_request_id uuid not null references public.platform_client_provision_request(provision_request_id) on delete cascade,
  event_type text not null,
  event_status text not null default 'recorded' check (event_status in ('recorded', 'ignored', 'failed')),
  actor_user_id uuid null,
  event_source text not null default 'i02',
  event_message text null,
  event_details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  constraint platform_client_provision_event_event_type_check check (btrim(event_type) <> ''),
  constraint platform_client_provision_event_event_source_check check (btrim(event_source) <> ''),
  constraint platform_client_provision_event_details_check check (jsonb_typeof(event_details) = 'object')
);

create index if not exists idx_platform_client_provision_event_request_created
on public.platform_client_provision_event (provision_request_id, created_at desc, event_id desc);

create index if not exists idx_platform_client_provision_event_type
on public.platform_client_provision_event (event_type, created_at desc);

alter table public.platform_client_provision_event enable row level security;
drop policy if exists platform_client_provision_event_service_role_all on public.platform_client_provision_event;
create policy platform_client_provision_event_service_role_all
on public.platform_client_provision_event
for all
to service_role
using (true)
with check (true);

create table if not exists public.platform_client_purchase_checkout (
  checkout_id uuid primary key default gen_random_uuid(),
  provision_request_id uuid not null references public.platform_client_provision_request(provision_request_id) on delete cascade,
  provider_code text not null default 'manual',
  external_checkout_id text null,
  checkout_status text not null default 'created'
    check (checkout_status in ('created', 'pending', 'paid', 'failed', 'cancelled', 'expired')),
  plan_code text not null,
  currency_code text not null,
  quoted_amount numeric(14,2) not null default 0,
  billing_cadence text null,
  checkout_url text null,
  expires_at timestamptz null,
  resolved_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_client_purchase_checkout_provider_code_check check (btrim(provider_code) <> ''),
  constraint platform_client_purchase_checkout_plan_code_check check (btrim(plan_code) <> ''),
  constraint platform_client_purchase_checkout_currency_code_check check (btrim(currency_code) <> ''),
  constraint platform_client_purchase_checkout_amount_check check (quoted_amount >= 0),
  constraint platform_client_purchase_checkout_metadata_check check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists idx_platform_client_purchase_checkout_external_checkout_id
on public.platform_client_purchase_checkout (provider_code, external_checkout_id)
where external_checkout_id is not null;

create index if not exists idx_platform_client_purchase_checkout_request_created
on public.platform_client_purchase_checkout (provision_request_id, created_at desc);

create index if not exists idx_platform_client_purchase_checkout_status
on public.platform_client_purchase_checkout (checkout_status, created_at desc);

alter table public.platform_client_purchase_checkout enable row level security;
drop policy if exists platform_client_purchase_checkout_service_role_all on public.platform_client_purchase_checkout;
create policy platform_client_purchase_checkout_service_role_all
on public.platform_client_purchase_checkout
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_client_purchase_checkout_set_updated_at on public.platform_client_purchase_checkout;
create trigger trg_platform_client_purchase_checkout_set_updated_at
before update on public.platform_client_purchase_checkout
for each row
execute function public.platform_set_updated_at();

create table if not exists public.platform_client_purchase_event (
  purchase_event_id uuid primary key default gen_random_uuid(),
  provision_request_id uuid not null references public.platform_client_provision_request(provision_request_id) on delete cascade,
  checkout_id uuid not null references public.platform_client_purchase_checkout(checkout_id) on delete cascade,
  provider_code text not null,
  provider_event_id text not null,
  event_type text not null,
  event_status text not null default 'recorded' check (event_status in ('recorded', 'ignored', 'failed')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  constraint platform_client_purchase_event_provider_code_check check (btrim(provider_code) <> ''),
  constraint platform_client_purchase_event_provider_event_id_check check (btrim(provider_event_id) <> ''),
  constraint platform_client_purchase_event_type_check check (btrim(event_type) <> ''),
  constraint platform_client_purchase_event_payload_check check (jsonb_typeof(payload) = 'object')
);

create unique index if not exists idx_platform_client_purchase_event_provider_unique
on public.platform_client_purchase_event (provider_code, provider_event_id);

create index if not exists idx_platform_client_purchase_event_checkout_id
on public.platform_client_purchase_event (checkout_id, created_at desc);

create index if not exists idx_platform_client_purchase_event_request_id
on public.platform_client_purchase_event (provision_request_id, created_at desc);

alter table public.platform_client_purchase_event enable row level security;
drop policy if exists platform_client_purchase_event_service_role_all on public.platform_client_purchase_event;
create policy platform_client_purchase_event_service_role_all
on public.platform_client_purchase_event
for all
to service_role
using (true)
with check (true);

create table if not exists public.platform_owner_bootstrap_token (
  token_id uuid primary key default gen_random_uuid(),
  provision_request_id uuid not null references public.platform_client_provision_request(provision_request_id) on delete cascade,
  token_purpose text not null check (token_purpose in ('purchase_activation', 'credential_setup')),
  token_hash text not null unique,
  token_status text not null default 'issued' check (token_status in ('issued', 'consumed', 'expired', 'revoked')),
  issued_for_email text null,
  expires_at timestamptz not null,
  consumed_at timestamptz null,
  consumed_by_user_id uuid null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_owner_bootstrap_token_hash_check check (btrim(token_hash) <> ''),
  constraint platform_owner_bootstrap_token_metadata_check check (jsonb_typeof(metadata) = 'object')
);

create index if not exists idx_platform_owner_bootstrap_token_request_purpose
on public.platform_owner_bootstrap_token (provision_request_id, token_purpose, created_at desc);

create index if not exists idx_platform_owner_bootstrap_token_status
on public.platform_owner_bootstrap_token (token_status, expires_at);

alter table public.platform_owner_bootstrap_token enable row level security;
drop policy if exists platform_owner_bootstrap_token_service_role_all on public.platform_owner_bootstrap_token;
create policy platform_owner_bootstrap_token_service_role_all
on public.platform_owner_bootstrap_token
for all
to service_role
using (true)
with check (true);

drop trigger if exists trg_platform_owner_bootstrap_token_set_updated_at on public.platform_owner_bootstrap_token;
create trigger trg_platform_owner_bootstrap_token_set_updated_at
before update on public.platform_owner_bootstrap_token
for each row
execute function public.platform_set_updated_at();

insert into public.platform_access_role (role_code, role_scope, role_status, description, metadata)
values (
  'tenant_owner_admin',
  'tenant',
  'active',
  'Tenant owner administrator role seeded by I02.',
  jsonb_build_object('source', 'i02', 'slice', 'I02_CLIENT_PURCHASE_PROVISION_BOOTSTRAP')
)
on conflict (role_code) do update
set role_scope = excluded.role_scope,
    role_status = excluded.role_status,
    description = excluded.description,
    metadata = excluded.metadata,
    updated_at = timezone('utc', now());

create or replace view public.platform_rm_client_provision_state as
select
  r.provision_request_id,
  r.request_key,
  r.company_name,
  r.legal_name,
  r.primary_contact_name,
  r.primary_work_email,
  r.primary_mobile,
  r.selected_plan_code,
  r.currency_code,
  r.country_code,
  r.timezone,
  r.request_source,
  r.provisioning_status,
  r.next_action,
  r.tenant_id,
  t.tenant_code,
  t.schema_name,
  r.owner_actor_user_id,
  c.checkout_id as latest_checkout_id,
  c.provider_code as latest_checkout_provider_code,
  c.external_checkout_id as latest_external_checkout_id,
  c.checkout_status as latest_checkout_status,
  c.quoted_amount as latest_checkout_amount,
  c.currency_code as latest_checkout_currency_code,
  c.checkout_url as latest_checkout_url,
  c.expires_at as latest_checkout_expires_at,
  pe.event_type as last_provision_event_type,
  pe.event_status as last_provision_event_status,
  pe.created_at as last_provision_event_at,
  (
    select count(*)
    from public.platform_client_provision_event e2
    where e2.provision_request_id = r.provision_request_id
  ) as provision_event_count,
  (
    select count(*)
    from public.platform_client_purchase_event p2
    where p2.provision_request_id = r.provision_request_id
  ) as purchase_event_count,
  r.created_at,
  r.updated_at
from public.platform_client_provision_request r
left join public.platform_tenant t
  on t.tenant_id = r.tenant_id
left join lateral (
  select c1.*
  from public.platform_client_purchase_checkout c1
  where c1.provision_request_id = r.provision_request_id
  order by c1.created_at desc, c1.checkout_id desc
  limit 1
) c on true
left join lateral (
  select e1.*
  from public.platform_client_provision_event e1
  where e1.provision_request_id = r.provision_request_id
  order by e1.created_at desc, e1.event_id desc
  limit 1
) pe on true;

create or replace function public.platform_i02_hash_token(p_token text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
$function$;

create or replace function public.platform_i02_generate_tenant_code(p_company_name text, p_provision_request_id uuid)
returns text
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_base_code text := public.platform_normalize_tenant_code(p_company_name);
  v_suffix text := substr(replace(coalesce(p_provision_request_id::text, gen_random_uuid()::text), '-', ''), 1, 6);
  v_candidate text;
begin
  if v_base_code is null or v_base_code = '' then
    v_base_code := 'client';
  end if;

  v_candidate := v_base_code;
  if exists (
    select 1
    from public.platform_tenant pt
    where pt.tenant_code = v_candidate
  ) then
    v_candidate := public.platform_normalize_tenant_code(v_base_code || '-' || v_suffix);
  end if;

  return v_candidate;
end;
$function$;

create or replace function public.platform_i02_latest_foundation_template_version()
returns text
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  select ptv.template_version
  from public.platform_template_version ptv
  where ptv.template_scope = 'foundation'
    and ptv.template_status = 'released'
  order by ptv.released_at desc nulls last, ptv.created_at desc
  limit 1;
$function$;

create or replace function public.platform_i02_resolve_provision_request_id(p_params jsonb)
returns uuid
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_id uuid := public.platform_try_uuid(p_params->>'provision_request_id');
  v_request_key text := lower(btrim(coalesce(p_params->>'request_key', '')));
  v_checkout_id uuid := public.platform_try_uuid(p_params->>'checkout_id');
begin
  if v_request_id is not null then
    return v_request_id;
  end if;

  if v_request_key <> '' then
    select r.provision_request_id
    into v_request_id
    from public.platform_client_provision_request r
    where r.request_key = v_request_key
    limit 1;
    return v_request_id;
  end if;

  if v_checkout_id is not null then
    select c.provision_request_id
    into v_request_id
    from public.platform_client_purchase_checkout c
    where c.checkout_id = v_checkout_id
    limit 1;
    return v_request_id;
  end if;

  return null;
end;
$function$;

create or replace function public.platform_i02_append_provision_event(p_params jsonb)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_id uuid := public.platform_try_uuid(p_params->>'provision_request_id');
begin
  if v_request_id is null then
    raise exception 'platform_i02_append_provision_event requires provision_request_id';
  end if;

  insert into public.platform_client_provision_event (
    provision_request_id,
    event_type,
    event_status,
    actor_user_id,
    event_source,
    event_message,
    event_details
  )
  values (
    v_request_id,
    lower(btrim(coalesce(p_params->>'event_type', 'i02_event'))),
    lower(coalesce(nullif(btrim(p_params->>'event_status'), ''), 'recorded')),
    coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_resolve_actor()),
    coalesce(nullif(btrim(p_params->>'event_source'), ''), 'i02'),
    nullif(btrim(coalesce(p_params->>'event_message', '')), ''),
    coalesce(p_params->'event_details', '{}'::jsonb)
  );
end;
$function$;

create or replace function public.platform_capture_client_provision_intent(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_key text := lower(btrim(coalesce(p_params->>'request_key', '')));
  v_company_name text := nullif(btrim(coalesce(p_params->>'company_name', '')), '');
  v_legal_name text := nullif(btrim(coalesce(p_params->>'legal_name', '')), '');
  v_contact_name text := nullif(btrim(coalesce(p_params->>'primary_contact_name', '')), '');
  v_email text := nullif(lower(btrim(coalesce(p_params->>'primary_work_email', ''))), '');
  v_mobile text := nullif(btrim(coalesce(p_params->>'primary_mobile', '')), '');
  v_selected_plan_code text := lower(btrim(coalesce(p_params->>'selected_plan_code', '')));
  v_currency_code text := upper(coalesce(nullif(btrim(p_params->>'currency_code'), ''), 'INR'));
  v_country_code text := upper(nullif(btrim(coalesce(p_params->>'country_code', '')), ''));
  v_timezone text := coalesce(nullif(btrim(p_params->>'timezone'), ''), 'Asia/Kolkata');
  v_request_source text := lower(coalesce(nullif(btrim(p_params->>'request_source'), ''), 'public'));
  v_source_ip text := nullif(btrim(coalesce(p_params->>'source_ip', '')), '');
  v_user_agent text := nullif(btrim(coalesce(p_params->>'user_agent', '')), '');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_request public.platform_client_provision_request%rowtype;
begin
  if v_request_key = '' then
    return public.platform_json_response(false, 'REQUEST_KEY_REQUIRED', 'request_key is required.', '{}'::jsonb);
  end if;
  if v_company_name is null then
    return public.platform_json_response(false, 'COMPANY_NAME_REQUIRED', 'company_name is required.', '{}'::jsonb);
  end if;
  if v_email is null then
    return public.platform_json_response(false, 'PRIMARY_WORK_EMAIL_REQUIRED', 'primary_work_email is required.', '{}'::jsonb);
  end if;
  if v_selected_plan_code = '' then
    return public.platform_json_response(false, 'SELECTED_PLAN_CODE_REQUIRED', 'selected_plan_code is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  if not exists (
    select 1
    from public.platform_plan_catalog pc
    where pc.plan_code = v_selected_plan_code
      and pc.status = 'active'
  ) then
    return public.platform_json_response(false, 'PLAN_NOT_FOUND', 'Active plan not found.', jsonb_build_object('plan_code', v_selected_plan_code));
  end if;

  select *
  into v_request
  from public.platform_client_provision_request
  where request_key = v_request_key
  limit 1;

  if found then
    return public.platform_json_response(
      true,
      'OK',
      'Provision request already exists for this request_key.',
      jsonb_build_object(
        'provision_request_id', v_request.provision_request_id,
        'request_key', v_request.request_key,
        'provisioning_status', v_request.provisioning_status,
        'next_action', v_request.next_action,
        'idempotent_replay', true
      )
    );
  end if;

  select *
  into v_request
  from public.platform_client_provision_request
  where lower(primary_work_email) = v_email
    and provisioning_status not in ('payment_failed', 'payment_cancelled', 'payment_expired', 'failed', 'ready_for_signin')
  order by created_at desc
  limit 1;

  if found then
    return public.platform_json_response(
      true,
      'OK',
      'Active provisioning request already exists for this email.',
      jsonb_build_object(
        'provision_request_id', v_request.provision_request_id,
        'request_key', v_request.request_key,
        'provisioning_status', v_request.provisioning_status,
        'next_action', v_request.next_action,
        'idempotent_replay', true
      )
    );
  end if;

  insert into public.platform_client_provision_request (
    request_key,
    company_name,
    legal_name,
    primary_contact_name,
    primary_work_email,
    primary_mobile,
    selected_plan_code,
    currency_code,
    country_code,
    timezone,
    request_source,
    provisioning_status,
    next_action,
    source_ip,
    user_agent,
    metadata
  )
  values (
    v_request_key,
    v_company_name,
    v_legal_name,
    v_contact_name,
    v_email,
    v_mobile,
    v_selected_plan_code,
    v_currency_code,
    v_country_code,
    v_timezone,
    v_request_source,
    'awaiting_purchase',
    'purchase',
    v_source_ip,
    v_user_agent,
    v_metadata
  )
  returning *
  into v_request;

  perform public.platform_i02_append_provision_event(jsonb_build_object(
    'provision_request_id', v_request.provision_request_id,
    'event_type', 'intent_captured',
    'event_source', 'platform_capture_client_provision_intent',
    'event_message', 'Public client provisioning intent captured.',
    'event_details', jsonb_build_object(
      'selected_plan_code', v_selected_plan_code,
      'request_source', v_request_source
    )
  ));

  return public.platform_json_response(
    true,
    'OK',
    'Provision request captured.',
    jsonb_build_object(
      'provision_request_id', v_request.provision_request_id,
      'request_key', v_request.request_key,
      'provisioning_status', v_request.provisioning_status,
      'next_action', v_request.next_action
    )
  );
end;
$function$;

create or replace function public.platform_get_client_provision_state(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_id uuid := public.platform_i02_resolve_provision_request_id(p_params);
  v_state record;
begin
  if v_request_id is null then
    return public.platform_json_response(false, 'PROVISION_REQUEST_ID_REQUIRED', 'provision_request_id or request_key is required.', '{}'::jsonb);
  end if;

  select *
  into v_state
  from public.platform_rm_client_provision_state
  where provision_request_id = v_request_id;

  if not found then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_FOUND', 'Provision request not found.', jsonb_build_object('provision_request_id', v_request_id));
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'Provision request state resolved.',
    to_jsonb(v_state)
  );
end;
$function$;

create or replace function public.platform_create_or_resume_public_checkout(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_id uuid := public.platform_i02_resolve_provision_request_id(p_params);
  v_provider_code text := lower(coalesce(nullif(btrim(p_params->>'provider_code'), ''), 'manual'));
  v_external_checkout_id text := nullif(btrim(coalesce(p_params->>'external_checkout_id', '')), '');
  v_checkout_url text := nullif(btrim(coalesce(p_params->>'checkout_url', '')), '');
  v_quoted_amount numeric(14,2) := coalesce(nullif(p_params->>'quoted_amount', '')::numeric, 0);
  v_expires_at timestamptz := nullif(p_params->>'expires_at', '')::timestamptz;
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_request public.platform_client_provision_request%rowtype;
  v_checkout public.platform_client_purchase_checkout%rowtype;
  v_plan public.platform_plan_catalog%rowtype;
  v_request_status text;
  v_next_action text;
begin
  if v_request_id is null then
    return public.platform_json_response(false, 'PROVISION_REQUEST_ID_REQUIRED', 'provision_request_id or request_key is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  select *
  into v_request
  from public.platform_client_provision_request
  where provision_request_id = v_request_id
  for update;

  if not found then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_FOUND', 'Provision request not found.', jsonb_build_object('provision_request_id', v_request_id));
  end if;

  if v_request.provisioning_status in ('ready_for_signin', 'failed') then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_CHECKOUT_ELIGIBLE', 'Provision request is not eligible for checkout.', jsonb_build_object('provisioning_status', v_request.provisioning_status));
  end if;

  select *
  into v_plan
  from public.platform_plan_catalog
  where plan_code = v_request.selected_plan_code
    and status = 'active';

  if not found then
    return public.platform_json_response(false, 'PLAN_NOT_FOUND', 'Active plan not found.', jsonb_build_object('plan_code', v_request.selected_plan_code));
  end if;

  select *
  into v_checkout
  from public.platform_client_purchase_checkout
  where provision_request_id = v_request_id
    and checkout_status in ('created', 'pending', 'paid')
  order by created_at desc
  limit 1;

  if found then
    return public.platform_json_response(
      true,
      'OK',
      'Provision checkout already exists.',
      jsonb_build_object(
        'checkout_id', v_checkout.checkout_id,
        'provision_request_id', v_request_id,
        'checkout_status', v_checkout.checkout_status,
        'next_action', case when v_checkout.checkout_status = 'paid' then 'purchase_activation' else 'await_payment' end,
        'idempotent_replay', true
      )
    );
  end if;

  if v_quoted_amount <= 0 then
    v_request_status := 'activation_ready';
    v_next_action := 'purchase_activation';
  else
    v_request_status := 'payment_pending';
    v_next_action := 'await_payment';
  end if;

  insert into public.platform_client_purchase_checkout (
    provision_request_id,
    provider_code,
    external_checkout_id,
    checkout_status,
    plan_code,
    currency_code,
    quoted_amount,
    billing_cadence,
    checkout_url,
    expires_at,
    resolved_at,
    metadata
  )
  values (
    v_request_id,
    v_provider_code,
    v_external_checkout_id,
    case when v_quoted_amount <= 0 then 'paid' else 'pending' end,
    v_request.selected_plan_code,
    coalesce(nullif(v_request.currency_code, ''), v_plan.currency_code),
    v_quoted_amount,
    v_plan.billing_cadence,
    v_checkout_url,
    v_expires_at,
    case when v_quoted_amount <= 0 then timezone('utc', now()) else null end,
    v_metadata
  )
  returning *
  into v_checkout;

  update public.platform_client_provision_request
  set provisioning_status = v_request_status,
      next_action = v_next_action,
      updated_at = timezone('utc', now())
  where provision_request_id = v_request_id;

  perform public.platform_i02_append_provision_event(jsonb_build_object(
    'provision_request_id', v_request_id,
    'event_type', case when v_quoted_amount <= 0 then 'checkout_completed_free_plan' else 'checkout_created' end,
    'event_source', 'platform_create_or_resume_public_checkout',
    'event_message', 'Public checkout created or resumed.',
    'event_details', jsonb_build_object(
      'checkout_id', v_checkout.checkout_id,
      'provider_code', v_provider_code,
      'checkout_status', v_checkout.checkout_status,
      'quoted_amount', v_quoted_amount
    )
  ));

  return public.platform_json_response(
    true,
    'OK',
    'Public checkout created.',
    jsonb_build_object(
      'checkout_id', v_checkout.checkout_id,
      'provision_request_id', v_request_id,
      'checkout_status', v_checkout.checkout_status,
      'quoted_amount', v_checkout.quoted_amount,
      'currency_code', v_checkout.currency_code,
      'checkout_url', v_checkout.checkout_url,
      'next_action', v_next_action
    )
  );
end;
$function$;

create or replace function public.platform_attach_public_checkout(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_checkout_id uuid := public.platform_try_uuid(p_params->>'checkout_id');
  v_request_id uuid := public.platform_i02_resolve_provision_request_id(p_params);
  v_external_checkout_id text := nullif(btrim(coalesce(p_params->>'external_checkout_id', '')), '');
  v_checkout_url text := nullif(btrim(coalesce(p_params->>'checkout_url', '')), '');
  v_expires_at timestamptz := nullif(p_params->>'expires_at', '')::timestamptz;
  v_metadata_patch jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_checkout public.platform_client_purchase_checkout%rowtype;
begin
  if jsonb_typeof(v_metadata_patch) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  if v_checkout_id is null and v_request_id is null then
    return public.platform_json_response(false, 'CHECKOUT_REFERENCE_REQUIRED', 'checkout_id or provision_request_id is required.', '{}'::jsonb);
  end if;

  if v_checkout_id is null then
    select *
    into v_checkout
    from public.platform_client_purchase_checkout
    where provision_request_id = v_request_id
    order by created_at desc
    limit 1
    for update;
  else
    select *
    into v_checkout
    from public.platform_client_purchase_checkout
    where checkout_id = v_checkout_id
    for update;
  end if;

  if not found then
    return public.platform_json_response(false, 'CHECKOUT_NOT_FOUND', 'Checkout not found.', jsonb_build_object('checkout_id', v_checkout_id, 'provision_request_id', v_request_id));
  end if;

  update public.platform_client_purchase_checkout
  set external_checkout_id = coalesce(v_external_checkout_id, external_checkout_id),
      checkout_url = coalesce(v_checkout_url, checkout_url),
      expires_at = coalesce(v_expires_at, expires_at),
      metadata = metadata || v_metadata_patch,
      updated_at = timezone('utc', now())
  where checkout_id = v_checkout.checkout_id
  returning *
  into v_checkout;

  perform public.platform_i02_append_provision_event(jsonb_build_object(
    'provision_request_id', v_checkout.provision_request_id,
    'event_type', 'checkout_attached',
    'event_source', 'platform_attach_public_checkout',
    'event_message', 'Checkout attachment data updated.',
    'event_details', jsonb_build_object(
      'checkout_id', v_checkout.checkout_id,
      'external_checkout_id', v_checkout.external_checkout_id
    )
  ));

  return public.platform_json_response(
    true,
    'OK',
    'Checkout attachment updated.',
    jsonb_build_object(
      'checkout_id', v_checkout.checkout_id,
      'provision_request_id', v_checkout.provision_request_id,
      'external_checkout_id', v_checkout.external_checkout_id
    )
  );
end;
$function$;

create or replace function public.platform_record_public_checkout_event(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_checkout_id uuid := public.platform_try_uuid(p_params->>'checkout_id');
  v_provider_code text := lower(coalesce(nullif(btrim(p_params->>'provider_code'), ''), 'manual'));
  v_external_checkout_id text := nullif(btrim(coalesce(p_params->>'external_checkout_id', '')), '');
  v_provider_event_id text := nullif(btrim(coalesce(p_params->>'provider_event_id', '')), '');
  v_event_type text := lower(coalesce(nullif(btrim(p_params->>'event_type'), ''), 'provider_event'));
  v_resolved_status text := lower(coalesce(
    nullif(btrim(p_params->>'resolved_status'), ''),
    case
      when v_event_type in ('checkout_paid', 'payment_paid', 'checkout.session.completed') then 'paid'
      when v_event_type in ('checkout_failed', 'payment_failed', 'payment.failed') then 'failed'
      when v_event_type in ('checkout_cancelled', 'payment_cancelled', 'checkout.session.cancelled') then 'cancelled'
      when v_event_type in ('checkout_expired', 'payment_expired', 'checkout.session.expired') then 'expired'
      else 'pending'
    end
  ));
  v_payload jsonb := coalesce(p_params->'payload', '{}'::jsonb);
  v_checkout public.platform_client_purchase_checkout%rowtype;
  v_request_status text;
  v_next_action text;
  v_purchase_event_id uuid;
begin
  if v_provider_event_id is null then
    return public.platform_json_response(false, 'PROVIDER_EVENT_ID_REQUIRED', 'provider_event_id is required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_payload) <> 'object' then
    return public.platform_json_response(false, 'INVALID_PAYLOAD', 'payload must be a JSON object.', '{}'::jsonb);
  end if;

  if v_checkout_id is null then
    if v_external_checkout_id is null then
      return public.platform_json_response(false, 'CHECKOUT_REFERENCE_REQUIRED', 'checkout_id or external_checkout_id is required.', '{}'::jsonb);
    end if;

    select *
    into v_checkout
    from public.platform_client_purchase_checkout
    where provider_code = v_provider_code
      and external_checkout_id = v_external_checkout_id
    for update;
  else
    select *
    into v_checkout
    from public.platform_client_purchase_checkout
    where checkout_id = v_checkout_id
    for update;
  end if;

  if not found then
    return public.platform_json_response(false, 'CHECKOUT_NOT_FOUND', 'Checkout not found for provider event.', jsonb_build_object('checkout_id', v_checkout_id, 'external_checkout_id', v_external_checkout_id));
  end if;

  insert into public.platform_client_purchase_event (
    provision_request_id,
    checkout_id,
    provider_code,
    provider_event_id,
    event_type,
    event_status,
    payload
  )
  values (
    v_checkout.provision_request_id,
    v_checkout.checkout_id,
    v_provider_code,
    v_provider_event_id,
    v_event_type,
    'recorded',
    v_payload
  )
  on conflict (provider_code, provider_event_id) do nothing
  returning purchase_event_id
  into v_purchase_event_id;

  if v_purchase_event_id is null then
    return public.platform_json_response(
      true,
      'OK',
      'Provider event already recorded.',
      jsonb_build_object(
        'checkout_id', v_checkout.checkout_id,
        'provision_request_id', v_checkout.provision_request_id,
        'provider_event_id', v_provider_event_id,
        'idempotent_replay', true
      )
    );
  end if;

  update public.platform_client_purchase_checkout
  set checkout_status = case
        when v_resolved_status in ('paid', 'failed', 'cancelled', 'expired') then v_resolved_status
        else checkout_status
      end,
      resolved_at = case
        when v_resolved_status in ('paid', 'failed', 'cancelled', 'expired') then timezone('utc', now())
        else resolved_at
      end,
      metadata = metadata || jsonb_build_object('last_provider_event_id', v_provider_event_id, 'last_event_type', v_event_type),
      updated_at = timezone('utc', now())
  where checkout_id = v_checkout.checkout_id
  returning *
  into v_checkout;

  v_request_status := case v_resolved_status
    when 'paid' then 'activation_ready'
    when 'failed' then 'payment_failed'
    when 'cancelled' then 'payment_cancelled'
    when 'expired' then 'payment_expired'
    else 'payment_pending'
  end;

  v_next_action := case v_resolved_status
    when 'paid' then 'purchase_activation'
    when 'failed' then 'retry_purchase'
    when 'cancelled' then 'retry_purchase'
    when 'expired' then 'retry_purchase'
    else 'await_payment'
  end;

  update public.platform_client_provision_request
  set provisioning_status = v_request_status,
      next_action = v_next_action,
      updated_at = timezone('utc', now())
  where provision_request_id = v_checkout.provision_request_id;

  perform public.platform_i02_append_provision_event(jsonb_build_object(
    'provision_request_id', v_checkout.provision_request_id,
    'event_type', 'checkout_' || v_resolved_status,
    'event_source', 'platform_record_public_checkout_event',
    'event_message', 'Provider checkout event recorded.',
    'event_details', jsonb_build_object(
      'checkout_id', v_checkout.checkout_id,
      'provider_event_id', v_provider_event_id,
      'event_type', v_event_type,
      'resolved_status', v_resolved_status
    )
  ));

  return public.platform_json_response(
    true,
    'OK',
    'Provider checkout event recorded.',
    jsonb_build_object(
      'purchase_event_id', v_purchase_event_id,
      'checkout_id', v_checkout.checkout_id,
      'provision_request_id', v_checkout.provision_request_id,
      'checkout_status', v_checkout.checkout_status,
      'provisioning_status', v_request_status,
      'next_action', v_next_action
    )
  );
end;
$function$;

create or replace function public.platform_resolve_public_checkout(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_id uuid := public.platform_i02_resolve_provision_request_id(p_params);
  v_checkout public.platform_client_purchase_checkout%rowtype;
  v_request public.platform_client_provision_request%rowtype;
  v_request_status text;
  v_next_action text;
begin
  if v_request_id is null then
    return public.platform_json_response(false, 'PROVISION_REQUEST_ID_REQUIRED', 'provision_request_id, request_key, or checkout_id is required.', '{}'::jsonb);
  end if;

  select *
  into v_request
  from public.platform_client_provision_request
  where provision_request_id = v_request_id
  for update;

  if not found then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_FOUND', 'Provision request not found.', jsonb_build_object('provision_request_id', v_request_id));
  end if;

  select *
  into v_checkout
  from public.platform_client_purchase_checkout
  where provision_request_id = v_request_id
  order by created_at desc
  limit 1;

  if not found then
    return public.platform_json_response(false, 'CHECKOUT_NOT_FOUND', 'Checkout not found for provision request.', jsonb_build_object('provision_request_id', v_request_id));
  end if;

  v_request_status := case v_checkout.checkout_status
    when 'paid' then 'activation_ready'
    when 'failed' then 'payment_failed'
    when 'cancelled' then 'payment_cancelled'
    when 'expired' then 'payment_expired'
    when 'created' then 'checkout_created'
    else 'payment_pending'
  end;

  v_next_action := case v_checkout.checkout_status
    when 'paid' then 'purchase_activation'
    when 'failed' then 'retry_purchase'
    when 'cancelled' then 'retry_purchase'
    when 'expired' then 'retry_purchase'
    when 'created' then 'await_payment'
    else 'await_payment'
  end;

  update public.platform_client_provision_request
  set provisioning_status = v_request_status,
      next_action = v_next_action,
      updated_at = timezone('utc', now())
  where provision_request_id = v_request_id;

  return public.platform_json_response(
    true,
    'OK',
    'Public checkout state resolved.',
    jsonb_build_object(
      'checkout_id', v_checkout.checkout_id,
      'provision_request_id', v_request_id,
      'checkout_status', v_checkout.checkout_status,
      'provisioning_status', v_request_status,
      'next_action', v_next_action
    )
  );
end;
$function$;

create or replace function public.platform_issue_owner_bootstrap_token(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_id uuid := public.platform_i02_resolve_provision_request_id(p_params);
  v_token_purpose text := lower(coalesce(nullif(btrim(p_params->>'token_purpose'), ''), ''));
  v_expires_in_minutes integer := coalesce(nullif(p_params->>'expires_in_minutes', '')::integer, 1440);
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_request public.platform_client_provision_request%rowtype;
  v_raw_token text;
  v_token_hash text;
  v_token public.platform_owner_bootstrap_token%rowtype;
begin
  if v_request_id is null then
    return public.platform_json_response(false, 'PROVISION_REQUEST_ID_REQUIRED', 'provision_request_id or request_key is required.', '{}'::jsonb);
  end if;
  if v_token_purpose not in ('purchase_activation', 'credential_setup') then
    return public.platform_json_response(false, 'TOKEN_PURPOSE_REQUIRED', 'token_purpose must be purchase_activation or credential_setup.', jsonb_build_object('token_purpose', v_token_purpose));
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  select *
  into v_request
  from public.platform_client_provision_request
  where provision_request_id = v_request_id
  for update;

  if not found then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_FOUND', 'Provision request not found.', jsonb_build_object('provision_request_id', v_request_id));
  end if;

  if v_token_purpose = 'purchase_activation'
     and v_request.provisioning_status not in ('activation_ready', 'payment_paid') then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_ACTIVATION_READY', 'Provision request is not ready for purchase activation.', jsonb_build_object('provisioning_status', v_request.provisioning_status));
  end if;

  if v_token_purpose = 'credential_setup'
     and v_request.provisioning_status not in ('credential_setup_required', 'activation_ready', 'payment_paid') then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_CREDENTIAL_SETUP_READY', 'Provision request is not ready for credential setup.', jsonb_build_object('provisioning_status', v_request.provisioning_status));
  end if;

  update public.platform_owner_bootstrap_token
  set token_status = 'revoked',
      updated_at = timezone('utc', now())
  where provision_request_id = v_request_id
    and token_purpose = v_token_purpose
    and token_status = 'issued';

  v_raw_token := encode(gen_random_bytes(24), 'hex');
  v_token_hash := public.platform_i02_hash_token(v_raw_token);

  insert into public.platform_owner_bootstrap_token (
    provision_request_id,
    token_purpose,
    token_hash,
    token_status,
    issued_for_email,
    expires_at,
    metadata
  )
  values (
    v_request_id,
    v_token_purpose,
    v_token_hash,
    'issued',
    v_request.primary_work_email,
    timezone('utc', now()) + make_interval(mins => v_expires_in_minutes),
    v_metadata
  )
  returning *
  into v_token;

  update public.platform_client_provision_request
  set provisioning_status = case
        when v_token_purpose = 'purchase_activation' then 'activation_ready'
        when provisioning_status in ('activation_ready', 'payment_paid') then 'credential_setup_required'
        else provisioning_status
      end,
      next_action = case
        when v_token_purpose = 'purchase_activation' then 'purchase_activation'
        else 'credential_setup'
      end,
      updated_at = timezone('utc', now())
  where provision_request_id = v_request_id;

  perform public.platform_i02_append_provision_event(jsonb_build_object(
    'provision_request_id', v_request_id,
    'event_type', v_token_purpose || '_token_issued',
    'event_source', 'platform_issue_owner_bootstrap_token',
    'event_message', 'Owner bootstrap token issued.',
    'event_details', jsonb_build_object(
      'token_id', v_token.token_id,
      'token_purpose', v_token_purpose,
      'expires_at', v_token.expires_at
    )
  ));

  return public.platform_json_response(
    true,
    'OK',
    'Owner bootstrap token issued.',
    jsonb_build_object(
      'token_id', v_token.token_id,
      'provision_request_id', v_request_id,
      'token_purpose', v_token_purpose,
      'token', v_raw_token,
      'expires_at', v_token.expires_at
    )
  );
end;
$function$;

create or replace function public.platform_get_owner_bootstrap_context(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_raw_token text := nullif(btrim(coalesce(p_params->>'token', '')), '');
  v_token_purpose text := lower(nullif(btrim(coalesce(p_params->>'token_purpose', '')), ''));
  v_token public.platform_owner_bootstrap_token%rowtype;
  v_request public.platform_client_provision_request%rowtype;
begin
  if v_raw_token is null then
    return public.platform_json_response(false, 'TOKEN_REQUIRED', 'token is required.', '{}'::jsonb);
  end if;

  select *
  into v_token
  from public.platform_owner_bootstrap_token
  where token_hash = public.platform_i02_hash_token(v_raw_token)
    and (v_token_purpose is null or token_purpose = v_token_purpose)
  order by created_at desc
  limit 1
  for update;

  if not found then
    return public.platform_json_response(false, 'TOKEN_NOT_FOUND', 'Owner bootstrap token not found.', '{}'::jsonb);
  end if;

  if v_token.token_status = 'issued' and v_token.expires_at < timezone('utc', now()) then
    update public.platform_owner_bootstrap_token
    set token_status = 'expired',
        updated_at = timezone('utc', now())
    where token_id = v_token.token_id;

    v_token.token_status := 'expired';
  end if;

  if v_token.token_status <> 'issued' then
    return public.platform_json_response(false, 'TOKEN_NOT_ACTIVE', 'Owner bootstrap token is not active.', jsonb_build_object('token_status', v_token.token_status, 'token_purpose', v_token.token_purpose));
  end if;

  select *
  into v_request
  from public.platform_client_provision_request
  where provision_request_id = v_token.provision_request_id;

  if not found then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_FOUND', 'Provision request not found for token.', jsonb_build_object('token_id', v_token.token_id));
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'Owner bootstrap context resolved.',
    jsonb_build_object(
      'token_id', v_token.token_id,
      'token_purpose', v_token.token_purpose,
      'expires_at', v_token.expires_at,
      'provision_request_id', v_request.provision_request_id,
      'company_name', v_request.company_name,
      'primary_work_email', v_request.primary_work_email,
      'selected_plan_code', v_request.selected_plan_code,
      'provisioning_status', v_request.provisioning_status,
      'tenant_id', v_request.tenant_id,
      'owner_actor_user_id', v_request.owner_actor_user_id
    )
  );
end;
$function$;

create or replace function public.platform_consume_owner_bootstrap_token(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_raw_token text := nullif(btrim(coalesce(p_params->>'token', '')), '');
  v_token_purpose text := lower(nullif(btrim(coalesce(p_params->>'token_purpose', '')), ''));
  v_consumed_by_user_id uuid := public.platform_try_uuid(p_params->>'consumed_by_user_id');
  v_token public.platform_owner_bootstrap_token%rowtype;
begin
  if v_raw_token is null then
    return public.platform_json_response(false, 'TOKEN_REQUIRED', 'token is required.', '{}'::jsonb);
  end if;

  select *
  into v_token
  from public.platform_owner_bootstrap_token
  where token_hash = public.platform_i02_hash_token(v_raw_token)
    and (v_token_purpose is null or token_purpose = v_token_purpose)
  order by created_at desc
  limit 1
  for update;

  if not found then
    return public.platform_json_response(false, 'TOKEN_NOT_FOUND', 'Owner bootstrap token not found.', '{}'::jsonb);
  end if;

  if v_token.token_status = 'issued' and v_token.expires_at < timezone('utc', now()) then
    update public.platform_owner_bootstrap_token
    set token_status = 'expired',
        updated_at = timezone('utc', now())
    where token_id = v_token.token_id;

    return public.platform_json_response(false, 'TOKEN_EXPIRED', 'Owner bootstrap token has expired.', jsonb_build_object('token_id', v_token.token_id, 'token_purpose', v_token.token_purpose));
  end if;

  if v_token.token_status <> 'issued' then
    return public.platform_json_response(false, 'TOKEN_NOT_ACTIVE', 'Owner bootstrap token is not active.', jsonb_build_object('token_status', v_token.token_status, 'token_purpose', v_token.token_purpose));
  end if;

  update public.platform_owner_bootstrap_token
  set token_status = 'consumed',
      consumed_at = timezone('utc', now()),
      consumed_by_user_id = coalesce(v_consumed_by_user_id, consumed_by_user_id),
      updated_at = timezone('utc', now())
  where token_id = v_token.token_id
  returning *
  into v_token;

  perform public.platform_i02_append_provision_event(jsonb_build_object(
    'provision_request_id', v_token.provision_request_id,
    'event_type', v_token.token_purpose || '_token_consumed',
    'event_source', 'platform_consume_owner_bootstrap_token',
    'event_message', 'Owner bootstrap token consumed.',
    'event_details', jsonb_build_object(
      'token_id', v_token.token_id,
      'token_purpose', v_token.token_purpose,
      'consumed_by_user_id', v_token.consumed_by_user_id
    )
  ));

  return public.platform_json_response(
    true,
    'OK',
    'Owner bootstrap token consumed.',
    jsonb_build_object(
      'token_id', v_token.token_id,
      'provision_request_id', v_token.provision_request_id,
      'token_purpose', v_token.token_purpose,
      'consumed_by_user_id', v_token.consumed_by_user_id
    )
  );
end;
$function$;

create or replace function public.platform_accept_purchase_activation(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_consume_result jsonb;
  v_request_id uuid;
  v_issue_result jsonb;
begin
  v_consume_result := public.platform_consume_owner_bootstrap_token(jsonb_build_object(
    'token', p_params->>'token',
    'token_purpose', 'purchase_activation'
  ));

  if coalesce((v_consume_result->>'success')::boolean, false) is not true then
    return v_consume_result;
  end if;

  v_request_id := public.platform_try_uuid(v_consume_result->'details'->>'provision_request_id');
  if v_request_id is null then
    return public.platform_json_response(false, 'PROVISION_REQUEST_ID_MISSING', 'Provision request id missing after purchase activation consume.', jsonb_build_object('consume_result', v_consume_result));
  end if;

  update public.platform_client_provision_request
  set provisioning_status = 'credential_setup_required',
      next_action = 'credential_setup',
      updated_at = timezone('utc', now())
  where provision_request_id = v_request_id;

  perform public.platform_i02_append_provision_event(jsonb_build_object(
    'provision_request_id', v_request_id,
    'event_type', 'purchase_activation_accepted',
    'event_source', 'platform_accept_purchase_activation',
    'event_message', 'Purchase activation accepted.'
  ));

  v_issue_result := public.platform_issue_owner_bootstrap_token(jsonb_build_object(
    'provision_request_id', v_request_id,
    'token_purpose', 'credential_setup',
    'expires_in_minutes', coalesce(nullif(p_params->>'credential_setup_expires_in_minutes', '')::integer, 1440)
  ));

  if coalesce((v_issue_result->>'success')::boolean, false) is not true then
    return v_issue_result;
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'Purchase activation accepted.',
    jsonb_build_object(
      'provision_request_id', v_request_id,
      'credential_setup_token', v_issue_result->'details'->>'token',
      'credential_setup_token_id', v_issue_result->'details'->>'token_id',
      'credential_setup_expires_at', v_issue_result->'details'->>'expires_at',
      'next_action', 'credential_setup'
    )
  );
end;
$function$;

create or replace function public.platform_mark_client_identity_created(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_id uuid := public.platform_i02_resolve_provision_request_id(p_params);
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_request public.platform_client_provision_request%rowtype;
  v_profile_result jsonb;
begin
  if v_request_id is null then
    return public.platform_json_response(false, 'PROVISION_REQUEST_ID_REQUIRED', 'provision_request_id or request_key is required.', '{}'::jsonb);
  end if;
  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
  end if;

  select *
  into v_request
  from public.platform_client_provision_request
  where provision_request_id = v_request_id
  for update;

  if not found then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_FOUND', 'Provision request not found.', jsonb_build_object('provision_request_id', v_request_id));
  end if;

  v_profile_result := public.platform_upsert_actor_profile(jsonb_build_object(
    'actor_user_id', v_actor_user_id,
    'primary_email', coalesce(nullif(btrim(p_params->>'primary_email'), ''), v_request.primary_work_email),
    'primary_mobile', coalesce(nullif(btrim(p_params->>'primary_mobile'), ''), v_request.primary_mobile),
    'display_name', coalesce(nullif(btrim(p_params->>'display_name'), ''), v_request.primary_contact_name),
    'profile_status', 'active',
    'email_verified', coalesce((p_params->>'email_verified')::boolean, true),
    'created_via', 'client_bootstrap',
    'metadata', jsonb_build_object('provision_request_id', v_request_id, 'source', 'platform_mark_client_identity_created')
  ));

  if coalesce((v_profile_result->>'success')::boolean, false) is not true then
    return v_profile_result;
  end if;

  update public.platform_client_provision_request
  set owner_actor_user_id = v_actor_user_id,
      provisioning_status = 'identity_created',
      next_action = 'tenant_bootstrap',
      updated_at = timezone('utc', now())
  where provision_request_id = v_request_id;

  perform public.platform_i02_append_provision_event(jsonb_build_object(
    'provision_request_id', v_request_id,
    'actor_user_id', v_actor_user_id,
    'event_type', 'identity_created',
    'event_source', 'platform_mark_client_identity_created',
    'event_message', 'Client owner identity created or linked.',
    'event_details', jsonb_build_object('actor_user_id', v_actor_user_id)
  ));

  return public.platform_json_response(
    true,
    'OK',
    'Client owner identity marked as created.',
    jsonb_build_object(
      'provision_request_id', v_request_id,
      'actor_user_id', v_actor_user_id,
      'provisioning_status', 'identity_created',
      'next_action', 'tenant_bootstrap'
    )
  );
end;
$function$;

create or replace function public.platform_bootstrap_client_tenant_header(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_id uuid := public.platform_i02_resolve_provision_request_id(p_params);
  v_template_version text := nullif(btrim(coalesce(p_params->>'template_version', '')), '');
  v_request public.platform_client_provision_request%rowtype;
  v_tenant_code text;
  v_result jsonb;
  v_tenant_id uuid;
begin
  if v_request_id is null then
    return public.platform_json_response(false, 'PROVISION_REQUEST_ID_REQUIRED', 'provision_request_id or request_key is required.', '{}'::jsonb);
  end if;

  select *
  into v_request
  from public.platform_client_provision_request
  where provision_request_id = v_request_id
  for update;

  if not found then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_FOUND', 'Provision request not found.', jsonb_build_object('provision_request_id', v_request_id));
  end if;

  if v_request.owner_actor_user_id is null then
    return public.platform_json_response(false, 'OWNER_IDENTITY_NOT_READY', 'Owner identity must be created before tenant bootstrap.', jsonb_build_object('provisioning_status', v_request.provisioning_status));
  end if;

  if v_request.tenant_id is not null then
    return public.platform_json_response(
      true,
      'OK',
      'Tenant header already bootstrapped for this provision request.',
      jsonb_build_object(
        'provision_request_id', v_request_id,
        'tenant_id', v_request.tenant_id,
        'idempotent_replay', true
      )
    );
  end if;

  if v_template_version is null then
    v_template_version := public.platform_i02_latest_foundation_template_version();
  end if;

  if v_template_version is null then
    return public.platform_json_response(false, 'FOUNDATION_TEMPLATE_NOT_FOUND', 'No released foundation template is available.', '{}'::jsonb);
  end if;

  v_tenant_code := public.platform_i02_generate_tenant_code(v_request.company_name, v_request.provision_request_id);

  v_result := public.platform_create_tenant_registry(jsonb_build_object(
    'tenant_code', v_tenant_code,
    'display_name', v_request.company_name,
    'legal_name', v_request.legal_name,
    'default_currency_code', coalesce(nullif(v_request.currency_code, ''), 'INR'),
    'default_timezone', coalesce(nullif(v_request.timezone, ''), 'Asia/Kolkata'),
    'tenant_kind', 'client',
    'metadata', jsonb_build_object(
      'source', 'platform_bootstrap_client_tenant_header',
      'provision_request_id', v_request_id
    )
  ));

  if coalesce((v_result->>'success')::boolean, false) is not true then
    return v_result;
  end if;

  v_tenant_id := public.platform_try_uuid(v_result->'details'->>'tenant_id');
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_MISSING', 'tenant_id missing from platform_create_tenant_registry result.', jsonb_build_object('result', v_result));
  end if;

  v_result := public.platform_create_tenant_schema(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'source', 'platform_bootstrap_client_tenant_header'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    return v_result;
  end if;

  v_result := public.platform_apply_template_version_to_tenant(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'template_version', v_template_version,
    'source', 'platform_bootstrap_client_tenant_header'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    return v_result;
  end if;

  v_result := public.platform_transition_provisioning_state(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'to_status', 'ready_for_routing',
    'source', 'platform_bootstrap_client_tenant_header',
    'latest_completed_step', 'client_bootstrap_completed',
    'ready_for_routing', true,
    'details', jsonb_build_object(
      'template_version', v_template_version,
      'provision_request_id', v_request_id
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    return v_result;
  end if;

  update public.platform_client_provision_request
  set tenant_id = v_tenant_id,
      provisioning_status = 'tenant_created',
      next_action = 'owner_binding',
      metadata = metadata || jsonb_build_object('tenant_code', v_tenant_code, 'template_version', v_template_version),
      updated_at = timezone('utc', now())
  where provision_request_id = v_request_id;

  perform public.platform_i02_append_provision_event(jsonb_build_object(
    'provision_request_id', v_request_id,
    'actor_user_id', v_request.owner_actor_user_id,
    'event_type', 'tenant_created',
    'event_source', 'platform_bootstrap_client_tenant_header',
    'event_message', 'Tenant header, schema, and foundation template bootstrapped.',
    'event_details', jsonb_build_object(
      'tenant_id', v_tenant_id,
      'tenant_code', v_tenant_code,
      'template_version', v_template_version
    )
  ));

  return public.platform_json_response(
    true,
    'OK',
    'Client tenant header bootstrapped.',
    jsonb_build_object(
      'provision_request_id', v_request_id,
      'tenant_id', v_tenant_id,
      'tenant_code', v_tenant_code,
      'template_version', v_template_version,
      'next_action', 'owner_binding'
    )
  );
end;
$function$;

create or replace function public.platform_bind_client_owner_admin(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_id uuid := public.platform_i02_resolve_provision_request_id(p_params);
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_try_uuid(p_params->>'owner_actor_user_id'));
  v_request public.platform_client_provision_request%rowtype;
  v_result jsonb;
begin
  if v_request_id is null then
    return public.platform_json_response(false, 'PROVISION_REQUEST_ID_REQUIRED', 'provision_request_id or request_key is required.', '{}'::jsonb);
  end if;

  select *
  into v_request
  from public.platform_client_provision_request
  where provision_request_id = v_request_id
  for update;

  if not found then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_FOUND', 'Provision request not found.', jsonb_build_object('provision_request_id', v_request_id));
  end if;

  if v_request.tenant_id is null then
    return public.platform_json_response(false, 'TENANT_NOT_READY', 'Tenant must be created before owner binding.', jsonb_build_object('provisioning_status', v_request.provisioning_status));
  end if;

  v_actor_user_id := coalesce(v_actor_user_id, v_request.owner_actor_user_id);
  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required for owner binding.', '{}'::jsonb);
  end if;

  if not exists (
    select 1
    from public.platform_access_role r
    where r.role_code = 'tenant_owner_admin'
      and r.role_status = 'active'
  ) then
    return public.platform_json_response(false, 'OWNER_ADMIN_ROLE_NOT_FOUND', 'tenant_owner_admin role is not available.', '{}'::jsonb);
  end if;

  if not exists (
    select 1
    from public.platform_access_role r
    where r.role_code = 'i01_portal_user'
      and r.role_status = 'active'
  ) then
    return public.platform_json_response(false, 'PORTAL_SIGNIN_ROLE_NOT_FOUND', 'i01_portal_user role is required for initial owner signin.', '{}'::jsonb);
  end if;

  v_result := public.platform_upsert_actor_profile(jsonb_build_object(
    'actor_user_id', v_actor_user_id,
    'primary_email', coalesce(nullif(btrim(p_params->>'primary_email'), ''), v_request.primary_work_email),
    'primary_mobile', coalesce(nullif(btrim(p_params->>'primary_mobile'), ''), v_request.primary_mobile),
    'display_name', coalesce(nullif(btrim(p_params->>'display_name'), ''), v_request.primary_contact_name),
    'profile_status', 'active',
    'email_verified', true,
    'created_via', 'client_bootstrap',
    'metadata', jsonb_build_object('provision_request_id', v_request_id, 'source', 'platform_bind_client_owner_admin')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    return v_result;
  end if;

  v_result := public.platform_register_actor_tenant_membership(jsonb_build_object(
    'tenant_id', v_request.tenant_id,
    'actor_user_id', v_actor_user_id,
    'membership_status', 'active',
    'routing_status', 'enabled',
    'is_default_tenant', true,
    'metadata', jsonb_build_object('provision_request_id', v_request_id, 'source', 'platform_bind_client_owner_admin')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    return v_result;
  end if;

  v_result := public.platform_assign_actor_role(jsonb_build_object(
    'tenant_id', v_request.tenant_id,
    'actor_user_id', v_actor_user_id,
    'role_code', 'tenant_owner_admin',
    'grant_status', 'active',
    'metadata', jsonb_build_object('provision_request_id', v_request_id, 'source', 'platform_bind_client_owner_admin')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    return v_result;
  end if;

  v_result := public.platform_assign_actor_role(jsonb_build_object(
    'tenant_id', v_request.tenant_id,
    'actor_user_id', v_actor_user_id,
    'role_code', 'i01_portal_user',
    'grant_status', 'active',
    'metadata', jsonb_build_object('provision_request_id', v_request_id, 'source', 'platform_bind_client_owner_admin')
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    return v_result;
  end if;

  update public.platform_client_provision_request
  set owner_actor_user_id = v_actor_user_id,
      provisioning_status = 'owner_role_bound',
      next_action = 'commercial_seed',
      updated_at = timezone('utc', now())
  where provision_request_id = v_request_id;

  perform public.platform_i02_append_provision_event(jsonb_build_object(
    'provision_request_id', v_request_id,
    'actor_user_id', v_actor_user_id,
    'event_type', 'owner_role_bound',
    'event_source', 'platform_bind_client_owner_admin',
    'event_message', 'Owner tenant membership and roles bound.',
    'event_details', jsonb_build_object(
      'tenant_id', v_request.tenant_id,
      'actor_user_id', v_actor_user_id,
      'granted_roles', jsonb_build_array('tenant_owner_admin', 'i01_portal_user')
    )
  ));

  return public.platform_json_response(
    true,
    'OK',
    'Client owner admin bound.',
    jsonb_build_object(
      'provision_request_id', v_request_id,
      'tenant_id', v_request.tenant_id,
      'actor_user_id', v_actor_user_id,
      'next_action', 'commercial_seed'
    )
  );
end;
$function$;

create or replace function public.platform_seed_client_commercial_state(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_id uuid := public.platform_i02_resolve_provision_request_id(p_params);
  v_request public.platform_client_provision_request%rowtype;
  v_result jsonb;
begin
  if v_request_id is null then
    return public.platform_json_response(false, 'PROVISION_REQUEST_ID_REQUIRED', 'provision_request_id or request_key is required.', '{}'::jsonb);
  end if;

  select *
  into v_request
  from public.platform_client_provision_request
  where provision_request_id = v_request_id
  for update;

  if not found then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_FOUND', 'Provision request not found.', jsonb_build_object('provision_request_id', v_request_id));
  end if;

  if v_request.tenant_id is null then
    return public.platform_json_response(false, 'TENANT_NOT_READY', 'Tenant must be created before commercial seeding.', '{}'::jsonb);
  end if;

  v_result := public.platform_upsert_tenant_subscription(jsonb_build_object(
    'tenant_id', v_request.tenant_id,
    'plan_code', v_request.selected_plan_code,
    'subscription_status', 'active',
    'billing_owner_user_id', v_request.owner_actor_user_id,
    'currency_code', coalesce(nullif(v_request.currency_code, ''), 'INR'),
    'metadata', jsonb_build_object('provision_request_id', v_request_id, 'source', 'platform_seed_client_commercial_state')
  ));

  if coalesce((v_result->>'success')::boolean, false) is not true then
    return v_result;
  end if;

  update public.platform_client_provision_request
  set provisioning_status = 'commercial_seeded',
      next_action = 'setup_seed',
      updated_at = timezone('utc', now())
  where provision_request_id = v_request_id;

  perform public.platform_i02_append_provision_event(jsonb_build_object(
    'provision_request_id', v_request_id,
    'actor_user_id', v_request.owner_actor_user_id,
    'event_type', 'commercial_seeded',
    'event_source', 'platform_seed_client_commercial_state',
    'event_message', 'Client commercial baseline seeded.',
    'event_details', jsonb_build_object(
      'tenant_id', v_request.tenant_id,
      'plan_code', v_request.selected_plan_code,
      'subscription_id', v_result->'details'->>'subscription_id'
    )
  ));

  return public.platform_json_response(
    true,
    'OK',
    'Client commercial state seeded.',
    jsonb_build_object(
      'provision_request_id', v_request_id,
      'tenant_id', v_request.tenant_id,
      'subscription_id', v_result->'details'->>'subscription_id',
      'next_action', 'setup_seed'
    )
  );
end;
$function$;

create or replace function public.platform_seed_client_owner_setup_state(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_id uuid := public.platform_i02_resolve_provision_request_id(p_params);
  v_request public.platform_client_provision_request%rowtype;
begin
  if v_request_id is null then
    return public.platform_json_response(false, 'PROVISION_REQUEST_ID_REQUIRED', 'provision_request_id or request_key is required.', '{}'::jsonb);
  end if;

  select *
  into v_request
  from public.platform_client_provision_request
  where provision_request_id = v_request_id
  for update;

  if not found then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_FOUND', 'Provision request not found.', jsonb_build_object('provision_request_id', v_request_id));
  end if;

  if v_request.tenant_id is null or v_request.owner_actor_user_id is null then
    return public.platform_json_response(false, 'PROVISION_REQUEST_NOT_SETUP_READY', 'Tenant and owner identity must be ready before setup completion.', jsonb_build_object('tenant_id', v_request.tenant_id, 'owner_actor_user_id', v_request.owner_actor_user_id));
  end if;

  update public.platform_client_provision_request
  set provisioning_status = 'ready_for_signin',
      next_action = 'signin',
      updated_at = timezone('utc', now())
  where provision_request_id = v_request_id;

  perform public.platform_i02_append_provision_event(jsonb_build_object(
    'provision_request_id', v_request_id,
    'actor_user_id', v_request.owner_actor_user_id,
    'event_type', 'setup_seeded',
    'event_source', 'platform_seed_client_owner_setup_state',
    'event_message', 'Owner setup state marked ready for signin.',
    'event_details', jsonb_build_object(
      'tenant_id', v_request.tenant_id,
      'signin_hint', '/signin'
    )
  ));

  return public.platform_json_response(
    true,
    'OK',
    'Client owner setup state seeded.',
    jsonb_build_object(
      'provision_request_id', v_request_id,
      'tenant_id', v_request.tenant_id,
      'owner_actor_user_id', v_request.owner_actor_user_id,
      'provisioning_status', 'ready_for_signin',
      'next_action', 'signin',
      'signin_hint', '/signin'
    )
  );
end;
$function$;

revoke all on public.platform_rm_client_provision_state from public, anon, authenticated;
grant select on public.platform_rm_client_provision_state to service_role;

revoke all on function public.platform_capture_client_provision_intent(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_client_provision_state(jsonb) from public, anon, authenticated;
revoke all on function public.platform_create_or_resume_public_checkout(jsonb) from public, anon, authenticated;
revoke all on function public.platform_attach_public_checkout(jsonb) from public, anon, authenticated;
revoke all on function public.platform_record_public_checkout_event(jsonb) from public, anon, authenticated;
revoke all on function public.platform_resolve_public_checkout(jsonb) from public, anon, authenticated;
revoke all on function public.platform_issue_owner_bootstrap_token(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_owner_bootstrap_context(jsonb) from public, anon, authenticated;
revoke all on function public.platform_consume_owner_bootstrap_token(jsonb) from public, anon, authenticated;
revoke all on function public.platform_accept_purchase_activation(jsonb) from public, anon, authenticated;
revoke all on function public.platform_mark_client_identity_created(jsonb) from public, anon, authenticated;
revoke all on function public.platform_bootstrap_client_tenant_header(jsonb) from public, anon, authenticated;
revoke all on function public.platform_bind_client_owner_admin(jsonb) from public, anon, authenticated;
revoke all on function public.platform_seed_client_commercial_state(jsonb) from public, anon, authenticated;
revoke all on function public.platform_seed_client_owner_setup_state(jsonb) from public, anon, authenticated;

grant execute on function public.platform_capture_client_provision_intent(jsonb) to service_role;
grant execute on function public.platform_get_client_provision_state(jsonb) to service_role;
grant execute on function public.platform_create_or_resume_public_checkout(jsonb) to service_role;
grant execute on function public.platform_attach_public_checkout(jsonb) to service_role;
grant execute on function public.platform_record_public_checkout_event(jsonb) to service_role;
grant execute on function public.platform_resolve_public_checkout(jsonb) to service_role;
grant execute on function public.platform_issue_owner_bootstrap_token(jsonb) to service_role;
grant execute on function public.platform_get_owner_bootstrap_context(jsonb) to service_role;
grant execute on function public.platform_consume_owner_bootstrap_token(jsonb) to service_role;
grant execute on function public.platform_accept_purchase_activation(jsonb) to service_role;
grant execute on function public.platform_mark_client_identity_created(jsonb) to service_role;
grant execute on function public.platform_bootstrap_client_tenant_header(jsonb) to service_role;
grant execute on function public.platform_bind_client_owner_admin(jsonb) to service_role;
grant execute on function public.platform_seed_client_commercial_state(jsonb) to service_role;
grant execute on function public.platform_seed_client_owner_setup_state(jsonb) to service_role;

;
