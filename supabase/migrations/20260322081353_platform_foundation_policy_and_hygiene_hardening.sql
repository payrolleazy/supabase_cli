drop policy if exists platform_actor_tenant_membership_service_role_all on public.platform_actor_tenant_membership;
create policy platform_actor_tenant_membership_service_role_all
on public.platform_actor_tenant_membership
for all
to service_role
using (true)
with check (true);

drop policy if exists platform_async_job_service_role_all on public.platform_async_job;
create policy platform_async_job_service_role_all
on public.platform_async_job
for all
to service_role
using (true)
with check (true);

drop policy if exists platform_async_job_attempt_service_role_all on public.platform_async_job_attempt;
create policy platform_async_job_attempt_service_role_all
on public.platform_async_job_attempt
for all
to service_role
using (true)
with check (true);

drop policy if exists platform_async_worker_registry_service_role_all on public.platform_async_worker_registry;
create policy platform_async_worker_registry_service_role_all
on public.platform_async_worker_registry
for all
to service_role
using (true)
with check (true);

drop policy if exists platform_schema_provisioning_run_service_role_all on public.platform_schema_provisioning_run;
create policy platform_schema_provisioning_run_service_role_all
on public.platform_schema_provisioning_run
for all
to service_role
using (true)
with check (true);

drop policy if exists platform_template_table_registry_service_role_all on public.platform_template_table_registry;
create policy platform_template_table_registry_service_role_all
on public.platform_template_table_registry
for all
to service_role
using (true)
with check (true);

drop policy if exists platform_template_version_service_role_all on public.platform_template_version;
create policy platform_template_version_service_role_all
on public.platform_template_version
for all
to service_role
using (true)
with check (true);

drop policy if exists platform_tenant_service_role_all on public.platform_tenant;
create policy platform_tenant_service_role_all
on public.platform_tenant
for all
to service_role
using (true)
with check (true);

drop policy if exists platform_tenant_access_state_service_role_all on public.platform_tenant_access_state;
create policy platform_tenant_access_state_service_role_all
on public.platform_tenant_access_state
for all
to service_role
using (true)
with check (true);

drop policy if exists platform_tenant_provisioning_service_role_all on public.platform_tenant_provisioning;
create policy platform_tenant_provisioning_service_role_all
on public.platform_tenant_provisioning
for all
to service_role
using (true)
with check (true);

drop policy if exists platform_tenant_status_history_service_role_all on public.platform_tenant_status_history;
create policy platform_tenant_status_history_service_role_all
on public.platform_tenant_status_history
for all
to service_role
using (true)
with check (true);

drop policy if exists platform_tenant_template_version_service_role_all on public.platform_tenant_template_version;
create policy platform_tenant_template_version_service_role_all
on public.platform_tenant_template_version
for all
to service_role
using (true)
with check (true);

alter function public.platform_schema_exists(text) set search_path to 'public', 'pg_temp';
alter function public.platform_build_schema_name(text) set search_path to 'public', 'pg_temp';
alter function public.platform_table_exists(text, text) set search_path to 'public', 'pg_temp';
alter function public.platform_set_updated_at() set search_path to 'public', 'pg_temp';
alter function public.platform_json_response(boolean, text, text, jsonb) set search_path to 'public', 'pg_temp';
alter function public.platform_try_uuid(text) set search_path to 'public', 'pg_temp';
alter function public.platform_normalize_tenant_code(text) set search_path to 'public', 'pg_temp';
alter function public.platform_resolve_actor() set search_path to 'public', 'pg_temp';
alter function public.platform_access_transition_allowed(text, text) set search_path to 'public', 'pg_temp';
alter function public.platform_provisioning_transition_allowed(text, text) set search_path to 'public', 'pg_temp';

alter view public.platform_schema_provisioning_view set (security_invoker = true);;
