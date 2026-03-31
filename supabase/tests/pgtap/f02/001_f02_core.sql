begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(13);

select has_table('public', 'platform_template_version', 'F02 exposes the template-version registry table.');
select has_table('public', 'platform_template_table_registry', 'F02 exposes the template-table registry table.');
select has_table('public', 'platform_schema_provisioning_run', 'F02 exposes the provisioning-run audit table.');
select has_table('public', 'platform_tenant_template_version', 'F02 exposes the per-tenant applied-version table.');
select has_view('public', 'platform_schema_provisioning_view', 'F02 exposes the provisioning state view.');
select has_view('public', 'platform_rm_schema_provisioning', 'F06 wrapper view over F02 provisioning state is present.');
select has_function('public', 'platform_generate_schema_name', array['jsonb'], 'F02 schema-name contract exists.');
select has_function('public', 'platform_register_template_version', array['jsonb'], 'F02 template-version registration contract exists.');
select has_function('public', 'platform_register_template_table', array['jsonb'], 'F02 template-table registration contract exists.');
select has_function('public', 'platform_create_tenant_schema', array['jsonb'], 'F02 tenant-schema creation contract exists.');
select has_function('public', 'platform_apply_template_version_to_tenant', array['jsonb'], 'F02 template-application contract exists.');
select has_function('public', 'platform_get_tenant_schema_state', array['jsonb'], 'F02 schema-state read contract exists.');
select has_function('public', 'platform_clone_registered_template_tables', array['uuid', 'text'], 'F02 clone helper exists.');

select * from finish();

rollback;
