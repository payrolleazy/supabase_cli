create or replace function public.platform_wcm_internal_resolve_context(p_tenant_id uuid, p_source text default 'platform_wcm_internal_resolve_context')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_result jsonb;
  v_details jsonb;
  v_current_tenant_id uuid := public.platform_current_tenant_id();
  v_current_schema text := public.platform_current_tenant_schema();
begin
  if p_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id is required.', '{}'::jsonb);
  end if;

  if v_current_tenant_id is not null and v_current_schema is not null then
    if p_tenant_id <> v_current_tenant_id then
      return public.platform_json_response(
        false,
        'CONTEXT_TENANT_MISMATCH',
        'The requested tenant does not match the current execution context.',
        jsonb_build_object(
          'requested_tenant_id', p_tenant_id,
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
      'WCM internal execution context resolved.',
      jsonb_build_object(
        'tenant_id', v_current_tenant_id,
        'tenant_schema', v_current_schema,
        'actor_user_id', public.platform_current_actor_user_id(),
        'execution_mode', public.platform_current_execution_mode()
      )
    );
  end if;

  v_result := public.platform_apply_execution_context(jsonb_build_object(
    'execution_mode', 'internal_platform',
    'tenant_id', p_tenant_id,
    'source', coalesce(nullif(btrim(p_source), ''), 'platform_wcm_internal_resolve_context')
  ));

  if coalesce((v_result->>'success')::boolean, false) is not true then
    return v_result;
  end if;

  v_details := coalesce(v_result->'details', '{}'::jsonb);

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
    'WCM internal execution context resolved.',
    jsonb_build_object(
      'tenant_id', public.platform_try_uuid(v_details->>'tenant_id'),
      'tenant_schema', v_details->>'tenant_schema',
      'actor_user_id', public.platform_current_actor_user_id(),
      'execution_mode', coalesce(v_details->>'execution_mode', public.platform_current_execution_mode())
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_wcm_internal_resolve_context.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;
