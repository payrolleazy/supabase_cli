delete from public.platform_gateway_request_log
where actor_user_id in (
  select user_id
  from unnest(array[
    public.platform_try_uuid('{{I05_GATEWAY_USER_ID}}'),
    public.platform_try_uuid('{{I05_EDGE_USER_ID}}')
  ]) as user_id
  where user_id is not null
)
   or tenant_id in (
     select tenant_id
     from public.platform_tenant
     where tenant_code = 'i05_' || left(replace('{{RUN_ID}}', '-', ''), 12)
   );

delete from public.platform_gateway_idempotency_claim
where actor_user_id in (
  select user_id
  from unnest(array[
    public.platform_try_uuid('{{I05_GATEWAY_USER_ID}}'),
    public.platform_try_uuid('{{I05_EDGE_USER_ID}}')
  ]) as user_id
  where user_id is not null
)
   or tenant_id in (
     select tenant_id
     from public.platform_tenant
     where tenant_code = 'i05_' || left(replace('{{RUN_ID}}', '-', ''), 12)
   );

delete from public.platform_document_binding
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i05_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_document_record
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i05_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_document_upload_intent
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i05_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_document_event_log
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i05_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_actor_role_grant
where actor_user_id in (
  select user_id
  from unnest(array[
    public.platform_try_uuid('{{I05_GATEWAY_USER_ID}}'),
    public.platform_try_uuid('{{I05_EDGE_USER_ID}}')
  ]) as user_id
  where user_id is not null
);

delete from public.platform_actor_tenant_membership
where actor_user_id in (
  select user_id
  from unnest(array[
    public.platform_try_uuid('{{I05_GATEWAY_USER_ID}}'),
    public.platform_try_uuid('{{I05_EDGE_USER_ID}}')
  ]) as user_id
  where user_id is not null
);

delete from public.platform_actor_profile
where actor_user_id in (
  select user_id
  from unnest(array[
    public.platform_try_uuid('{{I05_GATEWAY_USER_ID}}'),
    public.platform_try_uuid('{{I05_EDGE_USER_ID}}')
  ]) as user_id
  where user_id is not null
);

delete from public.platform_tenant_provisioning
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i05_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_tenant_access_state
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i05_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_tenant
where tenant_code = 'i05_' || left(replace('{{RUN_ID}}', '-', ''), 12);

do $$
begin
  execute format('drop schema if exists %I cascade', 'tenant_i05_' || left(replace('{{RUN_ID}}', '-', ''), 12));
end;
$$;

delete from auth.users
where id in (
  select user_id
  from unnest(array[
    public.platform_try_uuid('{{I05_GATEWAY_USER_ID}}'),
    public.platform_try_uuid('{{I05_EDGE_USER_ID}}')
  ]) as user_id
  where user_id is not null
);

select json_build_object(
  'I05_CLEANUP_COMPLETE',
  true
)::text;
