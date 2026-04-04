revoke all on function public.platform_i06_cleanup_expired_import_sessions(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_i06_cleanup_expired_export_artifacts(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_i06_run_exchange_maintenance(jsonb) from public, anon, authenticated, service_role;
revoke all on function public.platform_i06_run_runtime_scheduler() from public, anon, authenticated, service_role;

grant execute on function public.platform_i06_cleanup_expired_import_sessions(jsonb) to service_role;
grant execute on function public.platform_i06_cleanup_expired_export_artifacts(jsonb) to service_role;
grant execute on function public.platform_i06_run_exchange_maintenance(jsonb) to service_role;
grant execute on function public.platform_i06_run_runtime_scheduler() to service_role;
