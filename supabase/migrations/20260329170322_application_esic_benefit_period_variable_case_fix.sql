create or replace function public.platform_esic_refresh_benefit_period_internal(
  p_schema_name text,
  p_employee_id uuid,
  p_payroll_period date,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_window jsonb := public.platform_esic_benefit_period_window(p_payroll_period);
  v_contribution_start date := public.platform_esic_try_date(v_window->>'contribution_period_start');
  v_contribution_end date := public.platform_esic_try_date(v_window->>'contribution_period_end');
  v_benefit_start date := public.platform_esic_try_date(v_window->>'benefit_period_start');
  v_benefit_end date := public.platform_esic_try_date(v_window->>'benefit_period_end');
  v_total_days numeric(10,2);
  v_total_wages numeric(14,2);
  v_benefit_period_id uuid;
begin
  execute format(
    'select coalesce(sum(worked_days), 0), coalesce(sum(eligible_wages), 0)
       from %I.wcm_esic_contribution_ledger
      where employee_id = $1
        and payroll_period between $2 and $3',
    p_schema_name
  ) into v_total_days, v_total_wages using p_employee_id, v_contribution_start, v_contribution_end;

  execute format(
    'insert into %I.wcm_esic_employee_benefit_period (employee_id, contribution_period_start, contribution_period_end, benefit_period_start, benefit_period_end, total_days_worked, total_wages_paid, minimum_days_required, is_eligible, eligibility_details, last_calculated_at, calculated_by_actor_user_id, calculation_version)
     values ($1,$2,$3,$4,$5,$6,$7,78,$8,$9,timezone(''utc'', now()),$10,''esic_v1'')
     on conflict (employee_id, contribution_period_start) do update
     set contribution_period_end = excluded.contribution_period_end,
         benefit_period_start = excluded.benefit_period_start,
         benefit_period_end = excluded.benefit_period_end,
         total_days_worked = excluded.total_days_worked,
         total_wages_paid = excluded.total_wages_paid,
         minimum_days_required = excluded.minimum_days_required,
         is_eligible = excluded.is_eligible,
         eligibility_details = excluded.eligibility_details,
         last_calculated_at = excluded.last_calculated_at,
         calculated_by_actor_user_id = excluded.calculated_by_actor_user_id,
         calculation_version = excluded.calculation_version,
         updated_at = timezone(''utc'', now())
     returning benefit_period_id',
    p_schema_name
  ) into v_benefit_period_id using
    p_employee_id,
    v_contribution_start,
    v_contribution_end,
    v_benefit_start,
    v_benefit_end,
    coalesce(v_total_days, 0),
    coalesce(v_total_wages, 0),
    coalesce(v_total_days, 0) >= 78 and coalesce(v_total_wages, 0) > 0,
    jsonb_build_object('total_days_worked', coalesce(v_total_days, 0), 'total_wages_paid', coalesce(v_total_wages, 0), 'minimum_days_required', 78),
    p_actor_user_id;

  return public.platform_json_response(true,'OK','ESIC benefit period refreshed.',jsonb_build_object('benefit_period_id', v_benefit_period_id,'employee_id', p_employee_id));
end;
$function$;;
