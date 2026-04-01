create or replace function public.platform_f06_run_refresh_overview_scheduler()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_request_result jsonb;
  v_execute_result jsonb;
  v_run_id uuid;
  v_status text;
begin
  v_request_result := public.platform_request_read_model_refresh(
    jsonb_build_object(
      'read_model_code', 'platform_refresh_overview',
      'refresh_trigger', 'schedule',
      'requested_by', 'platform_f06_cron'
    )
  );

  if coalesce((v_request_result->>'success')::boolean, false) is not true then
    return v_request_result;
  end if;

  v_run_id := nullif(v_request_result->'details'->>'run_id', '')::uuid;
  v_status := coalesce(v_request_result->'details'->>'status', '');

  if v_run_id is null then
    return public.platform_json_response(
      false,
      'RUN_ID_MISSING',
      'Refresh request did not return a run_id.',
      jsonb_build_object('request_result', v_request_result)
    );
  end if;

  if v_status <> 'queued' then
    return public.platform_json_response(
      true,
      'OK',
      'Refresh request already in-flight or reused.',
      jsonb_build_object('run_id', v_run_id, 'status', v_status, 'request_result', v_request_result)
    );
  end if;

  v_execute_result := public.platform_execute_read_model_refresh(
    jsonb_build_object(
      'run_id', v_run_id,
      'capture_row_count', true
    )
  );

  return v_execute_result;
exception
  when others then
    return public.platform_json_response(
      false,
      'UNEXPECTED_ERROR',
      'Unexpected error in platform_f06_run_refresh_overview_scheduler.',
      jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
    );
end;
$function$;

revoke all on function public.platform_f06_run_refresh_overview_scheduler() from public, anon, authenticated, service_role;

revoke execute on function public.platform_request_read_model_refresh(jsonb) from public, anon, authenticated;
revoke execute on function public.platform_execute_read_model_refresh(jsonb) from public, anon, authenticated;
revoke execute on function public.platform_get_read_model_refresh_status(jsonb) from public, anon, authenticated;
revoke execute on function public.platform_begin_read_model_refresh(jsonb) from public, anon, authenticated;
revoke execute on function public.platform_complete_read_model_refresh(jsonb) from public, anon, authenticated;
revoke execute on function public.platform_fail_read_model_refresh(jsonb) from public, anon, authenticated;

grant execute on function public.platform_request_read_model_refresh(jsonb) to service_role;
grant execute on function public.platform_execute_read_model_refresh(jsonb) to service_role;
grant execute on function public.platform_get_read_model_refresh_status(jsonb) to service_role;
grant execute on function public.platform_begin_read_model_refresh(jsonb) to service_role;
grant execute on function public.platform_complete_read_model_refresh(jsonb) to service_role;
grant execute on function public.platform_fail_read_model_refresh(jsonb) to service_role;

update public.platform_read_model_catalog
set refresh_strategy = 'scheduled',
    notes = case
      when notes is null or btrim(notes) = '' then 'Scheduled every 30 minutes via F06 hardened cron.'
      when notes ilike '%Scheduled every 30 minutes via F06 hardened cron.%' then notes
      else notes || ' Scheduled every 30 minutes via F06 hardened cron.'
    end,
    updated_at = timezone('utc', now())
where read_model_code = 'platform_refresh_overview';

do $do$
declare
  v_command text := 'select public.platform_f06_run_refresh_overview_scheduler();';
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'f06-refresh-overview'
  ) then
    update cron.job
    set schedule = '*/30 * * * *',
        command = v_command,
        active = true
    where jobname = 'f06-refresh-overview';
  else
    perform cron.schedule('f06-refresh-overview', '*/30 * * * *', v_command);
  end if;
end;
$do$;

do $do$
declare
  v_result jsonb;
begin
  v_result := public.platform_f06_run_refresh_overview_scheduler();

  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'F06 initial refresh overview run failed: %', v_result::text;
  end if;
end;
$do$;
