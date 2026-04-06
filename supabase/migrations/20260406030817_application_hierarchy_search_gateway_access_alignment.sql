create or replace function public.platform_search_hierarchy_positions(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_schema_name text;
  v_search_text text := nullif(btrim(p_params->>'search_text'), '');
  v_position_status text := nullif(lower(btrim(p_params->>'position_status')), '');
  v_limit integer := 50;
  v_rows jsonb := '[]'::jsonb;
  v_row_count integer := 0;
  v_cache_available boolean := false;
begin
  if nullif(p_params->>'limit', '') is not null then
    begin
      v_limit := (p_params->>'limit')::integer;
    exception when others then
      return public.platform_json_response(false, 'INVALID_LIMIT', 'limit must be an integer.', '{}'::jsonb);
    end;
  end if;

  if v_tenant_id is null then
    v_tenant_id := public.platform_current_tenant_id();
  end if;
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select schema_name into v_schema_name from public.platform_tenant_registry_view where tenant_id = v_tenant_id and schema_provisioned is true;
  if v_schema_name is null then
    return public.platform_json_response(false, 'TENANT_SCHEMA_NOT_FOUND', 'Tenant schema is not available.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_limit < 1 then
    v_limit := 1;
  elsif v_limit > 200 then
    v_limit := 200;
  end if;

  select exists (select 1 from public.platform_rm_hierarchy_org_chart_cached_store c where c.tenant_id = v_tenant_id limit 1) into v_cache_available;

  if v_cache_available then
    select count(*)::integer, coalesce(jsonb_agg(to_jsonb(s) order by s.hierarchy_path, s.position_code), '[]'::jsonb)
    into v_row_count, v_rows
    from (
      select *
      from public.platform_rm_hierarchy_org_chart_cached_store c
      where c.tenant_id = v_tenant_id
        and (v_position_status is null or c.position_status = v_position_status)
        and (
          v_search_text is null
          or c.position_code ilike ('%' || v_search_text || '%')
          or c.position_name ilike ('%' || v_search_text || '%')
          or coalesce(c.position_group_code, '') ilike ('%' || v_search_text || '%')
          or coalesce(c.position_group_name, '') ilike ('%' || v_search_text || '%')
          or coalesce(c.operational_employee_code, '') ilike ('%' || v_search_text || '%')
          or coalesce(c.operational_employee_name, '') ilike ('%' || v_search_text || '%')
        )
      order by c.hierarchy_path nulls last, c.position_code
      limit v_limit
    ) s;
  else
    select count(*)::integer, coalesce(jsonb_agg(to_jsonb(s) order by s.hierarchy_path, s.position_code), '[]'::jsonb)
    into v_row_count, v_rows
    from (
      select *
      from public.platform_hierarchy_org_chart_rows_for_schema(v_tenant_id, v_schema_name) c
      where (v_position_status is null or c.position_status = v_position_status)
        and (
          v_search_text is null
          or c.position_code ilike ('%' || v_search_text || '%')
          or c.position_name ilike ('%' || v_search_text || '%')
          or coalesce(c.position_group_code, '') ilike ('%' || v_search_text || '%')
          or coalesce(c.position_group_name, '') ilike ('%' || v_search_text || '%')
          or coalesce(c.operational_employee_code, '') ilike ('%' || v_search_text || '%')
          or coalesce(c.operational_employee_name, '') ilike ('%' || v_search_text || '%')
        )
      order by c.hierarchy_path nulls last, c.position_code
      limit v_limit
    ) s;
  end if;

  return public.platform_json_response(true, 'OK', 'Hierarchy search completed.', jsonb_build_object('tenant_id', v_tenant_id, 'row_count', v_row_count, 'cache_available', v_cache_available, 'rows', v_rows));
end;
$function$;