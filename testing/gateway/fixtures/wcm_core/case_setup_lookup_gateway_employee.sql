do $$
declare
  v_schema_name text;
  v_employee_id uuid;
begin
  select schema_name
  into v_schema_name
  from public.platform_tenant
  where tenant_id = '{{WCM_TENANT_ID}}'::uuid;

  if v_schema_name is null then
    raise exception 'WCM tenant schema not found for run {{RUN_ID}}';
  end if;

  execute format(
    'select employee_id from %I.wcm_employee where employee_code = %L limit 1',
    v_schema_name,
    'WCM-GW-{{RUN_ID}}'
  )
  into v_employee_id;

  if v_employee_id is null then
    raise exception 'WCM gateway employee not found for run {{RUN_ID}}';
  end if;

  perform set_config('wcm_core.gateway_employee_id', v_employee_id::text, false);
end;
$$;

select json_build_object(
  'WCM_GATEWAY_EMPLOYEE_ID',
  current_setting('wcm_core.gateway_employee_id', true)
)::text;

