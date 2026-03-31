begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

select has_table('public', 'platform_tenant', 'F01 exposes the core platform_tenant table.');
select has_table('public', 'platform_tenant_provisioning', 'F01 exposes the tenant provisioning table.');
select has_table('public', 'platform_tenant_access_state', 'F01 exposes the tenant access state table.');
select has_table('public', 'platform_tenant_status_history', 'F01 exposes the tenant status history table.');
select has_view('public', 'platform_tenant_registry_view', 'F01 exposes the governed tenant registry view.');
select has_view('public', 'platform_rm_tenant_registry', 'F06 wrapper view over F01 registry is present.');
select has_function('public', 'platform_create_tenant_registry', array['jsonb'], 'F01 create tenant lifecycle entrypoint exists.');
select has_function('public', 'platform_get_tenant_registry', array['jsonb'], 'F01 read registry entrypoint exists.');
select has_function('public', 'platform_get_tenant_access_gate', array['jsonb'], 'F01 access gate entrypoint exists.');

select * from finish();

rollback;
