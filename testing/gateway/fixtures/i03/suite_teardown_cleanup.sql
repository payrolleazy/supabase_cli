delete from public.platform_gateway_request_log
where actor_user_id = '{{I03_USER_ID}}'::uuid
   or tenant_id in (
     select tenant_id
     from public.platform_tenant
     where tenant_code = 'i03_' || left(replace('{{RUN_ID}}', '-', ''), 12)
   );

delete from public.platform_gateway_idempotency_claim
where actor_user_id = '{{I03_USER_ID}}'::uuid
   or tenant_id in (
     select tenant_id
     from public.platform_tenant
     where tenant_code = 'i03_' || left(replace('{{RUN_ID}}', '-', ''), 12)
   );

delete from public.platform_actor_role_grant
where actor_user_id = '{{I03_USER_ID}}'::uuid;

delete from public.platform_actor_tenant_membership
where actor_user_id = '{{I03_USER_ID}}'::uuid;

delete from public.platform_actor_profile
where actor_user_id = '{{I03_USER_ID}}'::uuid;

delete from public.platform_tenant_provisioning
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i03_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_tenant_access_state
where tenant_id in (
  select tenant_id
  from public.platform_tenant
  where tenant_code = 'i03_' || left(replace('{{RUN_ID}}', '-', ''), 12)
);

delete from public.platform_tenant
where tenant_code = 'i03_' || left(replace('{{RUN_ID}}', '-', ''), 12);

do $$
begin
  execute format('drop schema if exists %I cascade', 'tenant_i03_' || left(replace('{{RUN_ID}}', '-', ''), 12));
end;
$$;

delete from auth.users
where id = '{{I03_USER_ID}}'::uuid;

select json_build_object(
  'I03_CLEANUP_COMPLETE',
  true
)::text;
