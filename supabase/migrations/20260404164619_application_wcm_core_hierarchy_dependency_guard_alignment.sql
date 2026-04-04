create or replace function public.platform_hierarchy_sync_wcm_position_state(p_schema_name text, p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_position_id bigint;
begin
  if p_schema_name is null or p_employee_id is null then
    return;
  end if;

  if not public.platform_table_exists(p_schema_name, 'wcm_employee_service_state')
     or not public.platform_table_exists(p_schema_name, 'hierarchy_position_occupancy') then
    return;
  end if;

  execute format(
    'select o.position_id
     from %I.hierarchy_position_occupancy o
     where o.employee_id = $1
       and o.occupancy_status = ''active''
       and o.effective_start_date <= current_date
       and coalesce(o.effective_end_date, date ''9999-12-31'') >= current_date
     order by o.effective_start_date desc, o.occupancy_id desc
     limit 1',
    p_schema_name
  )
  into v_position_id
  using p_employee_id;

  execute format(
    'update %I.wcm_employee_service_state
     set position_id = $1,
         updated_at = timezone(''utc'', now())
     where employee_id = $2',
    p_schema_name
  )
  using v_position_id, p_employee_id;
end;
$function$;
