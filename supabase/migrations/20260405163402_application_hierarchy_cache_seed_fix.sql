create or replace function public.platform_hierarchy_org_chart_cache_seed_rows()
returns table(
  tenant_id uuid,
  position_id bigint,
  position_code text,
  position_name text,
  position_group_id bigint,
  position_group_code text,
  position_group_name text,
  reporting_position_id bigint,
  hierarchy_path text,
  hierarchy_level integer,
  position_status text,
  active_occupancy_count integer,
  direct_report_count integer,
  operational_employee_id uuid,
  operational_employee_code text,
  operational_actor_user_id uuid,
  operational_employee_name text,
  operational_occupancy_role text,
  overlap_count integer
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant record;
begin
  for v_tenant in
    select t.tenant_id, t.schema_name
    from public.platform_tenant_registry_view t
    where t.schema_provisioned is true
      and t.schema_name like 'tenant_%'
    order by t.schema_name
  loop
    return query
    select *
    from public.platform_hierarchy_org_chart_rows_for_schema(v_tenant.tenant_id, v_tenant.schema_name);
  end loop;
end;
$function$;
