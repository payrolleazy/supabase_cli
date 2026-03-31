set search_path = public, pg_temp;

create table if not exists public.rcm_requisition (
  requisition_id uuid primary key default gen_random_uuid(),
  requisition_code text not null,
  requisition_title text not null,
  position_id bigint not null,
  requisition_status text not null default 'open'
    check (requisition_status in ('draft', 'open', 'on_hold', 'closed', 'cancelled', 'filled')),
  openings_count integer not null default 1,
  priority_code text null,
  target_start_date date null,
  description text null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint rcm_requisition_code_check check (btrim(requisition_code) <> ''),
  constraint rcm_requisition_title_check check (btrim(requisition_title) <> ''),
  constraint rcm_requisition_openings_count_check check (openings_count > 0)
);

create unique index if not exists uq_rcm_requisition_code_lower
on public.rcm_requisition (lower(requisition_code));

create index if not exists idx_rcm_requisition_position_id
on public.rcm_requisition (position_id);

create index if not exists idx_rcm_requisition_status
on public.rcm_requisition (requisition_status);

create table if not exists public.rcm_candidate (
  candidate_id uuid primary key default gen_random_uuid(),
  candidate_code text not null,
  first_name text not null,
  middle_name text null,
  last_name text not null,
  primary_email text not null,
  primary_phone text null,
  source_code text null,
  candidate_status text not null default 'active'
    check (candidate_status in ('prospect', 'active', 'withdrawn', 'rejected', 'converted', 'archived')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint rcm_candidate_code_check check (btrim(candidate_code) <> ''),
  constraint rcm_candidate_first_name_check check (btrim(first_name) <> ''),
  constraint rcm_candidate_last_name_check check (btrim(last_name) <> ''),
  constraint rcm_candidate_primary_email_check check (btrim(primary_email) <> '')
);

create unique index if not exists uq_rcm_candidate_code_lower
on public.rcm_candidate (lower(candidate_code));

create unique index if not exists uq_rcm_candidate_primary_email_lower
on public.rcm_candidate (lower(primary_email));

create index if not exists idx_rcm_candidate_status
on public.rcm_candidate (candidate_status);

create table if not exists public.rcm_job_application (
  application_id uuid primary key default gen_random_uuid(),
  requisition_id uuid not null,
  candidate_id uuid not null,
  current_stage_code text not null default 'applied',
  application_status text not null default 'active'
    check (application_status in ('active', 'rejected', 'withdrawn', 'converted', 'cancelled')),
  applied_on date not null default current_date,
  converted_at timestamptz null,
  rejected_at timestamptz null,
  withdrawn_at timestamptz null,
  application_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint rcm_job_application_stage_check check (btrim(current_stage_code) <> ''),
  constraint rcm_job_application_metadata_check check (jsonb_typeof(application_metadata) = 'object'),
  constraint uq_rcm_job_application_pair unique (requisition_id, candidate_id)
);

create index if not exists idx_rcm_job_application_requisition_id
on public.rcm_job_application (requisition_id);

create index if not exists idx_rcm_job_application_candidate_id
on public.rcm_job_application (candidate_id);

create index if not exists idx_rcm_job_application_status_stage
on public.rcm_job_application (application_status, current_stage_code);

create table if not exists public.rcm_application_stage_event (
  application_stage_event_id bigint generated always as identity primary key,
  application_id uuid not null,
  prior_stage_code text null,
  new_stage_code text not null,
  stage_outcome text not null default 'progressed'
    check (stage_outcome in ('progressed', 'rejected', 'withdrawn', 'converted', 'returned')),
  event_reason text null,
  event_details jsonb not null default '{}'::jsonb,
  actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint rcm_application_stage_event_stage_check check (btrim(new_stage_code) <> ''),
  constraint rcm_application_stage_event_details_check check (jsonb_typeof(event_details) = 'object')
);

create index if not exists idx_rcm_application_stage_event_application_created
on public.rcm_application_stage_event (application_id, created_at desc, application_stage_event_id desc);

create index if not exists idx_rcm_application_stage_event_outcome_created
on public.rcm_application_stage_event (stage_outcome, created_at desc);

create table if not exists public.rcm_conversion_case (
  conversion_case_id uuid primary key default gen_random_uuid(),
  application_id uuid not null,
  candidate_id uuid not null,
  requisition_id uuid not null,
  target_position_id bigint not null,
  conversion_status text not null default 'pending_validation'
    check (conversion_status in ('pending_validation', 'ready', 'converted', 'cancelled', 'failed')),
  prepared_at timestamptz not null default timezone('utc', now()),
  converted_at timestamptz null,
  wcm_employee_id uuid null,
  conversion_notes jsonb not null default '{}'::jsonb,
  last_validation_payload jsonb not null default '{}'::jsonb,
  prepared_by_actor_user_id uuid null,
  converted_by_actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint uq_rcm_conversion_case_application unique (application_id),
  constraint rcm_conversion_case_notes_check check (jsonb_typeof(conversion_notes) = 'object'),
  constraint rcm_conversion_case_validation_payload_check check (jsonb_typeof(last_validation_payload) = 'object')
);

create index if not exists idx_rcm_conversion_case_status
on public.rcm_conversion_case (conversion_status, prepared_at desc);

create index if not exists idx_rcm_conversion_case_candidate_id
on public.rcm_conversion_case (candidate_id);

create index if not exists idx_rcm_conversion_case_position_id
on public.rcm_conversion_case (target_position_id);

create table if not exists public.rcm_conversion_event_log (
  conversion_event_log_id bigint generated always as identity primary key,
  conversion_case_id uuid not null,
  event_type text not null,
  event_details jsonb not null default '{}'::jsonb,
  actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint rcm_conversion_event_log_type_check check (btrim(event_type) <> ''),
  constraint rcm_conversion_event_log_details_check check (jsonb_typeof(event_details) = 'object')
);

create index if not exists idx_rcm_conversion_event_log_case_created
on public.rcm_conversion_event_log (conversion_case_id, created_at desc, conversion_event_log_id desc);

create or replace function public.platform_rcm_module_template_version()
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select 'recruitment_and_conversion_v1'::text;
$function$;

create or replace function public.platform_rcm_try_date(p_value text)
returns date
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $function$
begin
  if nullif(btrim(coalesce(p_value, '')), '') is null then
    return null;
  end if;

  return p_value::date;
exception
  when others then
    return null;
end;
$function$;

create or replace function public.platform_rcm_try_integer(p_value text)
returns integer
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $function$
begin
  if nullif(btrim(coalesce(p_value, '')), '') is null then
    return null;
  end if;

  return p_value::integer;
exception
  when others then
    return null;
end;
$function$;;
