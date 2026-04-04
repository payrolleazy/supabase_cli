do $$
declare
  v_tenant_id uuid := gen_random_uuid();
  v_tenant_code text := 'wcm_' || left(replace('{{RUN_ID}}', '-', ''), 12);
  v_schema_name text := 'tenant_wcm_' || left(replace('{{RUN_ID}}', '-', ''), 12);
  v_apply_result jsonb;
  v_register_result jsonb;
  v_service_state_result jsonb;
  v_base_employee_id uuid;
  v_base_employee_code text := 'WCM-BASE-' || left(replace('{{RUN_ID}}', '-', ''), 12);
  v_gateway_user_id uuid := public.platform_try_uuid('{{WCM_USER_ID}}');
  v_gateway_email text := nullif('{{WCM_EMAIL}}', '');
begin
  if v_gateway_user_id is null then
    raise exception 'WCM fixture requires WCM_USER_ID token';
  end if;

  delete from public.platform_gateway_request_log
  where actor_user_id = v_gateway_user_id;

  delete from public.platform_gateway_idempotency_claim
  where actor_user_id = v_gateway_user_id;

  delete from public.platform_wcm_lifecycle_event_queue
  where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);

  delete from public.platform_wcm_lifecycle_rollback_audit
  where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);

  delete from public.platform_wcm_resignation_request
  where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);

  delete from public.platform_actor_role_grant
  where actor_user_id = v_gateway_user_id;

  delete from public.platform_actor_tenant_membership
  where actor_user_id = v_gateway_user_id;

  delete from public.platform_actor_profile
  where actor_user_id = v_gateway_user_id;

  delete from public.platform_tenant_provisioning
  where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);

  delete from public.platform_tenant_access_state
  where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);

  delete from public.platform_tenant
  where tenant_code = v_tenant_code;

  execute format('drop schema if exists %I cascade', v_schema_name);
  execute format('create schema %I', v_schema_name);

  insert into public.platform_tenant (
    tenant_id, tenant_code, schema_name, display_name, legal_name, metadata
  ) values (
    v_tenant_id,
    v_tenant_code,
    v_schema_name,
    'WCM Core Runtime Tenant',
    'WCM Core Runtime Tenant Legal',
    jsonb_build_object('certification_module', 'WCM_CORE', 'run_id', '{{RUN_ID}}')
  );

  insert into public.platform_tenant_provisioning (
    tenant_id, provisioning_status, schema_provisioned, foundation_version, latest_completed_step, ready_for_routing, details
  ) values (
    v_tenant_id,
    'ready_for_routing',
    true,
    'local_wcm_core_cert',
    'ready_for_routing',
    true,
    jsonb_build_object('certification_module', 'WCM_CORE', 'run_id', '{{RUN_ID}}')
  );

  insert into public.platform_tenant_access_state (
    tenant_id, access_state, billing_state, reason_details
  ) values (
    v_tenant_id,
    'active',
    'current',
    jsonb_build_object('certification_module', 'WCM_CORE', 'run_id', '{{RUN_ID}}')
  );

  insert into public.platform_actor_profile (
    actor_user_id, primary_email, display_name, profile_status, email_verified, created_via, metadata
  ) values (
    v_gateway_user_id,
    v_gateway_email,
    'WCM Core Certification User',
    'active',
    true,
    'local_certification',
    jsonb_build_object('certification_module', 'WCM_CORE', 'run_id', '{{RUN_ID}}')
  ) on conflict (actor_user_id) do update
  set primary_email = excluded.primary_email,
      display_name = excluded.display_name,
      profile_status = excluded.profile_status,
      email_verified = excluded.email_verified,
      created_via = excluded.created_via,
      metadata = excluded.metadata;

  insert into public.platform_actor_tenant_membership (
    tenant_id, actor_user_id, membership_status, is_default_tenant, routing_status, metadata
  ) values (
    v_tenant_id,
    v_gateway_user_id,
    'active',
    true,
    'enabled',
    jsonb_build_object('certification_module', 'WCM_CORE', 'run_id', '{{RUN_ID}}')
  ) on conflict (tenant_id, actor_user_id) do update
  set membership_status = excluded.membership_status,
      is_default_tenant = excluded.is_default_tenant,
      routing_status = excluded.routing_status,
      metadata = excluded.metadata;

  insert into public.platform_actor_role_grant (
    tenant_id, actor_user_id, role_code, grant_status, metadata
  ) values (
    v_tenant_id,
    v_gateway_user_id,
    'tenant_owner_admin',
    'active',
    jsonb_build_object('certification_module', 'WCM_CORE', 'run_id', '{{RUN_ID}}', 'role_code', 'tenant_owner_admin')
  ) on conflict (tenant_id, actor_user_id, role_code) do update
  set grant_status = excluded.grant_status,
      metadata = excluded.metadata;

  if exists (select 1 from public.platform_access_role where role_code = 'i01_portal_user') then
    insert into public.platform_actor_role_grant (
      tenant_id, actor_user_id, role_code, grant_status, metadata
    ) values (
      v_tenant_id,
      v_gateway_user_id,
      'i01_portal_user',
      'active',
      jsonb_build_object('certification_module', 'WCM_CORE', 'run_id', '{{RUN_ID}}', 'role_code', 'i01_portal_user')
    ) on conflict (tenant_id, actor_user_id, role_code) do update
    set grant_status = excluded.grant_status,
        metadata = excluded.metadata;
  end if;

  v_apply_result := public.platform_apply_wcm_core_to_tenant(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'source', 'wcm_core_suite_setup'
  ));
  if not coalesce((v_apply_result->>'success')::boolean, false) then
    raise exception 'WCM fixture apply-to-tenant failed: %', v_apply_result::text;
  end if;

  v_register_result := public.platform_register_wcm_employee(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'employee_code', v_base_employee_code,
    'first_name', 'Baseline',
    'last_name', 'Employee',
    'official_email', 'wcm.base.' || left(replace('{{RUN_ID}}', '-', ''), 12) || '@example.test'
  ));
  if not coalesce((v_register_result->>'success')::boolean, false) then
    raise exception 'WCM fixture base employee register failed: %', v_register_result::text;
  end if;

  v_base_employee_id := public.platform_try_uuid(v_register_result->'details'->>'employee_id');
  if v_base_employee_id is null then
    raise exception 'WCM fixture base employee register returned no employee id: %', v_register_result::text;
  end if;

  v_service_state_result := public.platform_upsert_wcm_service_state(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'employee_id', v_base_employee_id,
    'joining_date', '2025-01-01',
    'service_state', 'active',
    'employment_status', 'active',
    'position_id', 501,
    'last_billable', true,
    'state_notes', jsonb_build_object('certification_module', 'WCM_CORE', 'run_id', '{{RUN_ID}}', 'seed', 'base_employee'),
    'event_reason', 'wcm_core_suite_setup',
    'source_module', 'WCM_CORE'
  ));
  if not coalesce((v_service_state_result->>'success')::boolean, false) then
    raise exception 'WCM fixture base service state upsert failed: %', v_service_state_result::text;
  end if;

  perform set_config('wcm_core.tenant_id', v_tenant_id::text, false);
  perform set_config('wcm_core.base_employee_id', v_base_employee_id::text, false);
end;
$$;

select json_build_object(
  'WCM_TENANT_ID',
  current_setting('wcm_core.tenant_id', true),
  'WCM_BASE_EMPLOYEE_ID',
  current_setting('wcm_core.base_employee_id', true)
)::text;

