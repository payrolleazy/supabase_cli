create or replace function public.platform_hierarchy_health_check(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_schema_name text;
begin
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

  return public.platform_hierarchy_run_diagnostics_internal(v_tenant_id, v_schema_name, 'health_check');
end;
$function$;

create or replace function public.platform_hierarchy_self_test(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_schema_name text;
begin
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

  return public.platform_hierarchy_run_diagnostics_internal(v_tenant_id, v_schema_name, 'self_test');
end;
$function$;