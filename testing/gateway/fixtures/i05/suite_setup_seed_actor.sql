do $$
declare
  v_tenant_id uuid := gen_random_uuid();
  v_tenant_code text := 'i05_' || left(replace('{{RUN_ID}}', '-', ''), 12);
  v_schema_name text := 'tenant_i05_' || left(replace('{{RUN_ID}}', '-', ''), 12);
  v_document_id uuid := gen_random_uuid();
  v_object_name text;
  v_gateway_user_id uuid := public.platform_try_uuid('{{I05_GATEWAY_USER_ID}}');
  v_edge_user_id uuid := public.platform_try_uuid('{{I05_EDGE_USER_ID}}');
  v_gateway_email text := nullif('{{I05_GATEWAY_EMAIL}}', '');
  v_edge_email text := nullif('{{I05_EDGE_EMAIL}}', '');
  v_actor_user_id uuid := coalesce(public.platform_try_uuid('{{I05_GATEWAY_USER_ID}}'), public.platform_try_uuid('{{I05_EDGE_USER_ID}}'));
  v_actor_email text := coalesce(nullif('{{I05_GATEWAY_EMAIL}}', ''), nullif('{{I05_EDGE_EMAIL}}', ''));
  v_actor_surface text := case
    when public.platform_try_uuid('{{I05_GATEWAY_USER_ID}}') is not null then 'gateway'
    when public.platform_try_uuid('{{I05_EDGE_USER_ID}}') is not null then 'edge'
    else 'unknown'
  end;
begin
  if v_actor_user_id is null then
    raise exception 'I05 fixture requires at least one actor user id token';
  end if;

  delete from public.platform_gateway_request_log
  where actor_user_id in (
    select user_id
    from unnest(array[v_gateway_user_id, v_edge_user_id]) as user_id
    where user_id is not null
  );

  delete from public.platform_gateway_idempotency_claim
  where actor_user_id in (
    select user_id
    from unnest(array[v_gateway_user_id, v_edge_user_id]) as user_id
    where user_id is not null
  );

  delete from public.platform_document_binding
  where tenant_id in (
    select tenant_id
    from public.platform_tenant
    where tenant_code = v_tenant_code
  );

  delete from public.platform_document_record
  where tenant_id in (
    select tenant_id
    from public.platform_tenant
    where tenant_code = v_tenant_code
  );

  delete from public.platform_document_upload_intent
  where tenant_id in (
    select tenant_id
    from public.platform_tenant
    where tenant_code = v_tenant_code
  );

  delete from public.platform_document_event_log
  where tenant_id in (
    select tenant_id
    from public.platform_tenant
    where tenant_code = v_tenant_code
  );

  delete from public.platform_actor_role_grant
  where actor_user_id in (
    select user_id
    from unnest(array[v_gateway_user_id, v_edge_user_id]) as user_id
    where user_id is not null
  );

  delete from public.platform_actor_tenant_membership
  where actor_user_id in (
    select user_id
    from unnest(array[v_gateway_user_id, v_edge_user_id]) as user_id
    where user_id is not null
  );

  delete from public.platform_actor_profile
  where actor_user_id in (
    select user_id
    from unnest(array[v_gateway_user_id, v_edge_user_id]) as user_id
    where user_id is not null
  );

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
    'I05 Runtime Tenant',
    'I05 Runtime Tenant Legal',
    jsonb_build_object('certification_module', 'I05', 'run_id', '{{RUN_ID}}')
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
    'local_i05_cert',
    'ready_for_routing',
    true,
    jsonb_build_object('certification_module', 'I05', 'run_id', '{{RUN_ID}}')
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
    jsonb_build_object('certification_module', 'I05')
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
    v_actor_user_id,
    v_actor_email,
    'I05 ' || initcap(v_actor_surface) || ' User',
    'active',
    true,
    'local_certification',
    jsonb_build_object('certification_module', 'I05', 'run_id', '{{RUN_ID}}', 'surface', v_actor_surface)
  )
  on conflict (actor_user_id) do update
  set
    primary_email = excluded.primary_email,
    display_name = excluded.display_name,
    profile_status = excluded.profile_status,
    email_verified = excluded.email_verified,
    created_via = excluded.created_via,
    metadata = excluded.metadata;

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
    v_actor_user_id,
    'active',
    true,
    'enabled',
    jsonb_build_object('certification_module', 'I05', 'run_id', '{{RUN_ID}}', 'surface', v_actor_surface)
  )
  on conflict (tenant_id, actor_user_id) do update
  set
    membership_status = excluded.membership_status,
    is_default_tenant = excluded.is_default_tenant,
    routing_status = excluded.routing_status,
    metadata = excluded.metadata;

  insert into public.platform_actor_role_grant (
    tenant_id,
    actor_user_id,
    role_code,
    grant_status,
    metadata
  )
  values
  (
    v_tenant_id,
    v_actor_user_id,
    'tenant_owner_admin',
    'active',
    jsonb_build_object('certification_module', 'I05', 'run_id', '{{RUN_ID}}', 'surface', v_actor_surface, 'role_code', 'tenant_owner_admin')
  ),
  (
    v_tenant_id,
    v_actor_user_id,
    'i05_proof_document_admin',
    'active',
    jsonb_build_object('certification_module', 'I05', 'run_id', '{{RUN_ID}}', 'surface', v_actor_surface, 'role_code', 'i05_proof_document_admin')
  )
  on conflict (tenant_id, actor_user_id, role_code) do update
  set
    grant_status = excluded.grant_status,
    metadata = excluded.metadata;

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
      v_actor_user_id,
      'i01_portal_user',
      'active',
      jsonb_build_object('certification_module', 'I05', 'run_id', '{{RUN_ID}}', 'surface', v_actor_surface, 'role_code', 'i01_portal_user')
    )
    on conflict (tenant_id, actor_user_id, role_code) do update
    set
      grant_status = excluded.grant_status,
      metadata = excluded.metadata;
  end if;

  v_object_name := v_tenant_id::text || '/i05_proof_employee_document/' || v_actor_user_id::text || '/runtime-seed/i05-proof-runtime.pdf';

  insert into public.platform_document_record (
    document_id,
    tenant_id,
    document_class_id,
    bucket_code,
    upload_intent_id,
    owner_actor_user_id,
    uploaded_by_actor_user_id,
    storage_object_name,
    original_file_name,
    content_type,
    file_size_bytes,
    checksum_sha256,
    protection_mode,
    access_mode,
    allowed_role_codes,
    document_status,
    version_no,
    storage_metadata,
    document_metadata
  )
  select
    v_document_id,
    v_tenant_id,
    document_class_id,
    default_bucket_code,
    null,
    v_actor_user_id,
    v_actor_user_id,
    v_object_name,
    'i05-proof-runtime.pdf',
    'application/pdf',
    47,
    '2ab94463e399ce58a21df28c88b429dd6c64637faadd1de7d8d44f10e4132415',
    default_protection_mode,
    default_access_mode,
    default_allowed_role_codes,
    'active',
    1,
    jsonb_build_object('certification_module', 'I05', 'run_id', '{{RUN_ID}}', 'seeded', true),
    jsonb_build_object('certification_module', 'I05', 'run_id', '{{RUN_ID}}', 'seeded', true)
  from public.platform_document_class
  where document_class_code = 'i05_proof_employee_document';
end;
$$;

select json_build_object(
  'I05_TENANT_ID',
  (
    select tenant_id::text
    from public.platform_tenant
    where tenant_code = 'i05_' || left(replace('{{RUN_ID}}', '-', ''), 12)
  ),
  'I05_DOCUMENT_ID',
  (
    select document_id::text
    from public.platform_document_record
    where original_file_name = 'i05-proof-runtime.pdf'
      and tenant_id = (
        select tenant_id
        from public.platform_tenant
        where tenant_code = 'i05_' || left(replace('{{RUN_ID}}', '-', ''), 12)
      )
  )
)::text;
