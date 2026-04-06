create temp table if not exists pg_temp.hierarchy_cert_tokens (
  token_key text primary key,
  token_value text not null
);
truncate table pg_temp.hierarchy_cert_tokens;

do $$
declare
  v_tenant_id uuid := gen_random_uuid();
  v_tenant_code text := 'hier_' || left(replace('{{RUN_ID}}', '-', ''), 12);
  v_schema_name text := 'tenant_hier_' || left(replace('{{RUN_ID}}', '-', ''), 12);
  v_hierarchy_result jsonb;
  v_wcm_result jsonb;
  v_manager_employee_id uuid := gen_random_uuid();
  v_report_employee_id uuid := gen_random_uuid();
  v_extra_employee_id uuid := gen_random_uuid();
  v_base_group_id bigint;
  v_root_position_id bigint;
  v_child_position_id bigint;
begin
  delete from public.platform_gateway_request_log where actor_user_id = '{{HIER_USER_ID}}'::uuid;
  delete from public.platform_gateway_idempotency_claim where actor_user_id = '{{HIER_USER_ID}}'::uuid;
  delete from public.platform_actor_role_grant where actor_user_id = '{{HIER_USER_ID}}'::uuid;
  delete from public.platform_actor_tenant_membership where actor_user_id = '{{HIER_USER_ID}}'::uuid;
  delete from public.platform_actor_profile where actor_user_id = '{{HIER_USER_ID}}'::uuid;
  delete from public.platform_tenant_provisioning where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_tenant_access_state where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = v_tenant_code);
  delete from public.platform_tenant where tenant_code = v_tenant_code;
  execute format('drop schema if exists %I cascade', v_schema_name);
  execute format('create schema %I', v_schema_name);

  insert into public.platform_tenant (tenant_id, tenant_code, schema_name, display_name, legal_name, metadata)
  values (v_tenant_id, v_tenant_code, v_schema_name, 'Hierarchy Runtime Tenant', 'Hierarchy Runtime Tenant Legal', jsonb_build_object('certification_module', 'HIERARCHY', 'run_id', '{{RUN_ID}}'));

  insert into public.platform_tenant_provisioning (tenant_id, provisioning_status, schema_provisioned, foundation_version, latest_completed_step, ready_for_routing, details)
  values (v_tenant_id, 'ready_for_routing', true, 'local_hierarchy_cert', 'ready_for_routing', true, jsonb_build_object('certification_module', 'HIERARCHY', 'run_id', '{{RUN_ID}}'));

  insert into public.platform_tenant_access_state (tenant_id, access_state, billing_state, reason_details)
  values (v_tenant_id, 'active', 'current', jsonb_build_object('certification_module', 'HIERARCHY'));

  insert into public.platform_actor_profile (actor_user_id, primary_email, display_name, profile_status, email_verified, created_via, metadata)
  values ('{{HIER_USER_ID}}'::uuid, '{{HIER_EMAIL}}', 'Hierarchy Certification User', 'active', true, 'local_certification', jsonb_build_object('certification_module', 'HIERARCHY', 'run_id', '{{RUN_ID}}'));

  insert into public.platform_actor_tenant_membership (tenant_id, actor_user_id, membership_status, is_default_tenant, routing_status, metadata)
  values (v_tenant_id, '{{HIER_USER_ID}}'::uuid, 'active', true, 'enabled', jsonb_build_object('certification_module', 'HIERARCHY', 'run_id', '{{RUN_ID}}'));

  insert into public.platform_actor_role_grant (tenant_id, actor_user_id, role_code, grant_status, metadata)
  values (v_tenant_id, '{{HIER_USER_ID}}'::uuid, 'tenant_owner_admin', 'active', jsonb_build_object('certification_module', 'HIERARCHY', 'run_id', '{{RUN_ID}}', 'role_code', 'tenant_owner_admin'));

  if exists (select 1 from public.platform_access_role where role_code = 'i01_portal_user') then
    insert into public.platform_actor_role_grant (tenant_id, actor_user_id, role_code, grant_status, metadata)
    values (v_tenant_id, '{{HIER_USER_ID}}'::uuid, 'i01_portal_user', 'active', jsonb_build_object('certification_module', 'HIERARCHY', 'run_id', '{{RUN_ID}}', 'role_code', 'i01_portal_user'));
  end if;

  v_hierarchy_result := public.platform_apply_hierarchy_to_tenant(jsonb_build_object('tenant_id', v_tenant_id));
  if coalesce((v_hierarchy_result->>'success')::boolean, false) is not true then
    raise exception 'HIERARCHY tenant apply failed: %', v_hierarchy_result::text;
  end if;

  v_wcm_result := public.platform_apply_wcm_core_to_tenant(jsonb_build_object('tenant_id', v_tenant_id));
  if coalesce((v_wcm_result->>'success')::boolean, false) is not true then
    raise exception 'WCM_CORE tenant apply failed: %', v_wcm_result::text;
  end if;

  execute format(
    'insert into %I.wcm_employee (employee_id, employee_code, first_name, last_name, official_email, actor_user_id)
     values ($1, $2, $3, $4, $5, $6), ($7, $8, $9, $10, $11, null), ($12, $13, $14, $15, $16, null)',
    v_schema_name
  )
  using
    v_manager_employee_id, 'HIER-MGR-{{RUN_ID}}', 'Hierarchy', 'Manager', 'hier.mgr.{{RUN_ID}}@example.test', '{{HIER_USER_ID}}'::uuid,
    v_report_employee_id, 'HIER-REP-{{RUN_ID}}', 'Hierarchy', 'Report', 'hier.rep.{{RUN_ID}}@example.test',
    v_extra_employee_id, 'HIER-EXT-{{RUN_ID}}', 'Hierarchy', 'Extra', 'hier.ext.{{RUN_ID}}@example.test';

  execute format(
    'insert into %I.wcm_employee_service_state (employee_id, joining_date, service_state, employment_status, last_billable, state_notes)
     values ($1, date ''2024-01-01'', ''active'', ''active'', true, $2), ($3, date ''2024-02-01'', ''active'', ''active'', true, $4), ($5, date ''2024-03-01'', ''active'', ''active'', true, $6)',
    v_schema_name
  )
  using
    v_manager_employee_id, jsonb_build_object('certification_module', 'HIERARCHY', 'run_id', '{{RUN_ID}}', 'seed', 'manager'),
    v_report_employee_id, jsonb_build_object('certification_module', 'HIERARCHY', 'run_id', '{{RUN_ID}}', 'seed', 'report'),
    v_extra_employee_id, jsonb_build_object('certification_module', 'HIERARCHY', 'run_id', '{{RUN_ID}}', 'seed', 'extra');

  execute format(
    'insert into %I.hierarchy_position_group (position_group_code, position_group_name, group_status, description)
     values ($1, $2, ''active'', $3)
     returning position_group_id',
    v_schema_name
  ) into v_base_group_id using 'hier-base-grp-{{RUN_ID}}', 'Hierarchy Base Group {{RUN_ID}}', 'HIERARCHY certification base group';

  execute format(
    'insert into %I.hierarchy_position (position_code, position_name, position_group_id, position_status, effective_start_date)
     values ($1, $2, $3, ''active'', date ''2024-01-01'') returning position_id',
    v_schema_name
  ) into v_root_position_id using 'hier-root-{{RUN_ID}}', 'Hierarchy Root Position {{RUN_ID}}', v_base_group_id;

  execute format(
    'insert into %I.hierarchy_position (position_code, position_name, position_group_id, reporting_position_id, position_status, effective_start_date)
     values ($1, $2, $3, $4, ''active'', date ''2024-02-01'') returning position_id',
    v_schema_name
  ) into v_child_position_id using 'hier-child-{{RUN_ID}}', 'Hierarchy Child Position {{RUN_ID}}', v_base_group_id, v_root_position_id;

  execute format('update %I.wcm_employee_service_state set position_id = $1 where employee_id = $2', v_schema_name) using v_root_position_id, v_manager_employee_id;
  execute format('update %I.wcm_employee_service_state set position_id = $1 where employee_id = $2', v_schema_name) using v_child_position_id, v_report_employee_id;

  execute format(
    'insert into %I.hierarchy_position_occupancy (employee_id, position_id, occupancy_role, effective_start_date, occupancy_status, occupancy_reason)
     values ($1, $2, ''primary'', date ''2024-01-01'', ''active'', ''hierarchy_base_manager''), ($3, $4, ''primary'', date ''2024-02-01'', ''active'', ''hierarchy_base_report'')',
    v_schema_name
  ) using v_manager_employee_id, v_root_position_id, v_report_employee_id, v_child_position_id;

  insert into pg_temp.hierarchy_cert_tokens (token_key, token_value) values
    ('HIER_TENANT_ID', v_tenant_id::text),
    ('HIER_MANAGER_EMPLOYEE_ID', v_manager_employee_id::text),
    ('HIER_REPORT_EMPLOYEE_ID', v_report_employee_id::text),
    ('HIER_EXTRA_EMPLOYEE_ID', v_extra_employee_id::text),
    ('HIER_ROOT_POSITION_ID', v_root_position_id::text),
    ('HIER_CHILD_POSITION_ID', v_child_position_id::text);
end;
$$;

select json_object_agg(token_key, token_value)::text from pg_temp.hierarchy_cert_tokens;
