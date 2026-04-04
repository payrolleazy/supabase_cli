do $$
declare
  v_request_id uuid;
  v_audit_exists boolean;
begin
  select request_id
  into v_request_id
  from public.platform_wcm_resignation_request
  where tenant_id = '{{WCM_TENANT_ID}}'::uuid
    and employee_id = '{{WCM_BASE_EMPLOYEE_ID}}'::uuid
  order by created_at desc
  limit 1;

  if v_request_id is null then
    raise exception 'WCM rollback audit fixture missing request id for run {{RUN_ID}}';
  end if;

  select exists (
    select 1
    from public.platform_wcm_lifecycle_rollback_audit
    where tenant_id = '{{WCM_TENANT_ID}}'::uuid
      and request_id = v_request_id
      and decision_code = 'signal_only_reversal'
      and action_code = 'no_downstream_artifact'
  ) into v_audit_exists;

  if not v_audit_exists then
    perform public.platform_write_wcm_lifecycle_rollback_audit(
      '{{WCM_TENANT_ID}}'::uuid,
      v_request_id,
      '{{WCM_BASE_EMPLOYEE_ID}}'::uuid,
      501,
      'signal_only_reversal',
      'no_downstream_artifact',
      false,
      '{{WCM_USER_ID}}'::uuid,
      'wcm_core_certification_seed',
      jsonb_build_object('certification_module', 'WCM_CORE', 'run_id', '{{RUN_ID}}', 'fixture', 'rollback_audit')
    );
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
