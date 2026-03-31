create or replace function public.platform_rcm_requisition_catalog_rows()
returns table (
  tenant_id uuid,
  requisition_id uuid,
  requisition_code text,
  requisition_title text,
  position_id bigint,
  position_code text,
  position_name text,
  requisition_status text,
  openings_count integer,
  filled_count integer,
  open_application_count integer,
  target_start_date date,
  priority_code text,
  created_at timestamptz,
  updated_at timestamptz
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
  if not public.platform_table_exists(v_schema_name, 'rcm_requisition')
    or not public.platform_table_exists(v_schema_name, 'hierarchy_position')
    or not public.platform_table_exists(v_schema_name, 'rcm_job_application') then
    return;
  end if;

  return query execute format(
    'select $1::uuid as tenant_id,
            r.requisition_id,
            r.requisition_code,
            r.requisition_title,
            r.position_id,
            p.position_code,
            p.position_name,
            r.requisition_status,
            r.openings_count,
            coalesce(conv.filled_count, 0)::integer as filled_count,
            coalesce(app.open_application_count, 0)::integer as open_application_count,
            r.target_start_date,
            r.priority_code,
            r.created_at,
            r.updated_at
     from %1$I.rcm_requisition r
     join %1$I.hierarchy_position p on p.position_id = r.position_id
     left join (
       select requisition_id, count(*) as filled_count
       from %1$I.rcm_job_application
       where application_status = ''converted''
       group by requisition_id
     ) conv on conv.requisition_id = r.requisition_id
     left join (
       select requisition_id, count(*) as open_application_count
       from %1$I.rcm_job_application
       where application_status = ''active''
       group by requisition_id
     ) app on app.requisition_id = r.requisition_id
     order by r.requisition_code',
    v_schema_name
  ) using v_tenant_id;
end;
$function$;

create or replace function public.platform_rcm_candidate_pipeline_rows()
returns table (
  tenant_id uuid,
  application_id uuid,
  requisition_id uuid,
  requisition_code text,
  candidate_id uuid,
  candidate_code text,
  candidate_name text,
  primary_email text,
  current_stage_code text,
  application_status text,
  target_position_id bigint,
  target_position_code text,
  conversion_case_id uuid,
  conversion_status text,
  wcm_employee_id uuid,
  employee_code text,
  applied_on date,
  converted_at timestamptz,
  updated_at timestamptz
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
  if not public.platform_table_exists(v_schema_name, 'rcm_job_application')
    or not public.platform_table_exists(v_schema_name, 'rcm_candidate')
    or not public.platform_table_exists(v_schema_name, 'rcm_requisition')
    or not public.platform_table_exists(v_schema_name, 'rcm_conversion_case')
    or not public.platform_table_exists(v_schema_name, 'hierarchy_position')
    or not public.platform_table_exists(v_schema_name, 'wcm_employee') then
    return;
  end if;

  return query execute format(
    'select $1::uuid as tenant_id,
            a.application_id,
            a.requisition_id,
            r.requisition_code,
            a.candidate_id,
            c.candidate_code,
            concat_ws('' '', c.first_name, c.middle_name, c.last_name) as candidate_name,
            c.primary_email,
            a.current_stage_code,
            a.application_status,
            r.position_id as target_position_id,
            p.position_code as target_position_code,
            conv.conversion_case_id,
            conv.conversion_status,
            conv.wcm_employee_id,
            e.employee_code,
            a.applied_on,
            a.converted_at,
            a.updated_at
     from %1$I.rcm_job_application a
     join %1$I.rcm_candidate c on c.candidate_id = a.candidate_id
     join %1$I.rcm_requisition r on r.requisition_id = a.requisition_id
     join %1$I.hierarchy_position p on p.position_id = r.position_id
     left join %1$I.rcm_conversion_case conv on conv.application_id = a.application_id
     left join %1$I.wcm_employee e on e.employee_id = conv.wcm_employee_id
     order by a.updated_at desc, a.application_id',
    v_schema_name
  ) using v_tenant_id;
end;
$function$;

create or replace function public.platform_rcm_conversion_queue_rows()
returns table (
  tenant_id uuid,
  conversion_case_id uuid,
  application_id uuid,
  requisition_id uuid,
  requisition_code text,
  candidate_id uuid,
  candidate_code text,
  candidate_name text,
  target_position_id bigint,
  target_position_code text,
  conversion_status text,
  prepared_at timestamptz,
  converted_at timestamptz,
  wcm_employee_id uuid,
  employee_code text,
  current_stage_code text,
  application_status text
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
  if not public.platform_table_exists(v_schema_name, 'rcm_conversion_case')
    or not public.platform_table_exists(v_schema_name, 'rcm_job_application')
    or not public.platform_table_exists(v_schema_name, 'rcm_candidate')
    or not public.platform_table_exists(v_schema_name, 'rcm_requisition')
    or not public.platform_table_exists(v_schema_name, 'hierarchy_position')
    or not public.platform_table_exists(v_schema_name, 'wcm_employee') then
    return;
  end if;

  return query execute format(
    'select $1::uuid as tenant_id,
            conv.conversion_case_id,
            conv.application_id,
            conv.requisition_id,
            r.requisition_code,
            conv.candidate_id,
            c.candidate_code,
            concat_ws('' '', c.first_name, c.middle_name, c.last_name) as candidate_name,
            conv.target_position_id,
            p.position_code as target_position_code,
            conv.conversion_status,
            conv.prepared_at,
            conv.converted_at,
            conv.wcm_employee_id,
            e.employee_code,
            a.current_stage_code,
            a.application_status
     from %1$I.rcm_conversion_case conv
     join %1$I.rcm_job_application a on a.application_id = conv.application_id
     join %1$I.rcm_candidate c on c.candidate_id = conv.candidate_id
     join %1$I.rcm_requisition r on r.requisition_id = conv.requisition_id
     join %1$I.hierarchy_position p on p.position_id = conv.target_position_id
     left join %1$I.wcm_employee e on e.employee_id = conv.wcm_employee_id
     order by conv.prepared_at desc, conv.conversion_case_id',
    v_schema_name
  ) using v_tenant_id;
end;
$function$;;
