create index if not exists idx_platform_read_model_refresh_run_tenant_id
on public.platform_read_model_refresh_run (tenant_id);

revoke all on public.platform_rm_refresh_overview from anon, authenticated;
grant select on public.platform_rm_refresh_overview to service_role;;
