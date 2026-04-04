do $$
begin
  if not exists (
    select 1
    from public.platform_wcm_resignation_request
    where tenant_id = '{{WCM_TENANT_ID}}'::uuid
      and employee_id = '{{WCM_BASE_EMPLOYEE_ID}}'::uuid
  ) then
    raise exception 'WCM resignation request not found for run {{RUN_ID}}';
  end if;
end;
$$;

select json_build_object(
  'WCM_REQUEST_ID',
  (
    select request_id::text
    from public.platform_wcm_resignation_request
    where tenant_id = '{{WCM_TENANT_ID}}'::uuid
      and employee_id = '{{WCM_BASE_EMPLOYEE_ID}}'::uuid
    order by created_at desc
    limit 1
  )
)::text;
