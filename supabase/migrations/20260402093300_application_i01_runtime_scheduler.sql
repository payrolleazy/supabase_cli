create or replace function public.platform_i01_run_signup_orchestrator_scheduler()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_supabase_url text;
  v_service_role_key text;
  v_request_id bigint;
begin
  select decrypted_secret
  into v_supabase_url
  from vault.decrypted_secrets
  where name = 'supabase_url'
  order by created_at desc
  limit 1;

  select decrypted_secret
  into v_service_role_key
  from vault.decrypted_secrets
  where name = 'service_role_key'
  order by created_at desc
  limit 1;

  if coalesce(v_supabase_url, '') = '' then
    return public.platform_json_response(false, 'MISSING_SUPABASE_URL_SECRET', 'Vault secret supabase_url is missing.', '{}'::jsonb);
  end if;

  if coalesce(v_service_role_key, '') = '' then
    return public.platform_json_response(false, 'MISSING_SERVICE_ROLE_KEY_SECRET', 'Vault secret service_role_key is missing.', '{}'::jsonb);
  end if;

  select net.http_post(
    url := rtrim(v_supabase_url, '/') || '/functions/v1/identity-signup-orchestrator',
    body := jsonb_build_object('source', 'pg_cron'),
    params := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_role_key,
      'apikey', v_service_role_key,
      'x-client-info', 'i01-signup-orchestrator-cron'
    ),
    timeout_milliseconds := 15000
  )
  into v_request_id;

  return public.platform_json_response(true, 'OK', 'I01 signup orchestrator triggered.', jsonb_build_object('request_id', v_request_id));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_i01_run_signup_orchestrator_scheduler.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_i01_run_signin_cleanup_scheduler()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  return public.platform_cleanup_signin_runtime(jsonb_build_object(
    'attempt_retention_days', 30,
    'challenge_retention_days', 7,
    'source', 'pg_cron'
  ));
end;
$function$;

revoke all on function public.platform_i01_run_signup_orchestrator_scheduler() from public, anon, authenticated;
revoke all on function public.platform_i01_run_signin_cleanup_scheduler() from public, anon, authenticated;

grant execute on function public.platform_i01_run_signup_orchestrator_scheduler() to service_role;
grant execute on function public.platform_i01_run_signin_cleanup_scheduler() to service_role;

do $$
declare
  v_signup_command text := 'select public.platform_i01_run_signup_orchestrator_scheduler();';
  v_signin_cleanup_command text := 'select public.platform_i01_run_signin_cleanup_scheduler();';
begin
  if exists (select 1 from cron.job where jobname = 'i01-signup-orchestrator') then
    update cron.job
    set schedule = '* * * * *',
        command = v_signup_command,
        database = current_database(),
        username = current_user,
        active = true
    where jobname = 'i01-signup-orchestrator';
  else
    perform cron.schedule('i01-signup-orchestrator', '* * * * *', v_signup_command);
  end if;

  if exists (select 1 from cron.job where jobname = 'i01-signin-cleanup') then
    update cron.job
    set schedule = '*/30 * * * *',
        command = v_signin_cleanup_command,
        database = current_database(),
        username = current_user,
        active = true
    where jobname = 'i01-signin-cleanup';
  else
    perform cron.schedule('i01-signin-cleanup', '*/30 * * * *', v_signin_cleanup_command);
  end if;
end;
$$;