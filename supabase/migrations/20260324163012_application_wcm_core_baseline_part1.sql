set search_path = public, pg_temp;

create table if not exists public.wcm_employee (
  employee_id uuid primary key default gen_random_uuid(),
  employee_code text not null,
  first_name text not null,
  middle_name text null,
  last_name text not null,
  official_email text not null,
  actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_employee_code_check check (btrim(employee_code) <> ''),
  constraint wcm_employee_first_name_check check (btrim(first_name) <> ''),
  constraint wcm_employee_last_name_check check (btrim(last_name) <> ''),
  constraint wcm_employee_official_email_check check (btrim(official_email) <> '')
);

create unique index if not exists uq_wcm_employee_code
on public.wcm_employee (employee_code);

create unique index if not exists uq_wcm_employee_official_email_lower
on public.wcm_employee (lower(official_email));

create unique index if not exists uq_wcm_employee_actor_user_id
on public.wcm_employee (actor_user_id)
where actor_user_id is not null;

create table if not exists public.wcm_employee_service_state (
  employee_id uuid primary key,
  joining_date date not null,
  service_state text not null default 'active'
    check (service_state in ('pending_join', 'active', 'inactive', 'separated')),
  employment_status text not null default 'active',
  confirmation_date date null,
  leaving_date date null,
  relief_date date null,
  separation_type text null,
  full_and_final_status text null,
  full_and_final_process_date date null,
  position_id bigint null,
  last_billable boolean not null default true,
  state_notes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint wcm_employee_service_state_employment_status_check check (btrim(employment_status) <> ''),
  constraint wcm_employee_service_state_notes_check check (jsonb_typeof(state_notes) = 'object'),
  constraint wcm_employee_service_state_leaving_date_check check (
    leaving_date is null or leaving_date >= joining_date
  ),
  constraint wcm_employee_service_state_relief_date_check check (
    relief_date is null or relief_date >= joining_date
  )
);

create index if not exists idx_wcm_employee_service_state_service_state
on public.wcm_employee_service_state (service_state, employment_status);

create index if not exists idx_wcm_employee_service_state_position_id
on public.wcm_employee_service_state (position_id)
where position_id is not null;

create table if not exists public.wcm_employee_lifecycle_event (
  lifecycle_event_id bigint generated always as identity primary key,
  employee_id uuid not null,
  event_type text not null,
  source_module text not null default 'WCM_CORE',
  prior_service_state text null,
  new_service_state text null,
  prior_employment_status text null,
  new_employment_status text null,
  event_reason text null,
  event_details jsonb not null default '{}'::jsonb,
  actor_user_id uuid null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint wcm_employee_lifecycle_event_type_check check (btrim(event_type) <> ''),
  constraint wcm_employee_lifecycle_event_source_module_check check (btrim(source_module) <> ''),
  constraint wcm_employee_lifecycle_event_details_check check (jsonb_typeof(event_details) = 'object')
);

create index if not exists idx_wcm_employee_lifecycle_event_employee_created
on public.wcm_employee_lifecycle_event (employee_id, created_at desc, lifecycle_event_id desc);

create index if not exists idx_wcm_employee_lifecycle_event_type_created
on public.wcm_employee_lifecycle_event (event_type, created_at desc);

create or replace function public.platform_wcm_module_template_version()
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select 'wcm_core_v1'::text;
$function$;

create or replace function public.platform_wcm_resolve_context(p_params jsonb default '{}'::jsonb)
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
      return public.platform_json_response(
        false,
        'CONTEXT_TENANT_MISMATCH',
        'The requested tenant does not match the current execution context.',
        jsonb_build_object(
          'requested_tenant_id', v_requested_tenant_id,
          'current_tenant_id', v_current_tenant_id
        )
      );
    end if;

    if not public.platform_table_exists(v_current_schema, 'wcm_employee')
      or not public.platform_table_exists(v_current_schema, 'wcm_employee_service_state')
      or not public.platform_table_exists(v_current_schema, 'wcm_employee_lifecycle_event')
    then
      return public.platform_json_response(
        false,
        'WCM_CORE_TEMPLATE_NOT_APPLIED',
        'WCM_CORE is not applied to the current tenant schema.',
        jsonb_build_object(
          'tenant_id', v_current_tenant_id,
          'tenant_schema', v_current_schema
        )
      );
    end if;

    return public.platform_json_response(
      true,
      'OK',
      'WCM execution context resolved.',
      jsonb_build_object(
        'tenant_id', v_current_tenant_id,
        'tenant_schema', v_current_schema,
        'actor_user_id', public.platform_current_actor_user_id()
      )
    );
  end if;

  if not public.platform_is_internal_caller() then
    return public.platform_json_response(
      false,
      'TENANT_CONTEXT_REQUIRED',
      'An applied tenant execution context is required.',
      '{}'::jsonb
    );
  end if;

  if v_requested_tenant_id is null then
    return public.platform_json_response(
      false,
      'TENANT_ID_REQUIRED',
      'tenant_id or tenant_code is required when no execution context is active.',
      '{}'::jsonb
    );
  end if;

  v_context_result := public.platform_apply_execution_context(jsonb_build_object(
    'execution_mode', 'internal_platform',
    'tenant_id', v_requested_tenant_id,
    'source', coalesce(nullif(btrim(v_params->>'source'), ''), 'platform_wcm_resolve_context')
  ));

  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  v_details := coalesce(v_context_result->'details', '{}'::jsonb);

  if not public.platform_table_exists(v_details->>'tenant_schema', 'wcm_employee')
    or not public.platform_table_exists(v_details->>'tenant_schema', 'wcm_employee_service_state')
    or not public.platform_table_exists(v_details->>'tenant_schema', 'wcm_employee_lifecycle_event')
  then
    return public.platform_json_response(
      false,
      'WCM_CORE_TEMPLATE_NOT_APPLIED',
      'WCM_CORE is not applied to the requested tenant schema.',
      jsonb_build_object(
        'tenant_id', public.platform_try_uuid(v_details->>'tenant_id'),
        'tenant_schema', v_details->>'tenant_schema'
      )
    );
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'WCM execution context resolved.',
    jsonb_build_object(
      'tenant_id', public.platform_try_uuid(v_details->>'tenant_id'),
      'tenant_schema', v_details->>'tenant_schema',
      'actor_user_id', public.platform_current_actor_user_id()
    )
  );
exception
  when others then
    return public.platform_json_response(
      false,
      'UNEXPECTED_ERROR',
      'Unexpected error in platform_wcm_resolve_context.',
      jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
    );
end;
$function$;

create or replace function public.platform_apply_wcm_core_to_tenant(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_template_version text := public.platform_wcm_module_template_version();
  v_apply_result jsonb;
  v_context_result jsonb;
  v_context_details jsonb;
  v_schema_name text;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Internal caller is required.', '{}'::jsonb);
  end if;

  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  v_apply_result := public.platform_apply_template_version_to_tenant(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'template_version', v_template_version,
    'source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_apply_wcm_core_to_tenant')
  ));

  if coalesce((v_apply_result->>'success')::boolean, false) is not true then
    return v_apply_result;
  end if;

  v_context_result := public.platform_wcm_resolve_context(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'source', 'platform_apply_wcm_core_to_tenant'
  ));

  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');

  if v_schema_name is null then
    return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_AVAILABLE', 'Tenant schema is not available.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_employee_service_state'
      and c.conname = 'wcm_employee_service_state_employee_fk'
  ) then
    execute format(
      'alter table %I.wcm_employee_service_state add constraint wcm_employee_service_state_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade',
      v_schema_name,
      v_schema_name
    );
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_employee_lifecycle_event'
      and c.conname = 'wcm_employee_lifecycle_event_employee_fk'
  ) then
    execute format(
      'alter table %I.wcm_employee_lifecycle_event add constraint wcm_employee_lifecycle_event_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade',
      v_schema_name,
      v_schema_name
    );
  end if;

  if not exists (
    select 1
    from pg_trigger tg
    join pg_class t on t.oid = tg.tgrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_employee'
      and tg.tgname = 'trg_wcm_employee_set_updated_at'
      and not tg.tgisinternal
  ) then
    execute format(
      'create trigger trg_wcm_employee_set_updated_at before update on %I.wcm_employee for each row execute function public.platform_set_updated_at()',
      v_schema_name
    );
  end if;

  if not exists (
    select 1
    from pg_trigger tg
    join pg_class t on t.oid = tg.tgrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_employee_service_state'
      and tg.tgname = 'trg_wcm_employee_service_state_set_updated_at'
      and not tg.tgisinternal
  ) then
    execute format(
      'create trigger trg_wcm_employee_service_state_set_updated_at before update on %I.wcm_employee_service_state for each row execute function public.platform_set_updated_at()',
      v_schema_name
    );
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'WCM_CORE applied to tenant schema.',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'tenant_schema', v_schema_name,
      'template_version', v_template_version,
      'template_apply', v_apply_result->'details'
    )
  );
exception
  when others then
    return public.platform_json_response(
      false,
      'UNEXPECTED_ERROR',
      'Unexpected error in platform_apply_wcm_core_to_tenant.',
      jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm, 'tenant_id', v_tenant_id)
    );
end;
$function$;

create or replace function public.platform_log_wcm_lifecycle_event(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context_result jsonb;
  v_context_details jsonb;
  v_schema_name text;
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_event_type text := nullif(btrim(coalesce(p_params->>'event_type', '')), '');
  v_source_module text := coalesce(nullif(btrim(p_params->>'source_module'), ''), 'WCM_CORE');
  v_event_reason text := nullif(btrim(p_params->>'event_reason'), '');
  v_event_details jsonb := coalesce(p_params->'event_details', '{}'::jsonb);
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_employee_exists boolean := false;
  v_lifecycle_event_id bigint;
begin
  v_context_result := public.platform_wcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  if v_employee_id is null then
    return public.platform_json_response(false, 'EMPLOYEE_ID_REQUIRED', 'employee_id is required.', '{}'::jsonb);
  end if;

  if v_event_type is null then
    return public.platform_json_response(false, 'EVENT_TYPE_REQUIRED', 'event_type is required.', '{}'::jsonb);
  end if;

  if jsonb_typeof(v_event_details) is distinct from 'object' then
    return public.platform_json_response(false, 'INVALID_EVENT_DETAILS', 'event_details must be a JSON object.', '{}'::jsonb);
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');

  execute format('select exists (select 1 from %I.wcm_employee where employee_id = $1)', v_schema_name)
  into v_employee_exists
  using v_employee_id;

  if not v_employee_exists then
    return public.platform_json_response(false, 'EMPLOYEE_NOT_FOUND', 'Employee not found in tenant schema.', jsonb_build_object('employee_id', v_employee_id));
  end if;

  execute format(
    'insert into %I.wcm_employee_lifecycle_event (
       employee_id,
       event_type,
       source_module,
       prior_service_state,
       new_service_state,
       prior_employment_status,
       new_employment_status,
       event_reason,
       event_details,
       actor_user_id
     )
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
     returning lifecycle_event_id',
    v_schema_name
  )
  into v_lifecycle_event_id
  using
    v_employee_id,
    v_event_type,
    v_source_module,
    nullif(p_params->>'prior_service_state', ''),
    nullif(p_params->>'new_service_state', ''),
    nullif(p_params->>'prior_employment_status', ''),
    nullif(p_params->>'new_employment_status', ''),
    v_event_reason,
    v_event_details,
    v_actor_user_id;

  return public.platform_json_response(
    true,
    'OK',
    'WCM lifecycle event recorded.',
    jsonb_build_object(
      'tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),
      'employee_id', v_employee_id,
      'lifecycle_event_id', v_lifecycle_event_id,
      'event_type', v_event_type
    )
  );
exception
  when others then
    return public.platform_json_response(
      false,
      'UNEXPECTED_ERROR',
      'Unexpected error in platform_log_wcm_lifecycle_event.',
      jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
    );
end;
$function$;;
