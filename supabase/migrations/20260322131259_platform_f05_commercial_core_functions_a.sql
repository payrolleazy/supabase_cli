create or replace function public.platform_register_plan(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_plan_id uuid;
  v_plan_code text := lower(btrim(coalesce(p_params->>'plan_code', '')));
  v_plan_name text := btrim(coalesce(p_params->>'plan_name', ''));
  v_status text := coalesce(nullif(btrim(p_params->>'status'), ''), 'active');
  v_billing_cadence text := coalesce(nullif(btrim(p_params->>'billing_cadence'), ''), 'monthly');
  v_currency_code text := coalesce(nullif(btrim(p_params->>'currency_code'), ''), 'INR');
  v_description text := nullif(btrim(p_params->>'description'), '');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
begin
  if v_plan_code = '' then
    return public.platform_json_response(false, 'COMMERCIAL_PLAN_CODE_REQUIRED', 'plan_code is required.', '{}'::jsonb);
  end if;

  if v_plan_name = '' then
    return public.platform_json_response(false, 'COMMERCIAL_PLAN_NAME_REQUIRED', 'plan_name is required.', '{}'::jsonb);
  end if;

  insert into public.platform_plan_catalog (
    plan_code,
    plan_name,
    status,
    billing_cadence,
    currency_code,
    description,
    metadata
  )
  values (
    v_plan_code,
    v_plan_name,
    v_status,
    v_billing_cadence,
    v_currency_code,
    v_description,
    v_metadata
  )
  on conflict (plan_code) do update
  set
    plan_name = excluded.plan_name,
    status = excluded.status,
    billing_cadence = excluded.billing_cadence,
    currency_code = excluded.currency_code,
    description = excluded.description,
    metadata = excluded.metadata
  returning id into v_plan_id;

  return public.platform_json_response(
    true,
    'OK',
    'Plan registered.',
    jsonb_build_object(
      'plan_id', v_plan_id,
      'plan_code', v_plan_code
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_plan.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_plan_metric_rate(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_plan_id uuid := nullif(p_params->>'plan_id', '')::uuid;
  v_plan_code text := lower(btrim(coalesce(p_params->>'plan_code', '')));
  v_metric_code text := btrim(coalesce(p_params->>'metric_code', ''));
  v_unit_price numeric(18,2) := coalesce(nullif(p_params->>'unit_price', '')::numeric, null);
  v_currency_code text := coalesce(nullif(btrim(p_params->>'currency_code'), ''), 'INR');
  v_effective_from date := coalesce(nullif(p_params->>'effective_from', '')::date, current_date);
  v_effective_to date := nullif(p_params->>'effective_to', '')::date;
  v_billing_method text := coalesce(nullif(btrim(p_params->>'billing_method'), ''), 'per_unit');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_rate_id uuid;
begin
  if v_plan_id is null and v_plan_code = '' then
    return public.platform_json_response(false, 'COMMERCIAL_PLAN_REFERENCE_REQUIRED', 'plan_id or plan_code is required.', '{}'::jsonb);
  end if;

  if v_plan_id is null then
    select id into v_plan_id
    from public.platform_plan_catalog
    where plan_code = v_plan_code;
  end if;

  if v_plan_id is null then
    return public.platform_json_response(false, 'COMMERCIAL_PLAN_NOT_FOUND', 'Plan not found.', jsonb_build_object('plan_code', v_plan_code));
  end if;

  if v_metric_code = '' then
    return public.platform_json_response(false, 'COMMERCIAL_METRIC_CODE_REQUIRED', 'metric_code is required.', '{}'::jsonb);
  end if;

  if v_unit_price is null then
    return public.platform_json_response(false, 'COMMERCIAL_UNIT_PRICE_REQUIRED', 'unit_price is required.', '{}'::jsonb);
  end if;

  insert into public.platform_plan_metric_rate (
    plan_id,
    metric_code,
    billing_method,
    unit_price,
    currency_code,
    effective_from,
    effective_to,
    metadata
  )
  values (
    v_plan_id,
    v_metric_code,
    v_billing_method,
    v_unit_price,
    v_currency_code,
    v_effective_from,
    v_effective_to,
    v_metadata
  )
  on conflict (plan_id, metric_code, effective_from) do update
  set
    billing_method = excluded.billing_method,
    unit_price = excluded.unit_price,
    currency_code = excluded.currency_code,
    effective_to = excluded.effective_to,
    metadata = excluded.metadata
  returning id into v_rate_id;

  return public.platform_json_response(
    true,
    'OK',
    'Plan metric rate registered.',
    jsonb_build_object(
      'rate_id', v_rate_id,
      'plan_id', v_plan_id,
      'metric_code', v_metric_code
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_plan_metric_rate.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_upsert_tenant_subscription(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_plan_id uuid := nullif(p_params->>'plan_id', '')::uuid;
  v_plan_code text := lower(btrim(coalesce(p_params->>'plan_code', '')));
  v_subscription_status text := coalesce(nullif(btrim(p_params->>'subscription_status'), ''), 'active');
  v_currency_code text := coalesce(nullif(btrim(p_params->>'currency_code'), ''), 'INR');
  v_cycle_anchor_day integer := coalesce(nullif(p_params->>'cycle_anchor_day', '')::integer, 1);
  v_current_cycle_start date := nullif(p_params->>'current_cycle_start', '')::date;
  v_current_cycle_end date := nullif(p_params->>'current_cycle_end', '')::date;
  v_billing_owner_user_id uuid := nullif(p_params->>'billing_owner_user_id', '')::uuid;
  v_auto_renew boolean := coalesce((p_params->>'auto_renew')::boolean, true);
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_subscription_id uuid;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  if v_plan_id is null and v_plan_code = '' then
    return public.platform_json_response(false, 'COMMERCIAL_PLAN_REFERENCE_REQUIRED', 'plan_id or plan_code is required.', '{}'::jsonb);
  end if;

  if v_plan_id is null then
    select id into v_plan_id
    from public.platform_plan_catalog
    where plan_code = v_plan_code;
  end if;

  if v_plan_id is null then
    return public.platform_json_response(false, 'COMMERCIAL_PLAN_NOT_FOUND', 'Plan not found.', jsonb_build_object('plan_code', v_plan_code));
  end if;

  insert into public.platform_tenant_commercial_account (
    tenant_id,
    commercial_status,
    dues_state
  )
  values (
    v_tenant_id,
    'clear',
    'clear'
  )
  on conflict (tenant_id) do nothing;

  if v_current_cycle_start is null then
    v_current_cycle_start := date_trunc('month', current_date)::date;
  end if;

  if v_current_cycle_end is null then
    v_current_cycle_end := (date_trunc('month', v_current_cycle_start::timestamp) + interval '1 month - 1 day')::date;
  end if;

  insert into public.platform_tenant_subscription (
    tenant_id,
    plan_id,
    subscription_status,
    billing_owner_user_id,
    currency_code,
    cycle_anchor_day,
    current_cycle_start,
    current_cycle_end,
    auto_renew,
    metadata
  )
  values (
    v_tenant_id,
    v_plan_id,
    v_subscription_status,
    v_billing_owner_user_id,
    v_currency_code,
    v_cycle_anchor_day,
    v_current_cycle_start,
    v_current_cycle_end,
    v_auto_renew,
    v_metadata
  )
  on conflict (tenant_id) do update
  set
    plan_id = excluded.plan_id,
    subscription_status = excluded.subscription_status,
    billing_owner_user_id = excluded.billing_owner_user_id,
    currency_code = excluded.currency_code,
    cycle_anchor_day = excluded.cycle_anchor_day,
    current_cycle_start = excluded.current_cycle_start,
    current_cycle_end = excluded.current_cycle_end,
    auto_renew = excluded.auto_renew,
    metadata = excluded.metadata
  returning id into v_subscription_id;

  return public.platform_json_response(
    true,
    'OK',
    'Tenant subscription upserted.',
    jsonb_build_object(
      'subscription_id', v_subscription_id,
      'tenant_id', v_tenant_id,
      'plan_id', v_plan_id
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_upsert_tenant_subscription.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_sync_tenant_access_from_commercial(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_overdue_since date;
  v_background_stop_from timestamptz;
  v_new_access_state text;
  v_access_row public.platform_tenant_access_state%rowtype;
  v_actor uuid := auth.uid();
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  update public.platform_invoice
  set invoice_status = 'overdue'
  where tenant_id = v_tenant_id
    and balance_amount > 0
    and due_date < current_date
    and invoice_status in ('issued', 'partially_paid');

  select min(due_date)
  into v_overdue_since
  from public.platform_invoice
  where tenant_id = v_tenant_id
    and balance_amount > 0
    and due_date < current_date
    and invoice_status in ('overdue', 'issued', 'partially_paid');

  select *
  into v_access_row
  from public.platform_tenant_access_state
  where tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant access state not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_access_row.access_state in ('disabled', 'terminated') then
    return public.platform_json_response(true, 'OK', 'Commercial sync skipped because tenant access state is terminal.', jsonb_build_object('tenant_id', v_tenant_id, 'access_state', v_access_row.access_state));
  end if;

  if v_overdue_since is null then
    update public.platform_tenant_commercial_account
    set
      commercial_status = 'clear',
      dues_state = 'clear',
      overdue_since = null,
      dormant_access_from = null,
      background_stop_from = null,
      last_state_synced_at = timezone('utc', now())
    where tenant_id = v_tenant_id;

    if v_access_row.access_state in ('dormant_access_blocked', 'dormant_background_blocked') then
      update public.platform_tenant_access_state
      set
        access_state = 'active',
        billing_state = 'clear',
        reason_code = null,
        background_stop_at = null,
        updated_by = v_actor
      where tenant_id = v_tenant_id;

      perform public.platform_append_status_history(v_tenant_id, 'access', v_access_row.access_state, 'active', 'COMMERCIAL_DUES_CLEARED', '{}'::jsonb, v_actor, 'platform_sync_tenant_access_from_commercial');
      if v_access_row.billing_state is distinct from 'clear' then
        perform public.platform_append_status_history(v_tenant_id, 'billing', v_access_row.billing_state, 'clear', 'COMMERCIAL_DUES_CLEARED', '{}'::jsonb, v_actor, 'platform_sync_tenant_access_from_commercial');
      end if;
    end if;

    return public.platform_json_response(true, 'OK', 'Commercial state synced and tenant is clear.', jsonb_build_object('tenant_id', v_tenant_id, 'access_state', 'active'));
  end if;

  v_background_stop_from := timezone('utc', v_overdue_since::timestamp) + interval '60 days';
  v_new_access_state := case
    when timezone('utc', now()) >= v_background_stop_from then 'dormant_background_blocked'
    else 'dormant_access_blocked'
  end;

  update public.platform_tenant_commercial_account
  set
    commercial_status = v_new_access_state,
    dues_state = 'overdue',
    overdue_since = v_overdue_since,
    dormant_access_from = coalesce(dormant_access_from, timezone('utc', now())),
    background_stop_from = v_background_stop_from,
    last_state_synced_at = timezone('utc', now())
  where tenant_id = v_tenant_id;

  update public.platform_tenant_access_state
  set
    access_state = v_new_access_state,
    billing_state = 'delinquent',
    reason_code = 'COMMERCIAL_DUES_OVERDUE',
    background_stop_at = v_background_stop_from,
    updated_by = v_actor
  where tenant_id = v_tenant_id;

  if v_access_row.access_state is distinct from v_new_access_state then
    perform public.platform_append_status_history(v_tenant_id, 'access', v_access_row.access_state, v_new_access_state, 'COMMERCIAL_DUES_OVERDUE', jsonb_build_object('overdue_since', v_overdue_since, 'background_stop_from', v_background_stop_from), v_actor, 'platform_sync_tenant_access_from_commercial');
  end if;

  if v_access_row.billing_state is distinct from 'delinquent' then
    perform public.platform_append_status_history(v_tenant_id, 'billing', v_access_row.billing_state, 'delinquent', 'COMMERCIAL_DUES_OVERDUE', jsonb_build_object('overdue_since', v_overdue_since, 'background_stop_from', v_background_stop_from), v_actor, 'platform_sync_tenant_access_from_commercial');
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'Commercial state synced and tenant access updated.',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'overdue_since', v_overdue_since,
      'access_state', v_new_access_state,
      'background_stop_from', v_background_stop_from
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_sync_tenant_access_from_commercial.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_billable_unit(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_metric_code text := btrim(coalesce(p_params->>'metric_code', ''));
  v_quantity numeric(18,4) := coalesce(nullif(p_params->>'quantity', '')::numeric, 1);
  v_source_type text := btrim(coalesce(p_params->>'source_type', ''));
  v_source_id text := btrim(coalesce(p_params->>'source_id', ''));
  v_occurred_on date := coalesce(nullif(p_params->>'occurred_on', '')::date, current_date);
  v_idempotency_key text := btrim(coalesce(p_params->>'idempotency_key', ''));
  v_source_reference jsonb := coalesce(p_params->'source_reference', '{}'::jsonb);
  v_created_by uuid := coalesce(nullif(p_params->>'created_by', '')::uuid, auth.uid());
  v_gate jsonb;
  v_subscription public.platform_tenant_subscription%rowtype;
  v_rate public.platform_plan_metric_rate%rowtype;
  v_ledger public.platform_billable_unit_ledger%rowtype;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  if v_metric_code = '' then
    return public.platform_json_response(false, 'COMMERCIAL_METRIC_CODE_REQUIRED', 'metric_code is required.', '{}'::jsonb);
  end if;

  if v_source_type = '' or v_source_id = '' then
    return public.platform_json_response(false, 'COMMERCIAL_SOURCE_REFERENCE_REQUIRED', 'source_type and source_id are required.', '{}'::jsonb);
  end if;

  if v_idempotency_key = '' then
    return public.platform_json_response(false, 'COMMERCIAL_IDEMPOTENCY_KEY_REQUIRED', 'idempotency_key is required.', '{}'::jsonb);
  end if;

  v_gate := public.platform_get_tenant_access_gate(jsonb_build_object('tenant_id', v_tenant_id));

  if not coalesce((v_gate->>'success')::boolean, false) then
    return v_gate;
  end if;

  if not coalesce((v_gate->'details'->>'background_processing_allowed')::boolean, false) then
    return public.platform_json_response(false, 'COMMERCIAL_BACKGROUND_BLOCKED', 'Background processing is blocked for this tenant.', jsonb_build_object('tenant_id', v_tenant_id, 'gate_reason_code', v_gate->'details'->>'reason_code'));
  end if;

  select *
  into v_subscription
  from public.platform_tenant_subscription pts
  where pts.tenant_id = v_tenant_id
    and pts.subscription_status = 'active'
  limit 1;

  if not found then
    return public.platform_json_response(false, 'COMMERCIAL_SUBSCRIPTION_NOT_FOUND', 'Active subscription not found for tenant.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  v_rate := public.platform_get_effective_plan_rate(v_subscription.plan_id, v_metric_code, v_occurred_on);

  if v_rate.id is null then
    return public.platform_json_response(false, 'COMMERCIAL_RATE_NOT_FOUND', 'No active rate found for metric.', jsonb_build_object('tenant_id', v_tenant_id, 'metric_code', v_metric_code, 'occurred_on', v_occurred_on));
  end if;

  insert into public.platform_billable_unit_ledger (
    tenant_id,
    metric_code,
    quantity,
    unit_price,
    line_amount,
    currency_code,
    source_type,
    source_id,
    source_reference,
    occurred_on,
    idempotency_key,
    created_by
  )
  values (
    v_tenant_id,
    v_metric_code,
    v_quantity,
    v_rate.unit_price,
    round((v_quantity * v_rate.unit_price)::numeric, 2),
    v_rate.currency_code,
    v_source_type,
    v_source_id,
    v_source_reference,
    v_occurred_on,
    v_idempotency_key,
    v_created_by
  )
  on conflict (tenant_id, idempotency_key) do update
  set source_reference = public.platform_billable_unit_ledger.source_reference
  returning * into v_ledger;

  return public.platform_json_response(
    true,
    'OK',
    'Billable unit registered.',
    jsonb_build_object(
      'ledger_id', v_ledger.id,
      'tenant_id', v_ledger.tenant_id,
      'metric_code', v_ledger.metric_code,
      'line_amount', v_ledger.line_amount
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_register_billable_unit.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_open_billing_cycle(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_cycle_start date := nullif(p_params->>'cycle_start', '')::date;
  v_cycle_end date := nullif(p_params->>'cycle_end', '')::date;
  v_due_date date := nullif(p_params->>'invoice_due_date', '')::date;
  v_subscription public.platform_tenant_subscription%rowtype;
  v_cycle public.platform_billing_cycle%rowtype;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  if v_cycle_start is null or v_cycle_end is null then
    return public.platform_json_response(false, 'COMMERCIAL_CYCLE_WINDOW_REQUIRED', 'cycle_start and cycle_end are required.', '{}'::jsonb);
  end if;

  select *
  into v_subscription
  from public.platform_tenant_subscription pts
  where pts.tenant_id = v_tenant_id
    and pts.subscription_status = 'active'
  limit 1;

  if not found then
    return public.platform_json_response(false, 'COMMERCIAL_SUBSCRIPTION_NOT_FOUND', 'Active subscription not found for tenant.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_due_date is null then
    v_due_date := v_cycle_end + 7;
  end if;

  insert into public.platform_billing_cycle (
    tenant_id,
    subscription_id,
    cycle_start,
    cycle_end,
    invoice_due_date,
    currency_code
  )
  values (
    v_tenant_id,
    v_subscription.id,
    v_cycle_start,
    v_cycle_end,
    v_due_date,
    v_subscription.currency_code
  )
  on conflict (tenant_id, cycle_start, cycle_end) do update
  set invoice_due_date = excluded.invoice_due_date
  returning * into v_cycle;

  return public.platform_json_response(
    true,
    'OK',
    'Billing cycle opened.',
    jsonb_build_object(
      'billing_cycle_id', v_cycle.id,
      'tenant_id', v_cycle.tenant_id,
      'cycle_start', v_cycle.cycle_start,
      'cycle_end', v_cycle.cycle_end
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_open_billing_cycle.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_get_tenant_commercial_state(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_row public.platform_tenant_commercial_state_view%rowtype;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select *
  into v_row
  from public.platform_tenant_commercial_state_view
  where tenant_id = v_tenant_id;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'Tenant commercial state resolved.',
    to_jsonb(v_row)
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_get_tenant_commercial_state.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
