do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    create extension pg_cron with schema pg_catalog;
  end if;
end;
$$;

do $$
declare
  v_command text := 'select public.platform_commercial_orchestrator(''{"tenant_limit":50,"max_cycles_per_tenant":10,"run_settlement":true,"run_overdue_sync":true}''::jsonb);';
begin
  if exists (select 1 from cron.job where jobname = 'f05-commercial-orchestrator') then
    update cron.job
    set schedule = '15 0 * * *',
        command = v_command,
        database = current_database(),
        username = current_user,
        active = true
    where jobname = 'f05-commercial-orchestrator';
  else
    perform cron.schedule('f05-commercial-orchestrator', '15 0 * * *', v_command);
  end if;
end;
$$;
