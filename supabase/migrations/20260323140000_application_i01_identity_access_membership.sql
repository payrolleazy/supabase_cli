create table if not exists public.platform_actor_profile (
  actor_user_id uuid primary key,
  primary_email text null,
  primary_mobile text null,
  display_name text null,
  profile_status text not null default 'pending_signup'
    check (profile_status in ('pending_signup', 'active', 'suspended', 'disabled')),
  email_verified boolean not null default false,
  mobile_verified boolean not null default false,
  created_via text not null default 'internal',
  last_signin_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_actor_profile_metadata_check check (jsonb_typeof(metadata) = 'object')
);
create index if not exists idx_platform_actor_profile_email
on public.platform_actor_profile (lower(primary_email));
create index if not exists idx_platform_actor_profile_mobile
on public.platform_actor_profile (primary_mobile);
alter table public.platform_actor_profile enable row level security;
drop policy if exists platform_actor_profile_service_role_all on public.platform_actor_profile;
create policy platform_actor_profile_service_role_all
on public.platform_actor_profile
for all
to service_role
using (true)
with check (true);
drop trigger if exists trg_platform_actor_profile_set_updated_at on public.platform_actor_profile;
create trigger trg_platform_actor_profile_set_updated_at
before update on public.platform_actor_profile
for each row
execute function public.platform_set_updated_at();
create table if not exists public.platform_access_role (
  role_code text primary key,
  role_scope text not null check (role_scope in ('platform', 'tenant')),
  role_status text not null default 'active' check (role_status in ('active', 'disabled')),
  description text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_access_role_metadata_check check (jsonb_typeof(metadata) = 'object')
);
alter table public.platform_access_role enable row level security;
drop policy if exists platform_access_role_service_role_all on public.platform_access_role;
create policy platform_access_role_service_role_all
on public.platform_access_role
for all
to service_role
using (true)
with check (true);
drop trigger if exists trg_platform_access_role_set_updated_at on public.platform_access_role;
create trigger trg_platform_access_role_set_updated_at
before update on public.platform_access_role
for each row
execute function public.platform_set_updated_at();
create table if not exists public.platform_actor_role_grant (
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  actor_user_id uuid not null,
  role_code text not null references public.platform_access_role(role_code),
  grant_status text not null default 'active' check (grant_status in ('active', 'revoked', 'suspended')),
  granted_at timestamptz not null default timezone('utc', now()),
  granted_by uuid null,
  revoked_at timestamptz null,
  revoked_by uuid null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_actor_role_grant_pkey primary key (tenant_id, actor_user_id, role_code),
  constraint platform_actor_role_grant_metadata_check check (jsonb_typeof(metadata) = 'object')
);
create index if not exists idx_platform_actor_role_grant_actor
on public.platform_actor_role_grant (actor_user_id, grant_status);
alter table public.platform_actor_role_grant enable row level security;
drop policy if exists platform_actor_role_grant_service_role_all on public.platform_actor_role_grant;
create policy platform_actor_role_grant_service_role_all
on public.platform_actor_role_grant
for all
to service_role
using (true)
with check (true);
drop trigger if exists trg_platform_actor_role_grant_set_updated_at on public.platform_actor_role_grant;
create trigger trg_platform_actor_role_grant_set_updated_at
before update on public.platform_actor_role_grant
for each row
execute function public.platform_set_updated_at();
create table if not exists public.platform_membership_invitation (
  invitation_id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.platform_tenant(tenant_id) on delete cascade,
  invited_email text null,
  invited_mobile text null,
  role_code text not null references public.platform_access_role(role_code),
  invitation_status text not null default 'pending' check (invitation_status in ('pending', 'claimed', 'expired', 'revoked')),
  expires_at timestamptz null,
  claimed_at timestamptz null,
  claimed_by_user_id uuid null,
  issued_by uuid null,
  position_context jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_membership_invitation_target_check check (coalesce(invited_email, '') <> '' or coalesce(invited_mobile, '') <> ''),
  constraint platform_membership_invitation_position_context_check check (jsonb_typeof(position_context) = 'object'),
  constraint platform_membership_invitation_metadata_check check (jsonb_typeof(metadata) = 'object')
);
create index if not exists idx_platform_membership_invitation_lookup
on public.platform_membership_invitation (tenant_id, role_code, invitation_status, lower(invited_email), invited_mobile);
alter table public.platform_membership_invitation enable row level security;
drop policy if exists platform_membership_invitation_service_role_all on public.platform_membership_invitation;
create policy platform_membership_invitation_service_role_all
on public.platform_membership_invitation
for all
to service_role
using (true)
with check (true);
drop trigger if exists trg_platform_membership_invitation_set_updated_at on public.platform_membership_invitation;
create trigger trg_platform_membership_invitation_set_updated_at
before update on public.platform_membership_invitation
for each row
execute function public.platform_set_updated_at();
create table if not exists public.platform_signup_request (
  signup_request_id uuid primary key default gen_random_uuid(),
  invitation_id uuid null references public.platform_membership_invitation(invitation_id) on delete set null,
  email text not null,
  mobile_no text not null,
  request_status text not null default 'received' check (request_status in ('received', 'queued', 'processing', 'completed', 'denied', 'failed')),
  status_token_hash text not null unique,
  async_job_id uuid null references public.platform_async_job(job_id) on delete set null,
  source_ip text null,
  user_agent text null,
  decision_reason text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  completed_at timestamptz null,
  constraint platform_signup_request_metadata_check check (jsonb_typeof(metadata) = 'object')
);
create index if not exists idx_platform_signup_request_lookup
on public.platform_signup_request (lower(email), mobile_no, created_at desc);
alter table public.platform_signup_request enable row level security;
drop policy if exists platform_signup_request_service_role_all on public.platform_signup_request;
create policy platform_signup_request_service_role_all
on public.platform_signup_request
for all
to service_role
using (true)
with check (true);
drop trigger if exists trg_platform_signup_request_set_updated_at on public.platform_signup_request;
create trigger trg_platform_signup_request_set_updated_at
before update on public.platform_signup_request
for each row
execute function public.platform_set_updated_at();
create table if not exists public.platform_signin_policy (
  policy_code text primary key,
  entrypoint_code text not null,
  requires_password boolean not null default true,
  requires_otp boolean not null default false,
  allowed_role_codes text[] not null default '{}'::text[],
  allowed_membership_statuses text[] not null default array['active']::text[],
  policy_status text not null default 'active' check (policy_status in ('active', 'disabled')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_signin_policy_metadata_check check (jsonb_typeof(metadata) = 'object')
);
alter table public.platform_signin_policy enable row level security;
drop policy if exists platform_signin_policy_service_role_all on public.platform_signin_policy;
create policy platform_signin_policy_service_role_all
on public.platform_signin_policy
for all
to service_role
using (true)
with check (true);
drop trigger if exists trg_platform_signin_policy_set_updated_at on public.platform_signin_policy;
create trigger trg_platform_signin_policy_set_updated_at
before update on public.platform_signin_policy
for each row
execute function public.platform_set_updated_at();
create table if not exists public.platform_signin_challenge (
  challenge_id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null,
  policy_code text not null references public.platform_signin_policy(policy_code),
  challenge_status text not null default 'issued' check (challenge_status in ('issued', 'consumed', 'expired', 'cancelled')),
  challenge_token_hash text not null unique,
  source_ip text null,
  attempt_count integer not null default 0,
  expires_at timestamptz not null,
  consumed_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint platform_signin_challenge_metadata_check check (jsonb_typeof(metadata) = 'object')
);
create index if not exists idx_platform_signin_challenge_actor_status
on public.platform_signin_challenge (actor_user_id, challenge_status, expires_at);
alter table public.platform_signin_challenge enable row level security;
drop policy if exists platform_signin_challenge_service_role_all on public.platform_signin_challenge;
create policy platform_signin_challenge_service_role_all
on public.platform_signin_challenge
for all
to service_role
using (true)
with check (true);
drop trigger if exists trg_platform_signin_challenge_set_updated_at on public.platform_signin_challenge;
create trigger trg_platform_signin_challenge_set_updated_at
before update on public.platform_signin_challenge
for each row
execute function public.platform_set_updated_at();
create table if not exists public.platform_signin_attempt_log (
  attempt_id bigint generated always as identity primary key,
  identifier text not null,
  identifier_type text not null check (identifier_type in ('email', 'mobile', 'ip')),
  policy_code text null,
  attempt_result text not null check (attempt_result in ('allowed', 'failed_credentials', 'failed_policy', 'failed_rate_limit', 'failed_otp', 'succeeded')),
  source_ip text null,
  actor_user_id uuid null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  constraint platform_signin_attempt_log_metadata_check check (jsonb_typeof(metadata) = 'object')
);
create index if not exists idx_platform_signin_attempt_log_identifier
on public.platform_signin_attempt_log (identifier_type, identifier, created_at desc);
alter table public.platform_signin_attempt_log enable row level security;
drop policy if exists platform_signin_attempt_log_service_role_all on public.platform_signin_attempt_log;
create policy platform_signin_attempt_log_service_role_all
on public.platform_signin_attempt_log
for all
to service_role
using (true)
with check (true);
create table if not exists public.platform_identity_event_log (
  event_id bigint generated always as identity primary key,
  event_timestamp timestamptz not null default timezone('utc', now()),
  event_type text not null,
  severity text not null,
  tenant_id uuid null,
  actor_user_id uuid null,
  invitation_id uuid null,
  signup_request_id uuid null,
  message text not null,
  details jsonb not null default '{}'::jsonb,
  constraint platform_identity_event_log_details_check check (jsonb_typeof(details) = 'object')
);
create index if not exists idx_platform_identity_event_log_time
on public.platform_identity_event_log (event_timestamp desc);
create index if not exists idx_platform_identity_event_log_actor
on public.platform_identity_event_log (actor_user_id, tenant_id, event_timestamp desc);
alter table public.platform_identity_event_log enable row level security;
drop policy if exists platform_identity_event_log_service_role_all on public.platform_identity_event_log;
create policy platform_identity_event_log_service_role_all
on public.platform_identity_event_log
for all
to service_role
using (true)
with check (true);
create or replace view public.platform_rm_actor_access_overview as
select
  patmv.actor_user_id,
  pap.primary_email,
  pap.primary_mobile,
  pap.display_name,
  pap.profile_status,
  patmv.tenant_id,
  patmv.tenant_code,
  patmv.schema_name,
  patmv.membership_status,
  patmv.routing_status,
  patmv.is_default_tenant,
  patmv.access_state,
  patmv.client_access_allowed,
  patmv.background_processing_allowed,
  coalesce(array_agg(parg.role_code order by parg.role_code) filter (where parg.grant_status = 'active'), '{}'::text[]) as active_role_codes
from public.platform_actor_tenant_membership_view patmv
left join public.platform_actor_profile pap on pap.actor_user_id = patmv.actor_user_id
left join public.platform_actor_role_grant parg
  on parg.tenant_id = patmv.tenant_id
 and parg.actor_user_id = patmv.actor_user_id
group by
  patmv.actor_user_id,
  pap.primary_email,
  pap.primary_mobile,
  pap.display_name,
  pap.profile_status,
  patmv.tenant_id,
  patmv.tenant_code,
  patmv.schema_name,
  patmv.membership_status,
  patmv.routing_status,
  patmv.is_default_tenant,
  patmv.access_state,
  patmv.client_access_allowed,
  patmv.background_processing_allowed;
create or replace view public.platform_rm_membership_invitation_overview as
select
  pmi.invitation_id,
  pmi.tenant_id,
  pt.tenant_code,
  pmi.invited_email,
  pmi.invited_mobile,
  pmi.role_code,
  pmi.invitation_status,
  pmi.expires_at,
  pmi.claimed_at,
  pmi.claimed_by_user_id,
  pmi.created_at,
  pmi.updated_at
from public.platform_membership_invitation pmi
join public.platform_tenant pt on pt.tenant_id = pmi.tenant_id;
create or replace view public.platform_rm_signup_request_status as
select
  psr.signup_request_id,
  psr.request_status,
  psr.email,
  psr.mobile_no,
  psr.decision_reason,
  psr.created_at,
  psr.completed_at,
  psr.invitation_id,
  pmi.tenant_id,
  pt.tenant_code
from public.platform_signup_request psr
left join public.platform_membership_invitation pmi on pmi.invitation_id = psr.invitation_id
left join public.platform_tenant pt on pt.tenant_id = pmi.tenant_id;
create or replace function public.platform_identity_write_event(p_params jsonb)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  insert into public.platform_identity_event_log (
    event_type, severity, tenant_id, actor_user_id, invitation_id, signup_request_id, message, details
  ) values (
    btrim(coalesce(p_params->>'event_type', 'identity_event')),
    btrim(coalesce(p_params->>'severity', 'info')),
    public.platform_try_uuid(p_params->>'tenant_id'),
    public.platform_try_uuid(p_params->>'actor_user_id'),
    public.platform_try_uuid(p_params->>'invitation_id'),
    public.platform_try_uuid(p_params->>'signup_request_id'),
    btrim(coalesce(p_params->>'message', 'identity event')),
    coalesce(p_params->'details', '{}'::jsonb)
  );
end;
$function$;
create or replace function public.platform_upsert_actor_profile(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_profile_status text := lower(coalesce(nullif(p_params->>'profile_status', ''), 'active'));
  v_email text := nullif(lower(btrim(coalesce(p_params->>'primary_email', ''))), '');
  v_mobile text := nullif(btrim(coalesce(p_params->>'primary_mobile', '')), '');
  v_display_name text := nullif(btrim(coalesce(p_params->>'display_name', '')), '');
  v_created_via text := lower(coalesce(nullif(p_params->>'created_via', ''), 'internal'));
  v_email_verified boolean := case when p_params ? 'email_verified' then (p_params->>'email_verified')::boolean else false end;
  v_mobile_verified boolean := case when p_params ? 'mobile_verified' then (p_params->>'mobile_verified')::boolean else false end;
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
begin
  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
  end if;
  if v_profile_status not in ('pending_signup', 'active', 'suspended', 'disabled') then
    return public.platform_json_response(false, 'INVALID_PROFILE_STATUS', 'profile_status is invalid.', jsonb_build_object('profile_status', v_profile_status));
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  insert into public.platform_actor_profile (
    actor_user_id, primary_email, primary_mobile, display_name, profile_status,
    email_verified, mobile_verified, created_via, last_signin_at, metadata
  ) values (
    v_actor_user_id, v_email, v_mobile, v_display_name, v_profile_status,
    v_email_verified, v_mobile_verified, v_created_via, null, v_metadata
  )
  on conflict (actor_user_id) do update
  set primary_email = excluded.primary_email,
      primary_mobile = excluded.primary_mobile,
      display_name = excluded.display_name,
      profile_status = excluded.profile_status,
      email_verified = excluded.email_verified,
      mobile_verified = excluded.mobile_verified,
      created_via = excluded.created_via,
      metadata = excluded.metadata,
      updated_at = timezone('utc', now());

  perform public.platform_identity_write_event(jsonb_build_object(
    'event_type', 'actor_profile_upserted',
    'actor_user_id', v_actor_user_id,
    'message', 'Actor profile upserted.',
    'details', jsonb_build_object('profile_status', v_profile_status)
  ));

  return public.platform_json_response(true, 'OK', 'Actor profile upserted.', jsonb_build_object(
    'actor_user_id', v_actor_user_id,
    'profile_status', v_profile_status
  ));
end;
$function$;
create or replace function public.platform_assign_actor_role(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_role_code text := lower(btrim(coalesce(p_params->>'role_code', '')));
  v_grant_status text := lower(coalesce(nullif(p_params->>'grant_status', ''), 'active'));
  v_granted_by uuid := coalesce(public.platform_try_uuid(p_params->>'granted_by'), public.platform_resolve_actor());
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_membership public.platform_actor_tenant_membership%rowtype;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;
  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
  end if;
  if v_role_code = '' then
    return public.platform_json_response(false, 'ROLE_CODE_REQUIRED', 'role_code is required.', '{}'::jsonb);
  end if;
  if v_grant_status not in ('active', 'revoked', 'suspended') then
    return public.platform_json_response(false, 'INVALID_GRANT_STATUS', 'grant_status is invalid.', jsonb_build_object('grant_status', v_grant_status));
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;
  if not exists (
    select 1 from public.platform_access_role par
    where par.role_code = v_role_code and par.role_status = 'active'
  ) then
    return public.platform_json_response(false, 'ROLE_NOT_FOUND', 'Active role not found.', jsonb_build_object('role_code', v_role_code));
  end if;

  select * into v_membership
  from public.platform_actor_tenant_membership
  where tenant_id = v_tenant_id and actor_user_id = v_actor_user_id;

  if not found then
    return public.platform_json_response(false, 'ACTOR_TENANT_MEMBERSHIP_NOT_FOUND', 'Actor membership not found.', jsonb_build_object('tenant_id', v_tenant_id, 'actor_user_id', v_actor_user_id));
  end if;
  if not (v_membership.membership_status = 'active' and v_membership.routing_status = 'enabled') then
    return public.platform_json_response(false, 'ACTOR_TENANT_MEMBERSHIP_DISABLED', 'Actor membership is not active for role assignment.', jsonb_build_object('tenant_id', v_tenant_id, 'actor_user_id', v_actor_user_id));
  end if;

  insert into public.platform_actor_role_grant (
    tenant_id, actor_user_id, role_code, grant_status, granted_at, granted_by, revoked_at, revoked_by, metadata
  ) values (
    v_tenant_id, v_actor_user_id, v_role_code, v_grant_status, timezone('utc', now()), v_granted_by,
    case when v_grant_status <> 'active' then timezone('utc', now()) else null end,
    case when v_grant_status <> 'active' then v_granted_by else null end,
    v_metadata
  )
  on conflict (tenant_id, actor_user_id, role_code) do update
  set grant_status = excluded.grant_status,
      granted_at = excluded.granted_at,
      granted_by = excluded.granted_by,
      revoked_at = excluded.revoked_at,
      revoked_by = excluded.revoked_by,
      metadata = excluded.metadata,
      updated_at = timezone('utc', now());

  perform public.platform_identity_write_event(jsonb_build_object(
    'event_type', 'actor_role_assigned',
    'tenant_id', v_tenant_id,
    'actor_user_id', v_actor_user_id,
    'message', 'Actor role grant upserted.',
    'details', jsonb_build_object('role_code', v_role_code, 'grant_status', v_grant_status)
  ));

  return public.platform_json_response(true, 'OK', 'Actor role grant upserted.', jsonb_build_object(
    'tenant_id', v_tenant_id,
    'actor_user_id', v_actor_user_id,
    'role_code', v_role_code,
    'grant_status', v_grant_status
  ));
end;
$function$;
create or replace function public.platform_revoke_actor_role(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_role_code text := lower(btrim(coalesce(p_params->>'role_code', '')));
  v_revoked_by uuid := coalesce(public.platform_try_uuid(p_params->>'revoked_by'), public.platform_resolve_actor());
begin
  if v_tenant_id is null or v_actor_user_id is null or v_role_code = '' then
    return public.platform_json_response(false, 'ROLE_REVOKE_ARGUMENTS_REQUIRED', 'tenant_id, actor_user_id, and role_code are required.', '{}'::jsonb);
  end if;

  update public.platform_actor_role_grant
  set grant_status = 'revoked',
      revoked_at = timezone('utc', now()),
      revoked_by = v_revoked_by,
      updated_at = timezone('utc', now())
  where tenant_id = v_tenant_id
    and actor_user_id = v_actor_user_id
    and role_code = v_role_code;

  if not found then
    return public.platform_json_response(false, 'ROLE_GRANT_NOT_FOUND', 'Role grant not found.', jsonb_build_object('tenant_id', v_tenant_id, 'actor_user_id', v_actor_user_id, 'role_code', v_role_code));
  end if;

  perform public.platform_identity_write_event(jsonb_build_object(
    'event_type', 'actor_role_revoked',
    'tenant_id', v_tenant_id,
    'actor_user_id', v_actor_user_id,
    'message', 'Actor role revoked.',
    'details', jsonb_build_object('role_code', v_role_code)
  ));

  return public.platform_json_response(true, 'OK', 'Actor role revoked.', jsonb_build_object(
    'tenant_id', v_tenant_id,
    'actor_user_id', v_actor_user_id,
    'role_code', v_role_code
  ));
end;
$function$;
create or replace function public.platform_issue_membership_invitation(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_invited_email text := nullif(lower(btrim(coalesce(p_params->>'invited_email', ''))), '');
  v_invited_mobile text := nullif(btrim(coalesce(p_params->>'invited_mobile', '')), '');
  v_role_code text := lower(btrim(coalesce(p_params->>'role_code', '')));
  v_expires_at timestamptz := coalesce((p_params->>'expires_at')::timestamptz, timezone('utc', now()) + interval '7 days');
  v_issued_by uuid := coalesce(public.platform_try_uuid(p_params->>'issued_by'), public.platform_resolve_actor());
  v_position_context jsonb := coalesce(p_params->'position_context', '{}'::jsonb);
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_existing uuid;
  v_row public.platform_membership_invitation%rowtype;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;
  if v_role_code = '' then
    return public.platform_json_response(false, 'ROLE_CODE_REQUIRED', 'role_code is required.', '{}'::jsonb);
  end if;
  if coalesce(v_invited_email, '') = '' and coalesce(v_invited_mobile, '') = '' then
    return public.platform_json_response(false, 'INVITATION_TARGET_REQUIRED', 'At least one invitation target is required.', '{}'::jsonb);
  end if;
  if not exists (
    select 1 from public.platform_access_role par where par.role_code = v_role_code and par.role_status = 'active'
  ) then
    return public.platform_json_response(false, 'ROLE_NOT_FOUND', 'Active role not found.', jsonb_build_object('role_code', v_role_code));
  end if;
  if jsonb_typeof(v_position_context) <> 'object' or jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'position_context and metadata must be JSON objects.', '{}'::jsonb);
  end if;

  select invitation_id into v_existing
  from public.platform_membership_invitation
  where tenant_id = v_tenant_id
    and role_code = v_role_code
    and invitation_status = 'pending'
    and coalesce(lower(invited_email), '') = coalesce(v_invited_email, '')
    and coalesce(invited_mobile, '') = coalesce(v_invited_mobile, '')
  limit 1;

  if v_existing is not null then
    return public.platform_json_response(false, 'INVITATION_ALREADY_PENDING', 'A pending invitation already exists.', jsonb_build_object('invitation_id', v_existing));
  end if;

  insert into public.platform_membership_invitation (
    tenant_id, invited_email, invited_mobile, role_code, invitation_status, expires_at, issued_by, position_context, metadata
  ) values (
    v_tenant_id, v_invited_email, v_invited_mobile, v_role_code, 'pending', v_expires_at, v_issued_by, v_position_context, v_metadata
  )
  returning * into v_row;

  perform public.platform_identity_write_event(jsonb_build_object(
    'event_type', 'membership_invitation_issued',
    'tenant_id', v_tenant_id,
    'invitation_id', v_row.invitation_id,
    'message', 'Membership invitation issued.',
    'details', jsonb_build_object('role_code', v_role_code)
  ));

  return public.platform_json_response(true, 'OK', 'Membership invitation issued.', jsonb_build_object(
    'invitation_id', v_row.invitation_id,
    'tenant_id', v_row.tenant_id,
    'role_code', v_row.role_code,
    'invitation_status', v_row.invitation_status,
    'expires_at', v_row.expires_at
  ));
end;
$function$;
create or replace function public.platform_revoke_membership_invitation(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_invitation_id uuid := public.platform_try_uuid(p_params->>'invitation_id');
  v_reason text := nullif(btrim(coalesce(p_params->>'reason', '')), '');
  v_row public.platform_membership_invitation%rowtype;
begin
  if v_invitation_id is null then
    return public.platform_json_response(false, 'INVITATION_ID_REQUIRED', 'invitation_id is required.', '{}'::jsonb);
  end if;

  select * into v_row
  from public.platform_membership_invitation
  where invitation_id = v_invitation_id;

  if not found then
    return public.platform_json_response(false, 'INVITATION_NOT_FOUND', 'Invitation not found.', jsonb_build_object('invitation_id', v_invitation_id));
  end if;
  if v_row.invitation_status <> 'pending' then
    return public.platform_json_response(false, 'INVITATION_NOT_PENDING', 'Only pending invitations can be revoked.', jsonb_build_object('invitation_status', v_row.invitation_status));
  end if;

  update public.platform_membership_invitation
  set invitation_status = 'revoked',
      metadata = metadata || jsonb_build_object('revoke_reason', v_reason),
      updated_at = timezone('utc', now())
  where invitation_id = v_invitation_id;

  perform public.platform_identity_write_event(jsonb_build_object(
    'event_type', 'membership_invitation_revoked',
    'tenant_id', v_row.tenant_id,
    'invitation_id', v_row.invitation_id,
    'message', 'Membership invitation revoked.',
    'details', jsonb_build_object('reason', v_reason)
  ));

  return public.platform_json_response(true, 'OK', 'Membership invitation revoked.', jsonb_build_object(
    'invitation_id', v_invitation_id,
    'invitation_status', 'revoked'
  ));
end;
$function$;
create or replace function public.platform_register_signup_request(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_email text := nullif(lower(btrim(coalesce(p_params->>'email', ''))), '');
  v_mobile_no text := nullif(btrim(coalesce(p_params->>'mobile_no', '')), '');
  v_role_code text := nullif(lower(btrim(coalesce(p_params->>'role_code', ''))), '');
  v_status_token_hash text := nullif(btrim(coalesce(p_params->>'status_token_hash', '')), '');
  v_source_ip text := nullif(btrim(coalesce(p_params->>'source_ip', '')), '');
  v_user_agent text := nullif(btrim(coalesce(p_params->>'user_agent', '')), '');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_match_count integer := 0;
  v_invitation public.platform_membership_invitation%rowtype;
  v_request_status text := 'received';
  v_decision_reason text := null;
  v_row public.platform_signup_request%rowtype;
begin
  if v_email is null or v_mobile_no is null or v_status_token_hash is null then
    return public.platform_json_response(false, 'SIGNUP_REQUEST_ARGUMENTS_REQUIRED', 'email, mobile_no, and status_token_hash are required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  select count(*) into v_match_count
  from public.platform_membership_invitation pmi
  where pmi.invitation_status = 'pending'
    and (pmi.expires_at is null or pmi.expires_at > timezone('utc', now()))
    and coalesce(lower(pmi.invited_email), '') = v_email
    and coalesce(pmi.invited_mobile, '') = v_mobile_no
    and (v_role_code is null or pmi.role_code = v_role_code);

  if v_match_count = 1 then
    select * into v_invitation
    from public.platform_membership_invitation pmi
    where pmi.invitation_status = 'pending'
      and (pmi.expires_at is null or pmi.expires_at > timezone('utc', now()))
      and coalesce(lower(pmi.invited_email), '') = v_email
      and coalesce(pmi.invited_mobile, '') = v_mobile_no
      and (v_role_code is null or pmi.role_code = v_role_code)
    limit 1;
  elsif v_match_count = 0 then
    v_request_status := 'denied';
    v_decision_reason := 'INVITATION_NOT_FOUND';
  else
    v_request_status := 'denied';
    v_decision_reason := 'INVITATION_AMBIGUOUS';
  end if;

  insert into public.platform_signup_request (
    invitation_id, email, mobile_no, request_status, status_token_hash, source_ip, user_agent, decision_reason, metadata
  ) values (
    v_invitation.invitation_id, v_email, v_mobile_no, v_request_status, v_status_token_hash, v_source_ip, v_user_agent, v_decision_reason, v_metadata
  )
  returning * into v_row;

  perform public.platform_identity_write_event(jsonb_build_object(
    'event_type', 'signup_request_registered',
    'tenant_id', v_invitation.tenant_id,
    'invitation_id', v_invitation.invitation_id,
    'signup_request_id', v_row.signup_request_id,
    'message', 'Signup request registered.',
    'details', jsonb_build_object('request_status', v_request_status, 'decision_reason', v_decision_reason)
  ));

  return public.platform_json_response(true, 'OK', 'Signup request registered.', jsonb_build_object(
    'signup_request_id', v_row.signup_request_id,
    'request_status', v_row.request_status,
    'decision_reason', v_row.decision_reason,
    'invitation_id', v_row.invitation_id
  ));
exception
  when unique_violation then
    return public.platform_json_response(false, 'STATUS_TOKEN_HASH_DUPLICATE', 'status_token_hash already exists.', '{}'::jsonb);
end;
$function$;
create or replace function public.platform_get_signup_request_status(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_status_token_hash text := nullif(btrim(coalesce(p_params->>'status_token_hash', '')), '');
  v_signup_request_id uuid := coalesce(public.platform_try_uuid(p_params->>'signup_request_id'), public.platform_try_uuid(p_params->>'request_id'));
  v_row public.platform_signup_request%rowtype;
begin
  if v_status_token_hash is null then
    return public.platform_json_response(false, 'STATUS_TOKEN_HASH_REQUIRED', 'status_token_hash is required.', '{}'::jsonb);
  end if;

  select * into v_row
  from public.platform_signup_request
  where status_token_hash = v_status_token_hash
    and (v_signup_request_id is null or signup_request_id = v_signup_request_id);

  if not found then
    return public.platform_json_response(false, 'SIGNUP_REQUEST_NOT_FOUND', 'Signup request not found.', '{}'::jsonb);
  end if;

  return public.platform_json_response(true, 'OK', 'Signup request status resolved.', jsonb_build_object(
    'signup_request_id', v_row.signup_request_id,
    'request_status', v_row.request_status,
    'decision_reason', v_row.decision_reason,
    'created_at', v_row.created_at,
    'updated_at', v_row.updated_at,
    'completed_at', v_row.completed_at,
    'invitation_id', v_row.invitation_id
  ));
end;
$function$;
create or replace function public.platform_check_signup_rate_limit(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_source_ip text := nullif(btrim(coalesce(p_params->>'source_ip', '')), '');
  v_email text := nullif(lower(btrim(coalesce(p_params->>'email', ''))), '');
  v_mobile_no text := nullif(btrim(coalesce(p_params->>'mobile_no', '')), '');
  v_ip_window_minutes integer := greatest(coalesce((p_params->>'ip_window_minutes')::integer, 15), 1);
  v_ip_max_requests integer := greatest(coalesce((p_params->>'ip_max_requests')::integer, 10), 1);
  v_identity_window_minutes integer := greatest(coalesce((p_params->>'identity_window_minutes')::integer, 60), 1);
  v_identity_max_requests integer := greatest(coalesce((p_params->>'identity_max_requests')::integer, 5), 1);
  v_ip_count integer := 0;
  v_identity_count integer := 0;
  v_decision_reason text := null;
begin
  if v_email is null or v_mobile_no is null then
    return public.platform_json_response(false, 'SIGNUP_RATE_LIMIT_ARGUMENTS_REQUIRED', 'email and mobile_no are required.', '{}'::jsonb);
  end if;

  if v_source_ip is not null then
    select count(*) into v_ip_count
    from public.platform_signup_request
    where source_ip = v_source_ip
      and created_at > timezone('utc', now()) - make_interval(mins => v_ip_window_minutes);

    if v_ip_count >= v_ip_max_requests then
      v_decision_reason := 'IP_RATE_LIMIT';
    end if;
  end if;

  select count(*) into v_identity_count
  from public.platform_signup_request
  where lower(email) = v_email
    and mobile_no = v_mobile_no
    and created_at > timezone('utc', now()) - make_interval(mins => v_identity_window_minutes);

  if v_decision_reason is null and v_identity_count >= v_identity_max_requests then
    v_decision_reason := 'IDENTITY_RATE_LIMIT';
  end if;

  return public.platform_json_response(true, 'OK', 'Signup rate limit evaluated.', jsonb_build_object(
    'is_allowed', v_decision_reason is null,
    'decision_reason', v_decision_reason,
    'ip_count', v_ip_count,
    'ip_max_requests', v_ip_max_requests,
    'identity_count', v_identity_count,
    'identity_max_requests', v_identity_max_requests
  ));
end;
$function$;
create or replace function public.platform_update_signup_request_status(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_signup_request_id uuid := coalesce(public.platform_try_uuid(p_params->>'signup_request_id'), public.platform_try_uuid(p_params->>'request_id'));
  v_request_status text := lower(btrim(coalesce(p_params->>'request_status', '')));
  v_decision_reason text := nullif(btrim(coalesce(p_params->>'decision_reason', '')), '');
  v_async_job_id uuid := public.platform_try_uuid(p_params->>'async_job_id');
  v_metadata_patch jsonb := coalesce(p_params->'metadata_patch', '{}'::jsonb);
  v_row public.platform_signup_request%rowtype;
begin
  if v_signup_request_id is null then
    return public.platform_json_response(false, 'SIGNUP_REQUEST_ID_REQUIRED', 'signup_request_id is required.', '{}'::jsonb);
  end if;
  if v_request_status not in ('received', 'queued', 'processing', 'completed', 'denied', 'failed') then
    return public.platform_json_response(false, 'INVALID_SIGNUP_REQUEST_STATUS', 'request_status is invalid.', jsonb_build_object('request_status', v_request_status));
  end if;
  if jsonb_typeof(v_metadata_patch) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA_PATCH', 'metadata_patch must be a JSON object.', '{}'::jsonb);
  end if;

  update public.platform_signup_request
  set request_status = v_request_status,
      decision_reason = coalesce(v_decision_reason, decision_reason),
      async_job_id = coalesce(v_async_job_id, async_job_id),
      metadata = metadata || v_metadata_patch,
      completed_at = case when v_request_status in ('completed', 'denied', 'failed') then coalesce(completed_at, timezone('utc', now())) else completed_at end,
      updated_at = timezone('utc', now())
  where signup_request_id = v_signup_request_id
  returning * into v_row;

  if not found then
    return public.platform_json_response(false, 'SIGNUP_REQUEST_NOT_FOUND', 'Signup request not found.', jsonb_build_object('signup_request_id', v_signup_request_id));
  end if;

  perform public.platform_identity_write_event(jsonb_build_object(
    'event_type', 'signup_request_status_updated',
    'signup_request_id', v_signup_request_id,
    'message', 'Signup request status updated.',
    'details', jsonb_build_object('request_status', v_request_status, 'decision_reason', v_decision_reason)
  ));

  return public.platform_json_response(true, 'OK', 'Signup request status updated.', jsonb_build_object(
    'signup_request_id', v_row.signup_request_id,
    'request_status', v_row.request_status,
    'decision_reason', v_row.decision_reason,
    'async_job_id', v_row.async_job_id
  ));
end;
$function$;
create or replace function public.platform_check_signin_rate_limit(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_identifier text := nullif(lower(btrim(coalesce(p_params->>'identifier', ''))), '');
  v_identifier_type text := lower(coalesce(nullif(p_params->>'identifier_type', ''), 'email'));
  v_window_minutes integer := greatest(coalesce((p_params->>'window_minutes')::integer, 15), 1);
  v_max_attempts integer := greatest(coalesce((p_params->>'max_attempts')::integer, 5), 1);
  v_failure_count integer := 0;
begin
  if v_identifier is null then
    return public.platform_json_response(false, 'IDENTIFIER_REQUIRED', 'identifier is required.', '{}'::jsonb);
  end if;
  if v_identifier_type not in ('email', 'mobile', 'ip') then
    return public.platform_json_response(false, 'INVALID_IDENTIFIER_TYPE', 'identifier_type is invalid.', jsonb_build_object('identifier_type', v_identifier_type));
  end if;

  select count(*) into v_failure_count
  from public.platform_signin_attempt_log
  where identifier = v_identifier
    and identifier_type = v_identifier_type
    and attempt_result in ('failed_credentials', 'failed_policy', 'failed_rate_limit', 'failed_otp')
    and created_at > timezone('utc', now()) - make_interval(mins => v_window_minutes);

  return public.platform_json_response(true, 'OK', 'Signin rate limit evaluated.', jsonb_build_object(
    'is_allowed', v_failure_count < v_max_attempts,
    'attempts_remaining', greatest(0, v_max_attempts - v_failure_count),
    'failure_count', v_failure_count,
    'window_minutes', v_window_minutes
  ));
end;
$function$;
create or replace function public.platform_get_signin_policy(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_policy_code text := lower(btrim(coalesce(nullif(p_params->>'policy_code', ''), nullif(p_params->>'configId', ''))));
  v_row public.platform_signin_policy%rowtype;
begin
  if v_policy_code = '' then
    return public.platform_json_response(false, 'POLICY_CODE_REQUIRED', 'policy_code is required.', '{}'::jsonb);
  end if;

  select * into v_row
  from public.platform_signin_policy
  where policy_code = v_policy_code
    and policy_status = 'active';

  if not found then
    return public.platform_json_response(false, 'SIGNIN_POLICY_NOT_FOUND', 'Active signin policy not found.', jsonb_build_object('policy_code', v_policy_code));
  end if;

  return public.platform_json_response(true, 'OK', 'Signin policy resolved.', jsonb_build_object(
    'policy_code', v_row.policy_code,
    'entrypoint_code', v_row.entrypoint_code,
    'requires_password', v_row.requires_password,
    'requires_otp', v_row.requires_otp,
    'allowed_role_codes', v_row.allowed_role_codes,
    'allowed_membership_statuses', v_row.allowed_membership_statuses
  ));
end;
$function$;
create or replace function public.platform_record_signin_attempt(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_identifier_type text := lower(coalesce(nullif(p_params->>'identifier_type', ''), 'email'));
  v_identifier text := nullif(btrim(coalesce(p_params->>'identifier', '')), '');
  v_policy_code text := nullif(lower(btrim(coalesce(p_params->>'policy_code', ''))), '');
  v_attempt_result text := lower(btrim(coalesce(p_params->>'attempt_result', '')));
  v_source_ip text := nullif(btrim(coalesce(p_params->>'source_ip', '')), '');
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
begin
  if v_identifier is null then
    return public.platform_json_response(false, 'IDENTIFIER_REQUIRED', 'identifier is required.', '{}'::jsonb);
  end if;
  if v_identifier_type not in ('email', 'mobile', 'ip') then
    return public.platform_json_response(false, 'INVALID_IDENTIFIER_TYPE', 'identifier_type is invalid.', jsonb_build_object('identifier_type', v_identifier_type));
  end if;
  if v_attempt_result not in ('allowed', 'failed_credentials', 'failed_policy', 'failed_rate_limit', 'failed_otp', 'succeeded') then
    return public.platform_json_response(false, 'INVALID_ATTEMPT_RESULT', 'attempt_result is invalid.', jsonb_build_object('attempt_result', v_attempt_result));
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  if v_identifier_type = 'email' then
    v_identifier := lower(v_identifier);
  end if;

  insert into public.platform_signin_attempt_log (
    identifier, identifier_type, policy_code, attempt_result, source_ip, actor_user_id, metadata
  ) values (
    v_identifier, v_identifier_type, v_policy_code, v_attempt_result, v_source_ip, v_actor_user_id, v_metadata
  );

  return public.platform_json_response(true, 'OK', 'Signin attempt recorded.', jsonb_build_object(
    'identifier', v_identifier,
    'identifier_type', v_identifier_type,
    'attempt_result', v_attempt_result
  ));
end;
$function$;
create or replace function public.platform_issue_signin_challenge(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_policy_code text := lower(btrim(coalesce(p_params->>'policy_code', '')));
  v_challenge_token_hash text := nullif(btrim(coalesce(p_params->>'challenge_token_hash', '')), '');
  v_source_ip text := nullif(btrim(coalesce(p_params->>'source_ip', '')), '');
  v_expires_at timestamptz := coalesce((p_params->>'expires_at')::timestamptz, timezone('utc', now()) + interval '5 minutes');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_row public.platform_signin_challenge%rowtype;
begin
  if v_actor_user_id is null or v_policy_code = '' or v_challenge_token_hash is null then
    return public.platform_json_response(false, 'SIGNIN_CHALLENGE_ARGUMENTS_REQUIRED', 'actor_user_id, policy_code, and challenge_token_hash are required.', '{}'::jsonb);
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;
  if not exists (
    select 1 from public.platform_signin_policy psp
    where psp.policy_code = v_policy_code and psp.policy_status = 'active'
  ) then
    return public.platform_json_response(false, 'SIGNIN_POLICY_NOT_FOUND', 'Active signin policy not found.', jsonb_build_object('policy_code', v_policy_code));
  end if;

  insert into public.platform_signin_challenge (
    actor_user_id, policy_code, challenge_status, challenge_token_hash, source_ip, expires_at, metadata
  ) values (
    v_actor_user_id, v_policy_code, 'issued', v_challenge_token_hash, v_source_ip, v_expires_at, v_metadata
  )
  returning * into v_row;

  if v_source_ip is not null then
    insert into public.platform_signin_attempt_log (
      identifier, identifier_type, policy_code, attempt_result, source_ip, actor_user_id, metadata
    ) values (
      v_source_ip, 'ip', v_policy_code, 'allowed', v_source_ip, v_actor_user_id, '{}'::jsonb
    );
  end if;

  return public.platform_json_response(true, 'OK', 'Signin challenge issued.', jsonb_build_object(
    'challenge_id', v_row.challenge_id,
    'actor_user_id', v_row.actor_user_id,
    'policy_code', v_row.policy_code,
    'expires_at', v_row.expires_at
  ));
exception
  when unique_violation then
    return public.platform_json_response(false, 'CHALLENGE_TOKEN_HASH_DUPLICATE', 'challenge_token_hash already exists.', '{}'::jsonb);
end;
$function$;
create or replace function public.platform_consume_signin_challenge(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_challenge_token_hash text := nullif(btrim(coalesce(p_params->>'challenge_token_hash', '')), '');
  v_row record;
begin
  if v_challenge_token_hash is null then
    return public.platform_json_response(false, 'CHALLENGE_TOKEN_HASH_REQUIRED', 'challenge_token_hash is required.', '{}'::jsonb);
  end if;

  update public.platform_signin_challenge
  set challenge_status = 'consumed',
      consumed_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where challenge_token_hash = v_challenge_token_hash
    and challenge_status = 'issued'
    and expires_at > timezone('utc', now())
  returning challenge_id, actor_user_id, policy_code, expires_at, metadata into v_row;

  if v_row.challenge_id is null then
    if exists (
      select 1 from public.platform_signin_challenge
      where challenge_token_hash = v_challenge_token_hash and challenge_status = 'consumed'
    ) then
      return public.platform_json_response(false, 'CHALLENGE_ALREADY_CONSUMED', 'Signin challenge already consumed.', '{}'::jsonb);
    end if;
    return public.platform_json_response(false, 'CHALLENGE_INVALID_OR_EXPIRED', 'Signin challenge is invalid or expired.', '{}'::jsonb);
  end if;

  return public.platform_json_response(true, 'OK', 'Signin challenge consumed.', jsonb_build_object(
    'challenge_id', v_row.challenge_id,
    'actor_user_id', v_row.actor_user_id,
    'policy_code', v_row.policy_code,
    'metadata', coalesce(v_row.metadata, '{}'::jsonb)
  ));
end;
$function$;
create or replace function public.platform_mark_actor_signin_success(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
begin
  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
  end if;

  update public.platform_actor_profile
  set last_signin_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where actor_user_id = v_actor_user_id;

  perform public.platform_identity_write_event(jsonb_build_object(
    'event_type', 'actor_signin_succeeded',
    'tenant_id', v_tenant_id,
    'actor_user_id', v_actor_user_id,
    'message', 'Actor signin succeeded.',
    'details', '{}'::jsonb
  ));

  return public.platform_json_response(true, 'OK', 'Actor signin marked successful.', jsonb_build_object(
    'actor_user_id', v_actor_user_id,
    'tenant_id', v_tenant_id
  ));
end;
$function$;
create or replace function public.platform_complete_invited_signup(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_signup_request_id uuid := public.platform_try_uuid(p_params->>'signup_request_id');
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_email text := nullif(lower(btrim(coalesce(p_params->>'email', ''))), '');
  v_mobile_no text := nullif(btrim(coalesce(p_params->>'mobile_no', '')), '');
  v_display_name text := nullif(btrim(coalesce(p_params->>'display_name', '')), '');
  v_signup_request public.platform_signup_request%rowtype;
  v_invitation public.platform_membership_invitation%rowtype;
  v_gate jsonb;
  v_gate_details jsonb;
  v_membership_result jsonb;
  v_role_result jsonb;
begin
  if v_signup_request_id is null or v_actor_user_id is null or v_email is null or v_mobile_no is null then
    return public.platform_json_response(false, 'SIGNUP_COMPLETION_ARGUMENTS_REQUIRED', 'signup_request_id, actor_user_id, email, and mobile_no are required.', '{}'::jsonb);
  end if;

  select * into v_signup_request
  from public.platform_signup_request
  where signup_request_id = v_signup_request_id;

  if not found then
    return public.platform_json_response(false, 'SIGNUP_REQUEST_NOT_FOUND', 'Signup request not found.', jsonb_build_object('signup_request_id', v_signup_request_id));
  end if;
  if v_signup_request.request_status not in ('received', 'queued', 'processing') then
    return public.platform_json_response(false, 'SIGNUP_REQUEST_NOT_COMPLETABLE', 'Signup request is not completable.', jsonb_build_object('request_status', v_signup_request.request_status));
  end if;
  if v_signup_request.invitation_id is null then
    return public.platform_json_response(false, 'SIGNUP_REQUEST_NOT_INVITED', 'Signup request has no bound invitation.', jsonb_build_object('signup_request_id', v_signup_request_id));
  end if;

  select * into v_invitation
  from public.platform_membership_invitation
  where invitation_id = v_signup_request.invitation_id
  for update;

  if not found then
    return public.platform_json_response(false, 'INVITATION_NOT_FOUND', 'Invitation not found.', jsonb_build_object('invitation_id', v_signup_request.invitation_id));
  end if;
  if v_invitation.invitation_status <> 'pending' then
    return public.platform_json_response(false, 'INVITATION_NOT_PENDING', 'Invitation is not pending.', jsonb_build_object('invitation_status', v_invitation.invitation_status));
  end if;
  if v_invitation.expires_at is not null and v_invitation.expires_at <= timezone('utc', now()) then
    update public.platform_membership_invitation
    set invitation_status = 'expired',
        updated_at = timezone('utc', now())
    where invitation_id = v_invitation.invitation_id;
    return public.platform_json_response(false, 'INVITATION_EXPIRED', 'Invitation has expired.', jsonb_build_object('invitation_id', v_invitation.invitation_id));
  end if;
  if coalesce(lower(v_invitation.invited_email), '') <> v_email or coalesce(v_invitation.invited_mobile, '') <> v_mobile_no then
    return public.platform_json_response(false, 'INVITATION_IDENTITY_MISMATCH', 'Signup identity does not match the invitation.', '{}'::jsonb);
  end if;

  v_gate := public.platform_get_tenant_access_gate(jsonb_build_object('tenant_id', v_invitation.tenant_id));
  if coalesce((v_gate->>'success')::boolean, false) = false then
    return v_gate;
  end if;
  v_gate_details := coalesce(v_gate->'details', '{}'::jsonb);
  if coalesce((v_gate_details->>'ready_for_routing')::boolean, false) = false then
    return public.platform_json_response(false, 'TENANT_NOT_READY_FOR_ROUTING', 'Tenant is not ready for routing.', v_gate_details);
  end if;
  if coalesce((v_gate_details->>'client_access_allowed')::boolean, false) = false then
    return public.platform_json_response(false, coalesce(nullif(v_gate_details->>'reason_code', ''), 'TENANT_ACCESS_BLOCKED_DORMANT'), 'Client access is blocked for the tenant.', v_gate_details);
  end if;

  perform public.platform_upsert_actor_profile(jsonb_build_object(
    'actor_user_id', v_actor_user_id,
    'primary_email', v_email,
    'primary_mobile', v_mobile_no,
    'display_name', v_display_name,
    'profile_status', 'active',
    'created_via', 'invited_signup',
    'email_verified', true,
    'metadata', jsonb_build_object('signup_request_id', v_signup_request_id)
  ));

  v_membership_result := public.platform_register_actor_tenant_membership(jsonb_build_object(
    'tenant_id', v_invitation.tenant_id,
    'actor_user_id', v_actor_user_id,
    'membership_status', 'active',
    'routing_status', 'enabled',
    'metadata', jsonb_build_object('source', 'invited_signup', 'invitation_id', v_invitation.invitation_id)
  ));
  if coalesce((v_membership_result->>'success')::boolean, false) = false then
    return v_membership_result;
  end if;

  v_role_result := public.platform_assign_actor_role(jsonb_build_object(
    'tenant_id', v_invitation.tenant_id,
    'actor_user_id', v_actor_user_id,
    'role_code', v_invitation.role_code,
    'grant_status', 'active',
    'metadata', jsonb_build_object('source', 'invited_signup', 'invitation_id', v_invitation.invitation_id)
  ));
  if coalesce((v_role_result->>'success')::boolean, false) = false then
    return v_role_result;
  end if;

  update public.platform_membership_invitation
  set invitation_status = 'claimed',
      claimed_at = timezone('utc', now()),
      claimed_by_user_id = v_actor_user_id,
      updated_at = timezone('utc', now())
  where invitation_id = v_invitation.invitation_id;

  update public.platform_signup_request
  set request_status = 'completed',
      completed_at = timezone('utc', now()),
      decision_reason = 'SIGNUP_COMPLETED',
      updated_at = timezone('utc', now())
  where signup_request_id = v_signup_request_id;

  perform public.platform_identity_write_event(jsonb_build_object(
    'event_type', 'invited_signup_completed',
    'tenant_id', v_invitation.tenant_id,
    'actor_user_id', v_actor_user_id,
    'invitation_id', v_invitation.invitation_id,
    'signup_request_id', v_signup_request_id,
    'message', 'Invited signup completed.',
    'details', jsonb_build_object('role_code', v_invitation.role_code)
  ));

  return public.platform_json_response(true, 'OK', 'Invited signup completed.', jsonb_build_object(
    'signup_request_id', v_signup_request_id,
    'tenant_id', v_invitation.tenant_id,
    'actor_user_id', v_actor_user_id,
    'role_code', v_invitation.role_code,
    'invitation_id', v_invitation.invitation_id
  ));
end;
$function$;
create or replace function public.platform_get_actor_access_context(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_resolve_actor());
  v_profile jsonb;
  v_memberships jsonb;
begin
  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
  end if;

  select to_jsonb(pap) into v_profile
  from public.platform_actor_profile pap
  where pap.actor_user_id = v_actor_user_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'tenant_id', s.tenant_id,
    'tenant_code', s.tenant_code,
    'schema_name', s.schema_name,
    'membership_status', s.membership_status,
    'routing_status', s.routing_status,
    'is_default_tenant', s.is_default_tenant,
    'access_state', s.access_state,
    'client_access_allowed', s.client_access_allowed,
    'background_processing_allowed', s.background_processing_allowed,
    'active_role_codes', s.active_role_codes
  ) order by s.is_default_tenant desc, s.tenant_code asc), '[]'::jsonb)
  into v_memberships
  from public.platform_rm_actor_access_overview s
  where s.actor_user_id = v_actor_user_id;

  return public.platform_json_response(true, 'OK', 'Actor access context resolved.', jsonb_build_object(
    'actor_user_id', v_actor_user_id,
    'profile', coalesce(v_profile, '{}'::jsonb),
    'memberships', v_memberships
  ));
end;
$function$;
revoke all on public.platform_actor_profile from public, anon, authenticated;
revoke all on public.platform_access_role from public, anon, authenticated;
revoke all on public.platform_actor_role_grant from public, anon, authenticated;
revoke all on public.platform_membership_invitation from public, anon, authenticated;
revoke all on public.platform_signup_request from public, anon, authenticated;
revoke all on public.platform_signin_policy from public, anon, authenticated;
revoke all on public.platform_signin_challenge from public, anon, authenticated;
revoke all on public.platform_signin_attempt_log from public, anon, authenticated;
revoke all on public.platform_identity_event_log from public, anon, authenticated;
revoke all on public.platform_rm_actor_access_overview from public, anon, authenticated;
revoke all on public.platform_rm_membership_invitation_overview from public, anon, authenticated;
revoke all on public.platform_rm_signup_request_status from public, anon, authenticated;
revoke all on function public.platform_identity_write_event(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_actor_profile(jsonb) from public, anon, authenticated;
revoke all on function public.platform_assign_actor_role(jsonb) from public, anon, authenticated;
revoke all on function public.platform_revoke_actor_role(jsonb) from public, anon, authenticated;
revoke all on function public.platform_issue_membership_invitation(jsonb) from public, anon, authenticated;
revoke all on function public.platform_revoke_membership_invitation(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_signup_request(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_signup_request_status(jsonb) from public, anon, authenticated;
revoke all on function public.platform_check_signup_rate_limit(jsonb) from public, anon, authenticated;
revoke all on function public.platform_update_signup_request_status(jsonb) from public, anon, authenticated;
revoke all on function public.platform_check_signin_rate_limit(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_signin_policy(jsonb) from public, anon, authenticated;
revoke all on function public.platform_record_signin_attempt(jsonb) from public, anon, authenticated;
revoke all on function public.platform_issue_signin_challenge(jsonb) from public, anon, authenticated;
revoke all on function public.platform_consume_signin_challenge(jsonb) from public, anon, authenticated;
revoke all on function public.platform_mark_actor_signin_success(jsonb) from public, anon, authenticated;
revoke all on function public.platform_complete_invited_signup(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_actor_access_context(jsonb) from public, anon, authenticated;
grant select on public.platform_rm_actor_access_overview to service_role;
grant select on public.platform_rm_membership_invitation_overview to service_role;
grant select on public.platform_rm_signup_request_status to service_role;
grant execute on function public.platform_identity_write_event(jsonb) to service_role;
grant execute on function public.platform_upsert_actor_profile(jsonb) to service_role;
grant execute on function public.platform_assign_actor_role(jsonb) to service_role;
grant execute on function public.platform_revoke_actor_role(jsonb) to service_role;
grant execute on function public.platform_issue_membership_invitation(jsonb) to service_role;
grant execute on function public.platform_revoke_membership_invitation(jsonb) to service_role;
grant execute on function public.platform_register_signup_request(jsonb) to service_role;
grant execute on function public.platform_get_signup_request_status(jsonb) to service_role;
grant execute on function public.platform_check_signup_rate_limit(jsonb) to service_role;
grant execute on function public.platform_update_signup_request_status(jsonb) to service_role;
grant execute on function public.platform_check_signin_rate_limit(jsonb) to service_role;
grant execute on function public.platform_get_signin_policy(jsonb) to service_role;
grant execute on function public.platform_record_signin_attempt(jsonb) to service_role;
grant execute on function public.platform_issue_signin_challenge(jsonb) to service_role;
grant execute on function public.platform_consume_signin_challenge(jsonb) to service_role;
grant execute on function public.platform_mark_actor_signin_success(jsonb) to service_role;
grant execute on function public.platform_complete_invited_signup(jsonb) to service_role;
grant execute on function public.platform_get_actor_access_context(jsonb) to service_role;
