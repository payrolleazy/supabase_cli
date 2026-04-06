delete from public.platform_gateway_request_log
where actor_user_id = '{{HIER_USER_ID}}'::uuid
   or tenant_id in (select tenant_id from public.platform_tenant where tenant_code = 'hier_' || left(replace('{{RUN_ID}}', '-', ''), 12));

delete from public.platform_gateway_idempotency_claim
where actor_user_id = '{{HIER_USER_ID}}'::uuid
   or tenant_id in (select tenant_id from public.platform_tenant where tenant_code = 'hier_' || left(replace('{{RUN_ID}}', '-', ''), 12));

delete from public.platform_hierarchy_backup_log
where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = 'hier_' || left(replace('{{RUN_ID}}', '-', ''), 12));

delete from public.platform_hierarchy_error_log
where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = 'hier_' || left(replace('{{RUN_ID}}', '-', ''), 12));

delete from public.platform_hierarchy_performance_log
where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = 'hier_' || left(replace('{{RUN_ID}}', '-', ''), 12));

delete from public.platform_hierarchy_health_status
where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = 'hier_' || left(replace('{{RUN_ID}}', '-', ''), 12));

delete from public.platform_hierarchy_metadata
where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = 'hier_' || left(replace('{{RUN_ID}}', '-', ''), 12));

delete from public.platform_actor_role_grant where actor_user_id = '{{HIER_USER_ID}}'::uuid;
delete from public.platform_actor_tenant_membership where actor_user_id = '{{HIER_USER_ID}}'::uuid;
delete from public.platform_actor_profile where actor_user_id = '{{HIER_USER_ID}}'::uuid;
delete from public.platform_tenant_provisioning where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = 'hier_' || left(replace('{{RUN_ID}}', '-', ''), 12));
delete from public.platform_tenant_access_state where tenant_id in (select tenant_id from public.platform_tenant where tenant_code = 'hier_' || left(replace('{{RUN_ID}}', '-', ''), 12));
delete from public.platform_tenant where tenant_code = 'hier_' || left(replace('{{RUN_ID}}', '-', ''), 12);
delete from public.platform_hierarchy_maintenance_run where trigger_source = 'gateway_certification';

do $$ begin execute format('drop schema if exists %I cascade', 'tenant_hier_' || left(replace('{{RUN_ID}}', '-', ''), 12)); end; $$;

delete from auth.users where id = '{{HIER_USER_ID}}'::uuid;

select json_build_object('HIER_CLEANUP_COMPLETE', true)::text;
