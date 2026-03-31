create index if not exists idx_platform_tenant_template_version_run_id
  on public.platform_tenant_template_version (run_id);

create index if not exists idx_platform_tenant_template_version_template_version
  on public.platform_tenant_template_version (template_version);;
