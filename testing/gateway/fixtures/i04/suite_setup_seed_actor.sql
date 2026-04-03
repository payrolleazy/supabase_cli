do $$
declare
  v_tenant_id uuid := gen_random_uuid();
  v_tenant_code text := 'i04_' || left(replace('{{RUN_ID}}', '-', ''), 12);
  v_schema_name text := 'tenant_i04_' || left(replace('{{RUN_ID}}', '-', ''), 12);
begin
  delete from public.platform_gateway_request_log
  where actor_user_id = '{{I04_USER_ID}}'::uuid;

  delete from public.platform_gateway_idempotency_claim
  where actor_user_id = '{{I04_USER_ID}}'::uuid;

  delete from public.platform_actor_role_grant
  where actor_user_id = '{{I04_USER_ID}}'::uuid;

  delete from public.platform_actor_tenant_membership
  where actor_user_id = '{{I04_USER_ID}}'::uuid;

  delete from public.platform_actor_profile
  where actor_user_id = '{{I04_USER_ID}}'::uuid;

  delete from public.platform_tenant_provisioning
  where tenant_id in (
    select tenant_id
    from public.platform_tenant
    where tenant_code = v_tenant_code
  );

  delete from public.platform_tenant_access_state
  where tenant_id in (
    select tenant_id
    from public.platform_tenant
    where tenant_code = v_tenant_code
  );

  delete from public.platform_tenant
  where tenant_code = v_tenant_code;

  execute format('drop schema if exists %I cascade', v_schema_name);
  execute format('create schema %I', v_schema_name);

  insert into public.platform_tenant (
    tenant_id,
    tenant_code,
    schema_name,
    display_name,
    legal_name,
    metadata
  )
  values (
    v_tenant_id,
    v_tenant_code,
    v_schema_name,
    'I04 Runtime Tenant',
    'I04 Runtime Tenant Legal',
    jsonb_build_object('certification_module', 'I04', 'run_id', '{{RUN_ID}}')
  );

  insert into public.platform_tenant_provisioning (
    tenant_id,
    provisioning_status,
    schema_provisioned,
    foundation_version,
    latest_completed_step,
    ready_for_routing,
    details
  )
  values (
    v_tenant_id,
    'ready_for_routing',
    true,
    'local_i04_cert',
    'ready_for_routing',
    true,
    jsonb_build_object('certification_module', 'I04', 'run_id', '{{RUN_ID}}')
  );

  insert into public.platform_tenant_access_state (
    tenant_id,
    access_state,
    billing_state,
    reason_details
  )
  values (
    v_tenant_id,
    'active',
    'current',
    jsonb_build_object('certification_module', 'I04')
  );

  insert into public.platform_actor_profile (
    actor_user_id,
    primary_email,
    display_name,
    profile_status,
    email_verified,
    created_via,
    metadata
  )
  values (
    '{{I04_USER_ID}}'::uuid,
    '{{I04_EMAIL}}',
    'I04 Certification User',
    'active',
    true,
    'local_certification',
    jsonb_build_object('certification_module', 'I04', 'run_id', '{{RUN_ID}}')
  );

  insert into public.platform_actor_tenant_membership (
    tenant_id,
    actor_user_id,
    membership_status,
    is_default_tenant,
    routing_status,
    metadata
  )
  values (
    v_tenant_id,
    '{{I04_USER_ID}}'::uuid,
    'active',
    true,
    'enabled',
    jsonb_build_object('certification_module', 'I04', 'run_id', '{{RUN_ID}}')
  );

  insert into public.platform_actor_role_grant (
    tenant_id,
    actor_user_id,
    role_code,
    grant_status,
    metadata
  )
  values (
    v_tenant_id,
    '{{I04_USER_ID}}'::uuid,
    'tenant_owner_admin',
    'active',
    jsonb_build_object('certification_module', 'I04', 'run_id', '{{RUN_ID}}', 'role_code', 'tenant_owner_admin')
  );

  if exists (
    select 1
    from public.platform_access_role
    where role_code = 'i01_portal_user'
  ) then
    insert into public.platform_actor_role_grant (
      tenant_id,
      actor_user_id,
      role_code,
      grant_status,
      metadata
    )
    values (
      v_tenant_id,
      '{{I04_USER_ID}}'::uuid,
      'i01_portal_user',
      'active',
      jsonb_build_object('certification_module', 'I04', 'run_id', '{{RUN_ID}}', 'role_code', 'i01_portal_user')
    );
  end if;
end;
$$;

select json_build_object(
  'I04_TENANT_ID',
  (
    select tenant_id::text
    from public.platform_tenant
    where tenant_code = 'i04_' || left(replace('{{RUN_ID}}', '-', ''), 12)
  )
)::text;
