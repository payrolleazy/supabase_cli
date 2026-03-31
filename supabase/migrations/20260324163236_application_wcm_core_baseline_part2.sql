set search_path = public, pg_temp;

create or replace function public.platform_register_wcm_employee(p_params jsonb)
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
  v_input_employee_code text := nullif(btrim(coalesce(p_params->>'employee_code', '')), '');
  v_input_first_name text := nullif(btrim(coalesce(p_params->>'first_name', '')), '');
  v_input_middle_name text := nullif(btrim(coalesce(p_params->>'middle_name', '')), '');
  v_input_last_name text := nullif(btrim(coalesce(p_params->>'last_name', '')), '');
  v_input_official_email text := nullif(lower(btrim(coalesce(p_params->>'official_email', ''))), '');
  v_input_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_existing_employee_id uuid;
  v_existing_employee_code text;
  v_existing_first_name text;
  v_existing_middle_name text;
  v_existing_last_name text;
  v_existing_official_email text;
  v_existing_actor_user_id uuid;
  v_final_employee_code text;
  v_final_first_name text;
  v_final_middle_name text;
  v_final_last_name text;
  v_final_official_email text;
  v_final_actor_user_id uuid;
  v_duplicate_employee_id uuid;
  v_operation_kind text;
begin
  v_context_result := public.platform_wcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');

  if v_employee_id is not null then
    execute format(
      'select employee_id, employee_code, first_name, middle_name, last_name, official_email, actor_user_id
       from %I.wcm_employee
       where employee_id = $1',
      v_schema_name
    )
    into v_existing_employee_id, v_existing_employee_code, v_existing_first_name, v_existing_middle_name, v_existing_last_name, v_existing_official_email, v_existing_actor_user_id
    using v_employee_id;

    if v_existing_employee_id is null then
      return public.platform_json_response(false, 'EMPLOYEE_NOT_FOUND', 'Employee not found.', jsonb_build_object('employee_id', v_employee_id));
    end if;

    v_operation_kind := 'updated';
  else
    v_operation_kind := 'created';
  end if;

  v_final_employee_code := coalesce(v_input_employee_code, v_existing_employee_code);
  v_final_first_name := coalesce(v_input_first_name, v_existing_first_name);
  v_final_middle_name := coalesce(v_input_middle_name, v_existing_middle_name);
  v_final_last_name := coalesce(v_input_last_name, v_existing_last_name);
  v_final_official_email := coalesce(v_input_official_email, v_existing_official_email);
  v_final_actor_user_id := coalesce(v_input_actor_user_id, v_existing_actor_user_id);

  if v_final_employee_code is null then
    return public.platform_json_response(false, 'EMPLOYEE_CODE_REQUIRED', 'employee_code is required.', '{}'::jsonb);
  end if;

  if v_final_first_name is null or v_final_last_name is null then
    return public.platform_json_response(false, 'EMPLOYEE_NAME_REQUIRED', 'first_name and last_name are required.', '{}'::jsonb);
  end if;

  if v_final_official_email is null then
    return public.platform_json_response(false, 'OFFICIAL_EMAIL_REQUIRED', 'official_email is required.', '{}'::jsonb);
  end if;

  execute format('select employee_id from %I.wcm_employee where employee_code = $1 limit 1', v_schema_name)
  into v_duplicate_employee_id
  using v_final_employee_code;

  if v_duplicate_employee_id is not null and (v_employee_id is null or v_duplicate_employee_id <> v_employee_id) then
    return public.platform_json_response(false, 'EMPLOYEE_CODE_EXISTS', 'employee_code already exists in the tenant.', jsonb_build_object('employee_code', v_final_employee_code));
  end if;

  execute format('select employee_id from %I.wcm_employee where lower(official_email) = $1 limit 1', v_schema_name)
  into v_duplicate_employee_id
  using lower(v_final_official_email);

  if v_duplicate_employee_id is not null and (v_employee_id is null or v_duplicate_employee_id <> v_employee_id) then
    return public.platform_json_response(false, 'EMPLOYEE_EMAIL_EXISTS', 'official_email already exists in the tenant.', jsonb_build_object('official_email', v_final_official_email));
  end if;

  if v_final_actor_user_id is not null then
    execute format('select employee_id from %I.wcm_employee where actor_user_id = $1 limit 1', v_schema_name)
    into v_duplicate_employee_id
    using v_final_actor_user_id;

    if v_duplicate_employee_id is not null and (v_employee_id is null or v_duplicate_employee_id <> v_employee_id) then
      return public.platform_json_response(false, 'EMPLOYEE_ACTOR_LINK_EXISTS', 'actor_user_id is already linked to another employee in the tenant.', jsonb_build_object('actor_user_id', v_final_actor_user_id));
    end if;
  end if;

  if v_operation_kind = 'created' then
    execute format(
      'insert into %I.wcm_employee (
         employee_code,
         first_name,
         middle_name,
         last_name,
         official_email,
         actor_user_id
       )
       values ($1, $2, $3, $4, $5, $6)
       returning employee_id',
      v_schema_name
    )
    into v_employee_id
    using v_final_employee_code, v_final_first_name, v_final_middle_name, v_final_last_name, v_final_official_email, v_final_actor_user_id;
  else
    execute format(
      'update %I.wcm_employee
       set employee_code = $1,
           first_name = $2,
           middle_name = $3,
           last_name = $4,
           official_email = $5,
           actor_user_id = $6,
           updated_at = timezone(''utc'', now())
       where employee_id = $7',
      v_schema_name
    )
    using v_final_employee_code, v_final_first_name, v_final_middle_name, v_final_last_name, v_final_official_email, v_final_actor_user_id, v_employee_id;
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'WCM employee registered.',
    jsonb_build_object(
      'tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),
      'employee_id', v_employee_id,
      'operation_kind', v_operation_kind,
      'employee_code', v_final_employee_code,
      'official_email', v_final_official_email,
      'actor_user_id', v_final_actor_user_id
    )
  );
exception
  when others then
    return public.platform_json_response(
      false,
      'UNEXPECTED_ERROR',
      'Unexpected error in platform_register_wcm_employee.',
      jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
    );
end;
$function$;

create or replace function public.platform_upsert_wcm_service_state(p_params jsonb)
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
  v_input_joining_date date := public.platform_try_date(p_params->>'joining_date');
  v_input_service_state text := lower(coalesce(nullif(btrim(p_params->>'service_state'), ''), ''));
  v_input_employment_status text := nullif(btrim(coalesce(p_params->>'employment_status', '')), '');
  v_input_confirmation_date date := public.platform_try_date(p_params->>'confirmation_date');
  v_input_leaving_date date := public.platform_try_date(p_params->>'leaving_date');
  v_input_relief_date date := public.platform_try_date(p_params->>'relief_date');
  v_input_separation_type text := nullif(btrim(coalesce(p_params->>'separation_type', '')), '');
  v_input_full_and_final_status text := nullif(btrim(coalesce(p_params->>'full_and_final_status', '')), '');
  v_input_full_and_final_process_date date := public.platform_try_date(p_params->>'full_and_final_process_date');
  v_input_position_id bigint := public.platform_try_bigint(p_params->>'position_id');
  v_input_last_billable boolean := case when p_params ? 'last_billable' then (p_params->>'last_billable')::boolean else null end;
  v_input_state_notes jsonb := coalesce(p_params->'state_notes', '{}'::jsonb);
  v_employee_exists boolean := false;
  v_existing_employee_id uuid;
  v_existing_joining_date date;
  v_existing_service_state text;
  v_existing_employment_status text;
  v_existing_confirmation_date date;
  v_existing_leaving_date date;
  v_existing_relief_date date;
  v_existing_separation_type text;
  v_existing_full_and_final_status text;
  v_existing_full_and_final_process_date date;
  v_existing_position_id bigint;
  v_existing_last_billable boolean;
  v_existing_state_notes jsonb;
  v_state_exists boolean := false;
  v_final_joining_date date;
  v_final_service_state text;
  v_final_employment_status text;
  v_final_confirmation_date date;
  v_final_leaving_date date;
  v_final_relief_date date;
  v_final_separation_type text;
  v_final_full_and_final_status text;
  v_final_full_and_final_process_date date;
  v_final_position_id bigint;
  v_final_last_billable boolean;
  v_final_state_notes jsonb;
  v_current_billable boolean;
  v_event_result jsonb;
  v_event_type text;
begin
  v_context_result := public.platform_wcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  if v_employee_id is null then
    return public.platform_json_response(false, 'EMPLOYEE_ID_REQUIRED', 'employee_id is required.', '{}'::jsonb);
  end if;

  if jsonb_typeof(v_input_state_notes) is distinct from 'object' then
    return public.platform_json_response(false, 'INVALID_STATE_NOTES', 'state_notes must be a JSON object.', '{}'::jsonb);
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');

  execute format('select exists (select 1 from %I.wcm_employee where employee_id = $1)', v_schema_name)
  into v_employee_exists
  using v_employee_id;

  if not v_employee_exists then
    return public.platform_json_response(false, 'EMPLOYEE_NOT_FOUND', 'Employee not found.', jsonb_build_object('employee_id', v_employee_id));
  end if;

  execute format(
    'select employee_id, joining_date, service_state, employment_status, confirmation_date, leaving_date, relief_date, separation_type, full_and_final_status, full_and_final_process_date, position_id, last_billable, state_notes
     from %I.wcm_employee_service_state
     where employee_id = $1',
    v_schema_name
  )
  into v_existing_employee_id, v_existing_joining_date, v_existing_service_state, v_existing_employment_status, v_existing_confirmation_date, v_existing_leaving_date, v_existing_relief_date, v_existing_separation_type, v_existing_full_and_final_status, v_existing_full_and_final_process_date, v_existing_position_id, v_existing_last_billable, v_existing_state_notes
  using v_employee_id;

  v_state_exists := v_existing_employee_id is not null;

  v_final_joining_date := coalesce(v_input_joining_date, v_existing_joining_date);
  v_final_service_state := coalesce(nullif(v_input_service_state, ''), v_existing_service_state, 'active');
  v_final_employment_status := coalesce(v_input_employment_status, v_existing_employment_status, 'active');
  v_final_confirmation_date := coalesce(v_input_confirmation_date, v_existing_confirmation_date);
  v_final_leaving_date := coalesce(v_input_leaving_date, v_existing_leaving_date);
  v_final_relief_date := coalesce(v_input_relief_date, v_existing_relief_date);
  v_final_separation_type := coalesce(v_input_separation_type, v_existing_separation_type);
  v_final_full_and_final_status := coalesce(v_input_full_and_final_status, v_existing_full_and_final_status);
  v_final_full_and_final_process_date := coalesce(v_input_full_and_final_process_date, v_existing_full_and_final_process_date);
  v_final_position_id := coalesce(v_input_position_id, v_existing_position_id);
  v_final_last_billable := coalesce(v_input_last_billable, v_existing_last_billable, true);
  v_final_state_notes := case when p_params ? 'state_notes' then v_input_state_notes else coalesce(v_existing_state_notes, '{}'::jsonb) end;

  if v_final_joining_date is null then
    return public.platform_json_response(false, 'JOINING_DATE_REQUIRED', 'joining_date is required for the first service-state write.', '{}'::jsonb);
  end if;

  if v_final_service_state not in ('pending_join', 'active', 'inactive', 'separated') then
    return public.platform_json_response(false, 'INVALID_SERVICE_STATE', 'service_state is invalid.', jsonb_build_object('service_state', v_final_service_state));
  end if;

  if v_final_employment_status is null then
    return public.platform_json_response(false, 'EMPLOYMENT_STATUS_REQUIRED', 'employment_status is required.', '{}'::jsonb);
  end if;

  if v_final_leaving_date is not null and v_final_leaving_date < v_final_joining_date then
    return public.platform_json_response(false, 'INVALID_LEAVING_DATE', 'leaving_date cannot be earlier than joining_date.', '{}'::jsonb);
  end if;

  if v_final_relief_date is not null and v_final_relief_date < v_final_joining_date then
    return public.platform_json_response(false, 'INVALID_RELIEF_DATE', 'relief_date cannot be earlier than joining_date.', '{}'::jsonb);
  end if;

  if v_state_exists then
    execute format(
      'update %I.wcm_employee_service_state
       set joining_date = $1,
           service_state = $2,
           employment_status = $3,
           confirmation_date = $4,
           leaving_date = $5,
           relief_date = $6,
           separation_type = $7,
           full_and_final_status = $8,
           full_and_final_process_date = $9,
           position_id = $10,
           last_billable = $11,
           state_notes = $12,
           updated_at = timezone(''utc'', now())
       where employee_id = $13',
      v_schema_name
    )
    using v_final_joining_date, v_final_service_state, v_final_employment_status, v_final_confirmation_date, v_final_leaving_date, v_final_relief_date, v_final_separation_type, v_final_full_and_final_status, v_final_full_and_final_process_date, v_final_position_id, v_final_last_billable, v_final_state_notes, v_employee_id;
  else
    execute format(
      'insert into %I.wcm_employee_service_state (
         employee_id,
         joining_date,
         service_state,
         employment_status,
         confirmation_date,
         leaving_date,
         relief_date,
         separation_type,
         full_and_final_status,
         full_and_final_process_date,
         position_id,
         last_billable,
         state_notes
       )
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)',
      v_schema_name
    )
    using v_employee_id, v_final_joining_date, v_final_service_state, v_final_employment_status, v_final_confirmation_date, v_final_leaving_date, v_final_relief_date, v_final_separation_type, v_final_full_and_final_status, v_final_full_and_final_process_date, v_final_position_id, v_final_last_billable, v_final_state_notes;
  end if;

  v_current_billable := case
    when v_final_service_state = 'active' then true
    when v_final_service_state in ('inactive', 'separated')
      and v_final_last_billable = true
      and coalesce(lower(v_final_full_and_final_status), '') not in ('completed', 'settled', 'waived')
    then true
    else false
  end;

  v_event_type := case
    when not v_state_exists then 'service_state_initialized'
    when v_existing_service_state is distinct from v_final_service_state
      or v_existing_employment_status is distinct from v_final_employment_status
      or v_existing_full_and_final_status is distinct from v_final_full_and_final_status
    then 'service_state_changed'
    else 'service_state_updated'
  end;

  v_event_result := public.platform_log_wcm_lifecycle_event(jsonb_build_object(
    'tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),
    'employee_id', v_employee_id,
    'event_type', v_event_type,
    'source_module', coalesce(nullif(btrim(p_params->>'source_module'), ''), 'WCM_CORE'),
    'event_reason', nullif(btrim(p_params->>'event_reason'), ''),
    'prior_service_state', v_existing_service_state,
    'new_service_state', v_final_service_state,
    'prior_employment_status', v_existing_employment_status,
    'new_employment_status', v_final_employment_status,
    'event_details', jsonb_build_object(
      'joining_date', v_final_joining_date,
      'leaving_date', v_final_leaving_date,
      'relief_date', v_final_relief_date,
      'full_and_final_status', v_final_full_and_final_status,
      'full_and_final_process_date', v_final_full_and_final_process_date,
      'last_billable', v_final_last_billable,
      'current_billable', v_current_billable,
      'position_id', v_final_position_id
    )
  ));

  if coalesce((v_event_result->>'success')::boolean, false) is not true then
    return v_event_result;
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'WCM service state recorded.',
    jsonb_build_object(
      'tenant_id', public.platform_try_uuid(v_context_details->>'tenant_id'),
      'employee_id', v_employee_id,
      'service_state', v_final_service_state,
      'employment_status', v_final_employment_status,
      'full_and_final_status', v_final_full_and_final_status,
      'last_billable', v_final_last_billable,
      'current_billable', v_current_billable,
      'event_type', v_event_type
    )
  );
exception
  when others then
    return public.platform_json_response(
      false,
      'UNEXPECTED_ERROR',
      'Unexpected error in platform_upsert_wcm_service_state.',
      jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
    );
end;
$function$;

create or replace function public.platform_wcm_employee_catalog_rows()
returns table (
  tenant_id uuid,
  employee_id uuid,
  employee_code text,
  first_name text,
  middle_name text,
  last_name text,
  official_email text,
  actor_user_id uuid,
  service_state text,
  employment_status text,
  joining_date date,
  confirmation_date date,
  leaving_date date,
  relief_date date,
  separation_type text,
  full_and_final_status text,
  full_and_final_process_date date,
  position_id bigint,
  last_billable boolean,
  current_billable boolean,
  created_at timestamptz,
  updated_at timestamptz,
  state_updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_current_tenant_id();
  v_schema_name text := public.platform_current_tenant_schema();
begin
  if v_tenant_id is null or v_schema_name is null then
    return;
  end if;

  if not public.platform_table_exists(v_schema_name, 'wcm_employee')
    or not public.platform_table_exists(v_schema_name, 'wcm_employee_service_state')
  then
    return;
  end if;

  return query execute format(
    'select
       $1::uuid as tenant_id,
       e.employee_id,
       e.employee_code,
       e.first_name,
       e.middle_name,
       e.last_name,
       e.official_email,
       e.actor_user_id,
       s.service_state,
       s.employment_status,
       s.joining_date,
       s.confirmation_date,
       s.leaving_date,
       s.relief_date,
       s.separation_type,
       s.full_and_final_status,
       s.full_and_final_process_date,
       s.position_id,
       s.last_billable,
       case
         when s.service_state = ''active'' then true
         when s.service_state in (''inactive'', ''separated'')
           and coalesce(s.last_billable, false) = true
           and coalesce(lower(s.full_and_final_status), '''') not in (''completed'', ''settled'', ''waived'')
         then true
         else false
       end as current_billable,
       e.created_at,
       e.updated_at,
       s.updated_at as state_updated_at
     from %I.wcm_employee e
     left join %I.wcm_employee_service_state s
       on s.employee_id = e.employee_id
     order by e.employee_code',
    v_schema_name,
    v_schema_name
  ) using v_tenant_id;
end;
$function$;

create or replace view public.platform_rm_wcm_employee_catalog
with (security_invoker = true) as
select *
from public.platform_wcm_employee_catalog_rows();

create or replace view public.platform_rm_wcm_service_state_overview
with (security_invoker = true) as
select
  tenant_id,
  employee_id,
  employee_code,
  actor_user_id,
  service_state,
  employment_status,
  joining_date,
  confirmation_date,
  leaving_date,
  relief_date,
  separation_type,
  full_and_final_status,
  full_and_final_process_date,
  position_id,
  last_billable,
  current_billable,
  state_updated_at
from public.platform_rm_wcm_employee_catalog;

create or replace view public.platform_rm_wcm_billable_state_overview
with (security_invoker = true) as
select
  tenant_id,
  employee_id,
  employee_code,
  service_state,
  employment_status,
  full_and_final_status,
  last_billable,
  current_billable,
  leaving_date,
  relief_date,
  full_and_final_process_date,
  state_updated_at
from public.platform_rm_wcm_service_state_overview;

create or replace view public.platform_rm_wcm_headcount_summary
with (security_invoker = true) as
select
  tenant_id,
  count(*) as employee_count,
  count(*) filter (where service_state = 'active') as active_employee_count,
  count(*) filter (where current_billable) as current_billable_count,
  count(*) filter (where service_state = 'inactive') as inactive_employee_count,
  count(*) filter (where service_state = 'separated') as separated_employee_count
from public.platform_rm_wcm_service_state_overview
group by tenant_id;

revoke all on public.wcm_employee from public, anon, authenticated;
revoke all on public.wcm_employee_service_state from public, anon, authenticated;
revoke all on public.wcm_employee_lifecycle_event from public, anon, authenticated;
revoke all on public.platform_rm_wcm_employee_catalog from public, anon, authenticated;
revoke all on public.platform_rm_wcm_service_state_overview from public, anon, authenticated;
revoke all on public.platform_rm_wcm_billable_state_overview from public, anon, authenticated;
revoke all on public.platform_rm_wcm_headcount_summary from public, anon, authenticated;
revoke all on function public.platform_wcm_module_template_version() from public, anon, authenticated;
revoke all on function public.platform_wcm_resolve_context(jsonb) from public, anon, authenticated;
revoke all on function public.platform_apply_wcm_core_to_tenant(jsonb) from public, anon, authenticated;
revoke all on function public.platform_log_wcm_lifecycle_event(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_wcm_employee(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_wcm_service_state(jsonb) from public, anon, authenticated;
revoke all on function public.platform_wcm_employee_catalog_rows() from public, anon, authenticated;

grant select on public.platform_rm_wcm_employee_catalog to service_role;
grant select on public.platform_rm_wcm_service_state_overview to service_role;
grant select on public.platform_rm_wcm_billable_state_overview to service_role;
grant select on public.platform_rm_wcm_headcount_summary to service_role;
grant execute on function public.platform_wcm_module_template_version() to service_role;
grant execute on function public.platform_apply_wcm_core_to_tenant(jsonb) to service_role;
grant execute on function public.platform_log_wcm_lifecycle_event(jsonb) to service_role;
grant execute on function public.platform_register_wcm_employee(jsonb) to service_role;
grant execute on function public.platform_upsert_wcm_service_state(jsonb) to service_role;

do $$
declare
  v_template_version text := public.platform_wcm_module_template_version();
  v_result jsonb;
begin
  v_result := public.platform_register_template_version(jsonb_build_object(
    'template_version', v_template_version,
    'template_scope', 'module',
    'template_status', 'released',
    'foundation_version', 'I06',
    'description', 'WCM_CORE tenant-owned employee baseline.',
    'release_notes', jsonb_build_object(
      'slice', 'WCM_CORE',
      'module_code', 'WCM_CORE',
      'tenant_owned_tables', jsonb_build_array('wcm_employee', 'wcm_employee_service_state', 'wcm_employee_lifecycle_event')
    )
  ));

  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'WCM template version registration failed: %', v_result::text;
  end if;

  v_result := public.platform_register_template_table(jsonb_build_object(
    'template_version', v_template_version,
    'module_code', 'WCM_CORE',
    'source_schema_name', 'public',
    'source_table_name', 'wcm_employee',
    'target_table_name', 'wcm_employee',
    'clone_order', 100,
    'notes', jsonb_build_object('slice', 'WCM_CORE', 'kind', 'tenant_owned_table')
  ));

  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'WCM employee template table registration failed: %', v_result::text;
  end if;

  v_result := public.platform_register_template_table(jsonb_build_object(
    'template_version', v_template_version,
    'module_code', 'WCM_CORE',
    'source_schema_name', 'public',
    'source_table_name', 'wcm_employee_service_state',
    'target_table_name', 'wcm_employee_service_state',
    'clone_order', 110,
    'notes', jsonb_build_object('slice', 'WCM_CORE', 'kind', 'tenant_owned_table')
  ));

  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'WCM service-state template table registration failed: %', v_result::text;
  end if;

  v_result := public.platform_register_template_table(jsonb_build_object(
    'template_version', v_template_version,
    'module_code', 'WCM_CORE',
    'source_schema_name', 'public',
    'source_table_name', 'wcm_employee_lifecycle_event',
    'target_table_name', 'wcm_employee_lifecycle_event',
    'clone_order', 120,
    'notes', jsonb_build_object('slice', 'WCM_CORE', 'kind', 'tenant_owned_table')
  ));

  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'WCM lifecycle-event template table registration failed: %', v_result::text;
  end if;
end $$;;
