CREATE OR REPLACE FUNCTION public.platform_apply_payment_credit(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_amount numeric(18,2) := coalesce(nullif(p_params->>'amount', '')::numeric, null);
  v_direction text := lower(coalesce(nullif(btrim(p_params->>'direction'), ''), 'credit'));
  v_entry_type text := coalesce(nullif(btrim(p_params->>'entry_type'), ''), case when v_direction = 'debit' then 'settlement_debit' else 'payment_credit' end);
  v_reference_type text := coalesce(nullif(btrim(p_params->>'reference_type'), ''), 'payment_order');
  v_reference_id text := coalesce(nullif(btrim(p_params->>'reference_id'), ''), '');
  v_currency_code text := coalesce(nullif(btrim(p_params->>'currency_code'), ''), 'INR');
  v_notes text := nullif(btrim(p_params->>'notes'), '');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_created_by uuid := coalesce(nullif(p_params->>'created_by', '')::uuid, auth.uid());
  v_wallet public.platform_wallet_balance%rowtype;
  v_existing_ledger public.platform_wallet_ledger%rowtype;
  v_new_balance numeric(18,2);
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  if v_amount is null or v_amount <= 0 then
    return public.platform_json_response(false, 'COMMERCIAL_PAYMENT_AMOUNT_REQUIRED', 'amount must be greater than zero.', '{}'::jsonb);
  end if;

  if v_reference_id = '' then
    return public.platform_json_response(false, 'COMMERCIAL_REFERENCE_REQUIRED', 'reference_id is required.', '{}'::jsonb);
  end if;

  if v_direction not in ('credit', 'debit') then
    return public.platform_json_response(false, 'COMMERCIAL_INVALID_DIRECTION', 'direction must be credit or debit.', jsonb_build_object('direction', v_direction));
  end if;

  select * into v_existing_ledger
  from public.platform_wallet_ledger
  where tenant_id = v_tenant_id
    and reference_type = v_reference_type
    and reference_id = v_reference_id
    and entry_type = v_entry_type;

  if found then
    select * into v_wallet
    from public.platform_wallet_balance
    where tenant_id = v_tenant_id;

    return public.platform_json_response(
      true,
      'OK',
      'Wallet credit already applied.',
      jsonb_build_object(
        'wallet_balance', to_jsonb(v_wallet),
        'wallet_ledger', to_jsonb(v_existing_ledger),
        'idempotent_replay', true
      )
    );
  end if;

  insert into public.platform_wallet_balance (tenant_id, currency_code)
  values (v_tenant_id, v_currency_code)
  on conflict (tenant_id) do nothing;

  select * into v_wallet
  from public.platform_wallet_balance
  where tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'COMMERCIAL_WALLET_NOT_FOUND', 'Wallet balance row could not be resolved.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_direction = 'debit' and v_wallet.available_credit < v_amount then
    return public.platform_json_response(false, 'COMMERCIAL_WALLET_INSUFFICIENT_CREDIT', 'Wallet credit is insufficient for debit.', jsonb_build_object('available_credit', v_wallet.available_credit, 'requested_amount', v_amount));
  end if;

  v_new_balance := case when v_direction = 'debit' then v_wallet.available_credit - v_amount else v_wallet.available_credit + v_amount end;

  insert into public.platform_wallet_ledger (
    tenant_id,
    entry_type,
    direction,
    amount,
    currency_code,
    reference_type,
    reference_id,
    balance_after,
    notes,
    metadata,
    created_by
  )
  values (
    v_tenant_id,
    v_entry_type,
    v_direction,
    v_amount,
    coalesce(v_wallet.currency_code, v_currency_code),
    v_reference_type,
    v_reference_id,
    v_new_balance,
    v_notes,
    v_metadata,
    v_created_by
  )
  returning * into v_existing_ledger;

  update public.platform_wallet_balance
  set available_credit = v_new_balance,
      updated_at = timezone('utc', now()),
      last_settlement_at = case when v_entry_type = 'settlement_debit' then timezone('utc', now()) else last_settlement_at end
  where tenant_id = v_tenant_id
  returning * into v_wallet;

  return public.platform_json_response(
    true,
    'OK',
    'Wallet balance updated.',
    jsonb_build_object(
      'wallet_balance', to_jsonb(v_wallet),
      'wallet_ledger', to_jsonb(v_existing_ledger),
      'idempotent_replay', false
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_apply_payment_credit.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_apply_payment_receipt(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_invoice_id uuid := nullif(p_params->>'invoice_id', '')::uuid;
  v_invoice_no text := nullif(btrim(p_params->>'invoice_no'), '');
  v_provider_code text := btrim(coalesce(p_params->>'provider_code', ''));
  v_external_payment_id text := btrim(coalesce(p_params->>'external_payment_id', ''));
  v_amount numeric(18,2) := coalesce(nullif(p_params->>'amount', '')::numeric, null);
  v_currency_code text := coalesce(nullif(btrim(p_params->>'currency_code'), ''), 'INR');
  v_paid_at timestamptz := coalesce(nullif(p_params->>'paid_at', '')::timestamptz, timezone('utc', now()));
  v_details jsonb := coalesce(p_params->'details', '{}'::jsonb);
  v_invoice public.platform_invoice%rowtype;
  v_cycle public.platform_billing_cycle%rowtype;
  v_receipt public.platform_payment_receipt%rowtype;
  v_existing_receipt public.platform_payment_receipt%rowtype;
  v_new_paid numeric(18,2);
  v_new_balance numeric(18,2);
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  if v_provider_code = '' or v_external_payment_id = '' then
    return public.platform_json_response(false, 'COMMERCIAL_PAYMENT_REFERENCE_REQUIRED', 'provider_code and external_payment_id are required.', '{}'::jsonb);
  end if;

  if v_amount is null then
    return public.platform_json_response(false, 'COMMERCIAL_PAYMENT_AMOUNT_REQUIRED', 'amount is required.', '{}'::jsonb);
  end if;

  if v_invoice_id is null and v_invoice_no is null then
    return public.platform_json_response(false, 'COMMERCIAL_INVOICE_REFERENCE_REQUIRED', 'invoice_id or invoice_no is required.', '{}'::jsonb);
  end if;

  if v_invoice_id is not null then
    select * into v_invoice
    from public.platform_invoice
    where id = v_invoice_id
      and tenant_id = v_tenant_id
    for update;
  else
    select * into v_invoice
    from public.platform_invoice
    where invoice_no = v_invoice_no
      and tenant_id = v_tenant_id
    for update;
  end if;

  if not found then
    return public.platform_json_response(false, 'COMMERCIAL_INVOICE_NOT_FOUND', 'Invoice not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  insert into public.platform_payment_receipt (
    tenant_id,
    invoice_id,
    provider_code,
    external_payment_id,
    amount,
    currency_code,
    receipt_status,
    paid_at,
    details
  )
  values (
    v_tenant_id,
    v_invoice.id,
    v_provider_code,
    v_external_payment_id,
    v_amount,
    v_currency_code,
    'received',
    v_paid_at,
    v_details
  )
  on conflict (provider_code, external_payment_id) do nothing
  returning * into v_receipt;

  if v_receipt.id is null then
    select * into v_existing_receipt
    from public.platform_payment_receipt
    where provider_code = v_provider_code
      and external_payment_id = v_external_payment_id;

    return public.platform_json_response(
      true,
      'OK',
      'Payment receipt already applied.',
      jsonb_build_object(
        'payment_receipt_id', v_existing_receipt.id,
        'invoice_id', v_invoice.id,
        'invoice_status', v_invoice.invoice_status,
        'invoice_balance_amount', v_invoice.balance_amount,
        'idempotent_replay', true
      )
    );
  end if;

  v_new_paid := round((v_invoice.paid_amount + v_amount)::numeric, 2);
  v_new_balance := greatest(round((v_invoice.total_amount - least(v_new_paid, v_invoice.total_amount))::numeric, 2), 0);

  update public.platform_invoice
  set
    paid_amount = least(v_new_paid, total_amount),
    balance_amount = v_new_balance,
    invoice_status = case
      when v_new_balance = 0 then 'paid'
      when v_new_paid > 0 then 'partially_paid'
      else invoice_status
    end
  where id = v_invoice.id
  returning * into v_invoice;

  select * into v_cycle
  from public.platform_billing_cycle
  where id = v_invoice.billing_cycle_id
  for update;

  if found then
    update public.platform_billing_cycle
    set
      paid_amount = v_invoice.paid_amount,
      balance_amount = v_invoice.balance_amount,
      cycle_status = case
        when v_invoice.balance_amount = 0 then 'paid'
        when v_invoice.paid_amount > 0 then 'partially_paid'
        else cycle_status
      end
    where id = v_cycle.id
    returning * into v_cycle;
  end if;

  update public.platform_payment_receipt
  set receipt_status = 'applied'
  where id = v_receipt.id
  returning * into v_receipt;

  update public.platform_tenant_commercial_account
  set
    last_paid_at = timezone('utc', now()),
    last_state_synced_at = timezone('utc', now())
  where tenant_id = v_tenant_id;

  perform public.platform_sync_tenant_access_from_commercial(jsonb_build_object('tenant_id', v_tenant_id));

  return public.platform_json_response(
    true,
    'OK',
    'Payment receipt applied.',
    jsonb_build_object(
      'payment_receipt_id', v_receipt.id,
      'invoice_id', v_invoice.id,
      'invoice_status', v_invoice.invoice_status,
      'invoice_balance_amount', v_invoice.balance_amount,
      'idempotent_replay', false
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_apply_payment_receipt.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_attach_payment_order(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_payment_order_id uuid := nullif(p_params->>'payment_order_id', '')::uuid;
  v_external_order_id text := nullif(btrim(p_params->>'external_order_id'), '');
  v_status text := coalesce(nullif(btrim(p_params->>'status'), ''), 'pending');
  v_provider_payload jsonb := coalesce(p_params->'provider_payload', '{}'::jsonb);
  v_payment_order public.platform_payment_order%rowtype;
begin
  if v_payment_order_id is null then
    return public.platform_json_response(false, 'COMMERCIAL_PAYMENT_ORDER_REQUIRED', 'payment_order_id is required.', '{}'::jsonb);
  end if;

  update public.platform_payment_order
  set external_order_id = coalesce(v_external_order_id, external_order_id),
      status = v_status,
      checkout_payload = checkout_payload || jsonb_strip_nulls(jsonb_build_object('provider_payload', v_provider_payload, 'checkout_url', p_params->>'checkout_url', 'expires_at', p_params->>'expires_at')),
      updated_at = timezone('utc', now())
  where id = v_payment_order_id
  returning * into v_payment_order;

  if not found then
    return public.platform_json_response(false, 'COMMERCIAL_PAYMENT_ORDER_NOT_FOUND', 'Payment order not found.', jsonb_build_object('payment_order_id', v_payment_order_id));
  end if;

  return public.platform_json_response(true, 'OK', 'Payment order attached.', to_jsonb(v_payment_order));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_attach_payment_order.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_close_billing_cycle(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_cycle_id uuid := nullif(p_params->>'billing_cycle_id', '')::uuid;
  v_cycle public.platform_billing_cycle%rowtype;
  v_invoice public.platform_invoice%rowtype;
  v_settlement public.platform_billing_settlement%rowtype;
  v_subtotal numeric(18,2);
  v_invoice_no text;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  if v_cycle_id is null then
    select id into v_cycle_id
    from public.platform_billing_cycle
    where tenant_id = v_tenant_id
      and cycle_status = 'open'
    order by cycle_start
    limit 1;
  end if;

  if v_cycle_id is null then
    return public.platform_json_response(false, 'COMMERCIAL_BILLING_CYCLE_NOT_FOUND', 'Open billing cycle not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  select * into v_cycle
  from public.platform_billing_cycle
  where id = v_cycle_id
    and tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'COMMERCIAL_BILLING_CYCLE_NOT_FOUND', 'Billing cycle not found.', jsonb_build_object('billing_cycle_id', v_cycle_id));
  end if;

  if v_cycle.cycle_status <> 'open' then
    select * into v_invoice
    from public.platform_invoice
    where billing_cycle_id = v_cycle.id
    order by created_at desc
    limit 1;

    return public.platform_json_response(true, 'OK', 'Billing cycle already closed.', jsonb_build_object('billing_cycle_id', v_cycle.id, 'invoice', to_jsonb(v_invoice), 'idempotent_replay', true));
  end if;

  select * into v_settlement
  from public.platform_billing_settlement
  where billing_cycle_id = v_cycle.id
  order by created_at desc
  limit 1;

  select coalesce(round(sum(line_amount)::numeric, 2), 0)
  into v_subtotal
  from public.platform_billable_unit_ledger
  where tenant_id = v_tenant_id
    and occurred_on between v_cycle.cycle_start and v_cycle.cycle_end
    and billing_cycle_id = v_cycle.id
    and entry_status = 'recorded';

  v_invoice_no := public.platform_build_invoice_no(v_cycle.cycle_end);

  insert into public.platform_invoice (
    tenant_id,
    billing_cycle_id,
    settlement_id,
    invoice_no,
    invoice_status,
    issue_date,
    due_date,
    currency_code,
    subtotal_amount,
    total_amount,
    paid_amount,
    balance_amount,
    invoice_payload
  )
  values (
    v_tenant_id,
    v_cycle.id,
    v_settlement.id,
    v_invoice_no,
    case when v_subtotal = 0 then 'paid' else 'issued' end,
    current_date,
    v_cycle.invoice_due_date,
    v_cycle.currency_code,
    v_subtotal,
    v_subtotal,
    case when v_subtotal = 0 then v_subtotal else 0 end,
    case when v_subtotal = 0 then 0 else v_subtotal end,
    jsonb_build_object(
      'billing_cycle_id', v_cycle.id,
      'cycle_start', v_cycle.cycle_start,
      'cycle_end', v_cycle.cycle_end,
      'settlement_id', v_settlement.id
    )
  )
  returning * into v_invoice;

  update public.platform_billing_cycle
  set cycle_status = case when v_subtotal = 0 then 'paid' else 'invoiced' end,
      subtotal_amount = v_subtotal,
      total_amount = v_subtotal,
      paid_amount = case when v_subtotal = 0 then v_subtotal else 0 end,
      balance_amount = case when v_subtotal = 0 then 0 else v_subtotal end,
      closed_at = timezone('utc', now())
  where id = v_cycle.id
  returning * into v_cycle;

  update public.platform_billable_unit_ledger
  set invoice_id = v_invoice.id,
      entry_status = 'invoiced'
  where billing_cycle_id = v_cycle.id
    and tenant_id = v_tenant_id
    and entry_status = 'recorded';

  if v_settlement.id is not null and v_subtotal = 0 then
    update public.platform_billing_settlement
    set settlement_status = 'settled',
        settled_at = coalesce(settled_at, timezone('utc', now()))
    where id = v_settlement.id
    returning * into v_settlement;
  end if;

  update public.platform_tenant_commercial_account
  set last_invoiced_at = timezone('utc', now()),
      last_state_synced_at = timezone('utc', now())
  where tenant_id = v_tenant_id;

  perform public.platform_sync_tenant_access_from_commercial(jsonb_build_object('tenant_id', v_tenant_id));

  return public.platform_json_response(
    true,
    'OK',
    'Billing cycle closed and invoice created.',
    jsonb_build_object(
      'billing_cycle_id', v_cycle.id,
      'invoice_id', v_invoice.id,
      'invoice_no', v_invoice.invoice_no,
      'total_amount', v_invoice.total_amount,
      'settlement_id', v_settlement.id,
      'idempotent_replay', false
    )
  );
exception
  when unique_violation then
    select * into v_invoice from public.platform_invoice where billing_cycle_id = v_cycle_id order by created_at desc limit 1;
    return public.platform_json_response(true, 'OK', 'Invoice already exists for this billing cycle.', jsonb_build_object('billing_cycle_id', v_cycle_id, 'invoice', to_jsonb(v_invoice), 'idempotent_replay', true));
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_close_billing_cycle.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_count_billable_users(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_as_of_date date := coalesce(nullif(p_params->>'as_of_date', '')::date, current_date);
  v_subscription public.platform_tenant_subscription%rowtype;
  v_plan public.platform_plan_catalog%rowtype;
  v_active_employee_count integer := 0;
  v_free_allowance integer := 0;
  v_chargeable_user_count integer := 0;
  v_snapshot_hash text;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select * into v_subscription
  from public.platform_tenant_subscription
  where tenant_id = v_tenant_id;

  if not found then
    return public.platform_json_response(false, 'COMMERCIAL_SUBSCRIPTION_NOT_FOUND', 'Subscription not found for tenant.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  select * into v_plan
  from public.platform_plan_catalog
  where id = v_subscription.plan_id;

  if not found then
    return public.platform_json_response(false, 'COMMERCIAL_PLAN_NOT_FOUND', 'Plan not found for tenant subscription.', jsonb_build_object('tenant_id', v_tenant_id, 'plan_id', v_subscription.plan_id));
  end if;

  select count(*)::integer into v_active_employee_count
  from public.platform_rm_wcm_employee_catalog ec
  where ec.tenant_id = v_tenant_id
    and ec.current_billable is true
    and (ec.joining_date is null or ec.joining_date <= v_as_of_date)
    and (ec.relief_date is null or ec.relief_date > v_as_of_date);

  v_free_allowance := greatest(coalesce(v_plan.included_employee_count, 0), 0);
  v_chargeable_user_count := greatest(v_active_employee_count - v_free_allowance, 0);
  v_snapshot_hash := md5(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'as_of_date', v_as_of_date,
    'active_employee_count', v_active_employee_count,
    'free_allowance', v_free_allowance,
    'chargeable_user_count', v_chargeable_user_count
  )::text);

  return public.platform_json_response(
    true,
    'OK',
    'Billable users counted.',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'as_of_date', v_as_of_date,
      'active_employee_count', v_active_employee_count,
      'billable_user_count', v_active_employee_count,
      'free_allowance', v_free_allowance,
      'chargeable_user_count', v_chargeable_user_count,
      'count_snapshot_hash', v_snapshot_hash,
      'plan_id', v_plan.id,
      'plan_code', v_plan.plan_code
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_count_billable_users.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_create_or_update_subscription(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  return public.platform_upsert_tenant_subscription(p_params);
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_create_settlement(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_period_start date;
  v_period_end date;
  v_meter_date date;
  v_due_date date;
  v_count_result jsonb;
  v_count_details jsonb;
  v_billable_user_count integer;
  v_free_allowance integer;
  v_chargeable_user_count integer;
  v_snapshot_hash text;
  v_subscription public.platform_tenant_subscription%rowtype;
  v_plan public.platform_plan_catalog%rowtype;
  v_wallet public.platform_wallet_balance%rowtype;
  v_existing_settlement public.platform_billing_settlement%rowtype;
  v_settlement public.platform_billing_settlement%rowtype;
  v_cycle public.platform_billing_cycle%rowtype;
  v_usage_snapshot_id bigint;
  v_metric_unit_rate numeric(18,4);
  v_base_amount numeric(18,2);
  v_gross_amount numeric(18,2);
  v_credit_applied numeric(18,2);
  v_final_amount numeric(18,2);
  v_credit_result jsonb;
  v_ledger_id bigint;
  v_ledger_key text;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select * into v_subscription
  from public.platform_tenant_subscription
  where tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'COMMERCIAL_SUBSCRIPTION_NOT_FOUND', 'Active subscription not found for tenant.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  select * into v_plan
  from public.platform_plan_catalog
  where id = v_subscription.plan_id;

  if not found then
    return public.platform_json_response(false, 'COMMERCIAL_PLAN_NOT_FOUND', 'Plan not found for tenant subscription.', jsonb_build_object('plan_id', v_subscription.plan_id));
  end if;

  v_period_start := coalesce(nullif(p_params->>'period_start', '')::date, v_subscription.current_cycle_start);
  v_period_end := coalesce(nullif(p_params->>'period_end', '')::date, v_subscription.current_cycle_end);
  v_meter_date := coalesce(nullif(p_params->>'meter_date', '')::date, v_period_end, current_date);
  v_due_date := coalesce(nullif(p_params->>'invoice_due_date', '')::date, v_period_end + 7);

  if v_period_start is null or v_period_end is null then
    return public.platform_json_response(false, 'COMMERCIAL_CYCLE_WINDOW_REQUIRED', 'period_start and period_end are required.', '{}'::jsonb);
  end if;

  if v_period_end < v_period_start then
    return public.platform_json_response(false, 'COMMERCIAL_INVALID_CYCLE_WINDOW', 'period_end must be on or after period_start.', jsonb_build_object('period_start', v_period_start, 'period_end', v_period_end));
  end if;

  select * into v_existing_settlement
  from public.platform_billing_settlement
  where tenant_id = v_tenant_id
    and period_start = v_period_start
    and period_end = v_period_end
  for update;

  if found then
    return public.platform_json_response(true, 'OK', 'Settlement already exists.', jsonb_build_object('settlement', to_jsonb(v_existing_settlement), 'reused_existing', true));
  end if;

  select * into v_cycle
  from public.platform_billing_cycle
  where tenant_id = v_tenant_id
    and cycle_start = v_period_start
    and cycle_end = v_period_end
  for update;

  if not found then
    perform public.platform_open_billing_cycle(jsonb_build_object(
      'tenant_id', v_tenant_id,
      'cycle_start', v_period_start,
      'cycle_end', v_period_end,
      'invoice_due_date', v_due_date
    ));

    select * into v_cycle
    from public.platform_billing_cycle
    where tenant_id = v_tenant_id
      and cycle_start = v_period_start
      and cycle_end = v_period_end
    for update;
  end if;

  v_count_result := public.platform_count_billable_users(jsonb_build_object('tenant_id', v_tenant_id, 'as_of_date', v_meter_date));
  if coalesce((v_count_result->>'success')::boolean, false) is not true then
    return v_count_result;
  end if;

  v_count_details := coalesce(v_count_result->'details', '{}'::jsonb);
  v_billable_user_count := coalesce((v_count_details->>'billable_user_count')::integer, 0);
  v_free_allowance := coalesce((v_count_details->>'free_allowance')::integer, 0);
  v_chargeable_user_count := coalesce((v_count_details->>'chargeable_user_count')::integer, 0);
  v_snapshot_hash := v_count_details->>'count_snapshot_hash';

  insert into public.platform_employee_usage_snapshot (
    tenant_id,
    snapshot_date,
    count_basis_date,
    active_employee_count,
    free_employee_count,
    billable_employee_count,
    meter_method,
    snapshot_payload,
    snapshot_hash
  ) values (
    v_tenant_id,
    v_meter_date,
    v_meter_date,
    v_billable_user_count,
    v_free_allowance,
    v_chargeable_user_count,
    'platform_rm_wcm_employee_catalog.current_billable',
    jsonb_build_object('source', 'platform_count_billable_users', 'count_result', v_count_details),
    v_snapshot_hash
  )
  on conflict (tenant_id, snapshot_date) do update
  set count_basis_date = excluded.count_basis_date,
      active_employee_count = excluded.active_employee_count,
      free_employee_count = excluded.free_employee_count,
      billable_employee_count = excluded.billable_employee_count,
      meter_method = excluded.meter_method,
      snapshot_payload = excluded.snapshot_payload,
      snapshot_hash = excluded.snapshot_hash
  returning id into v_usage_snapshot_id;

  v_metric_unit_rate := coalesce(
    nullif(v_plan.pricing_rules->>'overage_per_employee_amount', '')::numeric,
    (
      select pmr.unit_price
      from public.platform_plan_metric_rate pmr
      where pmr.plan_id = v_plan.id
        and pmr.metric_code = 'employee_monthly_active'
      order by pmr.effective_from desc, pmr.created_at desc
      limit 1
    ),
    0
  );
  v_base_amount := coalesce(nullif(v_plan.pricing_rules->>'base_amount', '')::numeric, 0);
  v_gross_amount := round((v_base_amount + (coalesce(v_chargeable_user_count, 0)::numeric * coalesce(v_metric_unit_rate, 0)))::numeric, 2);

  insert into public.platform_wallet_balance (tenant_id, currency_code)
  values (v_tenant_id, coalesce(v_subscription.currency_code, v_plan.currency_code, 'INR'))
  on conflict (tenant_id) do nothing;

  select * into v_wallet
  from public.platform_wallet_balance
  where tenant_id = v_tenant_id
  for update;

  v_credit_applied := least(coalesce(v_wallet.available_credit, 0), v_gross_amount);
  v_final_amount := round((v_gross_amount - v_credit_applied)::numeric, 2);

  insert into public.platform_billing_settlement (
    tenant_id,
    billing_cycle_id,
    period_start,
    period_end,
    measured_peak_users,
    measured_average_users,
    chargeable_users,
    unit_rate,
    gross_amount,
    credit_applied,
    tax_payload,
    final_amount,
    settlement_status,
    usage_snapshot_ids,
    settled_at
  ) values (
    v_tenant_id,
    v_cycle.id,
    v_period_start,
    v_period_end,
    v_billable_user_count,
    v_billable_user_count::numeric,
    v_chargeable_user_count,
    v_metric_unit_rate,
    v_gross_amount,
    v_credit_applied,
    '{}'::jsonb,
    v_final_amount,
    case when v_final_amount > 0 then 'pending_payment' else 'settled' end,
    jsonb_build_array(v_usage_snapshot_id),
    case when v_final_amount > 0 then null else timezone('utc', now()) end
  )
  returning * into v_settlement;

  if v_credit_applied > 0 then
    v_credit_result := public.platform_apply_payment_credit(jsonb_build_object(
      'tenant_id', v_tenant_id,
      'amount', v_credit_applied,
      'currency_code', coalesce(v_wallet.currency_code, v_subscription.currency_code, v_plan.currency_code, 'INR'),
      'reference_type', 'platform_billing_settlement',
      'reference_id', v_settlement.id::text,
      'entry_type', 'settlement_debit',
      'direction', 'debit',
      'notes', format('Settlement debit for %s to %s', v_period_start, v_period_end),
      'metadata', jsonb_build_object('settlement_id', v_settlement.id, 'period_start', v_period_start, 'period_end', v_period_end)
    ));

    if coalesce((v_credit_result->>'success')::boolean, false) is not true then
      return v_credit_result;
    end if;
  end if;

  v_ledger_key := format('f05:settlement:%s:%s:%s', v_tenant_id, v_period_start, v_period_end);

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
    billing_cycle_id,
    entry_status
  ) values (
    v_tenant_id,
    'employee_monthly_active',
    greatest(v_chargeable_user_count, 1),
    case when v_chargeable_user_count = 0 then v_final_amount else v_metric_unit_rate end,
    v_final_amount,
    coalesce(v_subscription.currency_code, v_plan.currency_code, 'INR'),
    'platform_billing_settlement',
    v_settlement.id::text,
    jsonb_build_object(
      'settlement_id', v_settlement.id,
      'period_start', v_period_start,
      'period_end', v_period_end,
      'billable_user_count', v_billable_user_count,
      'chargeable_user_count', v_chargeable_user_count,
      'base_amount', v_base_amount,
      'credit_applied', v_credit_applied
    ),
    v_period_end,
    v_ledger_key,
    v_cycle.id,
    'recorded'
  )
  on conflict (tenant_id, idempotency_key) do update
  set quantity = excluded.quantity,
      unit_price = excluded.unit_price,
      line_amount = excluded.line_amount,
      currency_code = excluded.currency_code,
      source_type = excluded.source_type,
      source_id = excluded.source_id,
      source_reference = excluded.source_reference,
      occurred_on = excluded.occurred_on,
      billing_cycle_id = excluded.billing_cycle_id,
      entry_status = excluded.entry_status
  returning id into v_ledger_id;

  return public.platform_json_response(
    true,
    'OK',
    'Settlement created.',
    jsonb_build_object(
      'settlement', to_jsonb(v_settlement),
      'billing_cycle_id', v_cycle.id,
      'usage_snapshot_id', v_usage_snapshot_id,
      'ledger_id', v_ledger_id,
      'count_result', v_count_details,
      'reused_existing', false
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_create_settlement.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_get_tenant_commercial_gate_state(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_gate_code text := coalesce(nullif(btrim(p_params->>'gate_code'), ''), 'billing_access');
  v_row public.platform_tenant_commercial_state_view%rowtype;
  v_gate_status text;
  v_explanation jsonb;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select * into v_row
  from public.platform_tenant_commercial_state_view
  where tenant_id = v_tenant_id;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant commercial state not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_row.subscription_id is null then
    v_gate_status := 'blocked_unconfigured';
    v_explanation := jsonb_build_object('reason', 'subscription_missing');
  elsif v_row.dues_state = 'overdue' and v_row.background_stop_from is not null and v_row.background_stop_from <= timezone('utc', now()) then
    v_gate_status := 'background_blocked';
    v_explanation := jsonb_build_object('reason', 'dues_overdue_background_blocked', 'background_stop_from', v_row.background_stop_from);
  elsif v_row.dues_state = 'overdue' then
    v_gate_status := 'access_blocked';
    v_explanation := jsonb_build_object('reason', 'dues_overdue', 'overdue_since', v_row.overdue_since);
  elsif v_row.subscription_status in ('expired', 'blocked', 'cancelled') then
    v_gate_status := 'blocked_subscription';
    v_explanation := jsonb_build_object('reason', 'subscription_status', 'subscription_status', v_row.subscription_status);
  elsif v_row.trial_ends_at is not null and v_row.trial_ends_at < timezone('utc', now()) and coalesce(v_row.grace_until, v_row.trial_ends_at) < timezone('utc', now()) and coalesce(v_row.latest_invoice_balance_amount, 0) > 0 then
    v_gate_status := 'payment_required';
    v_explanation := jsonb_build_object('reason', 'trial_or_grace_elapsed_with_balance', 'trial_ends_at', v_row.trial_ends_at, 'grace_until', v_row.grace_until, 'invoice_balance_amount', v_row.latest_invoice_balance_amount);
  else
    v_gate_status := 'clear';
    v_explanation := jsonb_build_object('reason', 'commercial_clear');
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'Tenant commercial gate state resolved.',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'gate_code', v_gate_code,
      'gate_status', v_gate_status,
      'explanation', v_explanation,
      'commercial_state', to_jsonb(v_row)
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_get_tenant_commercial_gate_state.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_initiate_checkout(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_provider_code text := lower(btrim(coalesce(p_params->>'provider_code', '')));
  v_amount numeric(18,2) := nullif(p_params->>'amount', '')::numeric;
  v_currency_code text := nullif(btrim(p_params->>'currency_code'), '');
  v_external_order_id text := nullif(btrim(p_params->>'external_order_id'), '');
  v_return_url text := nullif(btrim(p_params->>'return_url'), '');
  v_cancel_url text := nullif(btrim(p_params->>'cancel_url'), '');
  v_plan_code text := nullif(btrim(p_params->>'plan_code'), '');
  v_settlement_id uuid := nullif(p_params->>'settlement_id', '')::uuid;
  v_invoice_id uuid := nullif(p_params->>'invoice_id', '')::uuid;
  v_invoice_no text := nullif(btrim(p_params->>'invoice_no'), '');
  v_notes text := nullif(btrim(p_params->>'notes'), '');
  v_provider_payload jsonb := coalesce(p_params->'provider_payload', '{}'::jsonb);
  v_order_purpose text := coalesce(nullif(btrim(p_params->>'order_purpose'), ''), case when v_invoice_id is not null or v_invoice_no is not null then 'invoice_payment' when v_settlement_id is not null then 'settlement_payment' else 'wallet_topup' end);
  v_initiated_by uuid := coalesce(nullif(p_params->>'initiated_by', '')::uuid, nullif(p_params->>'user_id', '')::uuid, auth.uid());
  v_payment_order public.platform_payment_order%rowtype;
  v_invoice public.platform_invoice%rowtype;
  v_settlement public.platform_billing_settlement%rowtype;
begin
  if v_provider_code = '' then
    return public.platform_json_response(false, 'COMMERCIAL_PROVIDER_REQUIRED', 'provider_code is required.', '{}'::jsonb);
  end if;

  if v_invoice_id is not null or v_invoice_no is not null then
    if v_invoice_id is not null then
      select * into v_invoice from public.platform_invoice where id = v_invoice_id;
    else
      select * into v_invoice from public.platform_invoice where invoice_no = v_invoice_no;
    end if;

    if not found then
      return public.platform_json_response(false, 'COMMERCIAL_INVOICE_NOT_FOUND', 'Invoice not found.', jsonb_build_object('invoice_id', v_invoice_id, 'invoice_no', v_invoice_no));
    end if;

    v_tenant_id := coalesce(v_tenant_id, v_invoice.tenant_id);
    v_amount := coalesce(v_amount, v_invoice.balance_amount);
    v_currency_code := coalesce(v_currency_code, v_invoice.currency_code);
  end if;

  if v_settlement_id is not null then
    select * into v_settlement from public.platform_billing_settlement where id = v_settlement_id;
    if not found then
      return public.platform_json_response(false, 'COMMERCIAL_SETTLEMENT_NOT_FOUND', 'Settlement not found.', jsonb_build_object('settlement_id', v_settlement_id));
    end if;

    v_tenant_id := coalesce(v_tenant_id, v_settlement.tenant_id);
    v_amount := coalesce(v_amount, v_settlement.final_amount);
  end if;

  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  if v_amount is null or v_amount <= 0 then
    return public.platform_json_response(false, 'COMMERCIAL_CHECKOUT_AMOUNT_REQUIRED', 'amount must be greater than zero.', '{}'::jsonb);
  end if;

  if v_currency_code is null then
    select coalesce(wb.currency_code, pts.currency_code, 'INR') into v_currency_code
    from public.platform_tenant pt
    left join public.platform_wallet_balance wb on wb.tenant_id = pt.tenant_id
    left join public.platform_tenant_subscription pts on pts.tenant_id = pt.tenant_id
    where pt.tenant_id = v_tenant_id;
  end if;

  insert into public.platform_payment_order (
    tenant_id,
    settlement_id,
    invoice_id,
    provider_code,
    external_order_id,
    amount,
    currency_code,
    status,
    checkout_payload,
    initiated_by
  )
  values (
    v_tenant_id,
    v_settlement_id,
    v_invoice.id,
    v_provider_code,
    v_external_order_id,
    v_amount,
    coalesce(v_currency_code, 'INR'),
    case when v_external_order_id is null then 'created' else 'pending' end,
    jsonb_strip_nulls(jsonb_build_object(
      'return_url', v_return_url,
      'cancel_url', v_cancel_url,
      'plan_code', v_plan_code,
      'settlement_id', v_settlement_id,
      'invoice_id', v_invoice.id,
      'notes', v_notes,
      'provider_payload', v_provider_payload,
      'order_purpose', v_order_purpose
    )),
    v_initiated_by
  )
  returning * into v_payment_order;

  return public.platform_json_response(
    true,
    'OK',
    'Payment order created.',
    jsonb_build_object(
      'payment_order', to_jsonb(v_payment_order),
      'provider_request', jsonb_build_object(
        'provider_code', v_provider_code,
        'amount', v_amount,
        'currency_code', coalesce(v_currency_code, 'INR'),
        'order_reference', v_payment_order.id,
        'external_order_id', v_external_order_id,
        'return_url', v_return_url,
        'cancel_url', v_cancel_url,
        'context', jsonb_strip_nulls(jsonb_build_object(
          'tenant_id', v_tenant_id,
          'settlement_id', v_settlement_id,
          'invoice_id', v_invoice.id,
          'plan_code', v_plan_code,
          'order_purpose', v_order_purpose
        ))
      )
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_initiate_checkout.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_process_due_subscription_cycles(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_max_cycles integer := greatest(coalesce(nullif(p_params->>'max_cycles', '')::integer, 1), 1);
  v_processed_cycles integer := 0;
  v_subscription public.platform_tenant_subscription%rowtype;
  v_cycle_start date;
  v_cycle_end date;
  v_next_cycle_start date;
  v_next_cycle_end date;
  v_window_length integer;
  v_settlement_result jsonb;
  v_close_result jsonb;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  loop
    exit when v_processed_cycles >= v_max_cycles;

    select * into v_subscription
    from public.platform_tenant_subscription
    where tenant_id = v_tenant_id
      and subscription_status in ('active', 'trial', 'grace')
    for update;

    exit when not found;
    exit when v_subscription.current_cycle_start is null or v_subscription.current_cycle_end is null;
    exit when v_subscription.current_cycle_end >= current_date;

    v_cycle_start := v_subscription.current_cycle_start;
    v_cycle_end := v_subscription.current_cycle_end;
    v_window_length := (v_cycle_end - v_cycle_start);

    v_settlement_result := public.platform_create_settlement(jsonb_build_object(
      'tenant_id', v_tenant_id,
      'period_start', v_cycle_start,
      'period_end', v_cycle_end,
      'invoice_due_date', v_cycle_end + 7
    ));
    if coalesce((v_settlement_result->>'success')::boolean, false) is not true then
      return v_settlement_result;
    end if;

    v_close_result := public.platform_close_billing_cycle(jsonb_build_object(
      'tenant_id', v_tenant_id,
      'billing_cycle_id', coalesce((v_settlement_result->'details'->>'billing_cycle_id')::uuid, null)
    ));
    if coalesce((v_close_result->>'success')::boolean, false) is not true then
      return v_close_result;
    end if;

    v_next_cycle_start := v_cycle_end + 1;
    v_next_cycle_end := v_next_cycle_start + v_window_length;

    update public.platform_tenant_subscription
    set current_cycle_start = v_next_cycle_start,
        current_cycle_end = v_next_cycle_end,
        updated_at = timezone('utc', now())
    where id = v_subscription.id;

    v_processed_cycles := v_processed_cycles + 1;
  end loop;

  return public.platform_json_response(true, 'OK', 'Due subscription cycles processed.', jsonb_build_object('tenant_id', v_tenant_id, 'processed_cycles', v_processed_cycles));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_process_due_subscription_cycles.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_reconcile_tenant_commercial_summary(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_row public.platform_tenant_commercial_state_view%rowtype;
  v_gate_result jsonb;
  v_gate_details jsonb;
  v_mismatch boolean := false;
  v_reasons jsonb := '[]'::jsonb;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  select * into v_row
  from public.platform_tenant_commercial_state_view
  where tenant_id = v_tenant_id;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant commercial state not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  v_gate_result := public.platform_get_tenant_commercial_gate_state(jsonb_build_object('tenant_id', v_tenant_id));
  v_gate_details := coalesce(v_gate_result->'details', '{}'::jsonb);

  if v_row.dues_state = 'overdue' and coalesce(v_gate_details->>'gate_status', '') = 'clear' then
    v_mismatch := true;
    v_reasons := v_reasons || jsonb_build_array(jsonb_build_object('reason', 'overdue_but_gate_clear'));
  end if;

  if v_row.subscription_id is null and coalesce(v_gate_details->>'gate_status', '') <> 'blocked_unconfigured' then
    v_mismatch := true;
    v_reasons := v_reasons || jsonb_build_array(jsonb_build_object('reason', 'subscription_missing_but_gate_not_unconfigured'));
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'Tenant commercial summary reconciled.',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'mismatch_detected', v_mismatch,
      'reasons', v_reasons,
      'gate_status', v_gate_details->>'gate_status'
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_reconcile_tenant_commercial_summary.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_refresh_feature_gate_cache(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_gate_code text := coalesce(nullif(btrim(p_params->>'gate_code'), ''), 'billing_access');
  v_source_version text := coalesce(nullif(btrim(p_params->>'source_version'), ''), 'platform_refresh_feature_gate_cache/v1');
  v_gate_result jsonb;
  v_details jsonb;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  v_gate_result := public.platform_get_tenant_commercial_gate_state(jsonb_build_object('tenant_id', v_tenant_id, 'gate_code', v_gate_code));
  if coalesce((v_gate_result->>'success')::boolean, false) is not true then
    return v_gate_result;
  end if;

  v_details := coalesce(v_gate_result->'details', '{}'::jsonb);

  insert into public.platform_feature_gate_cache (tenant_id, gate_code, gate_status, evaluated_at, explanation, source_version)
  values (
    v_tenant_id,
    v_gate_code,
    coalesce(v_details->>'gate_status', 'unknown'),
    timezone('utc', now()),
    coalesce(v_details->'explanation', '{}'::jsonb),
    v_source_version
  )
  on conflict (tenant_id, gate_code) do update
  set gate_status = excluded.gate_status,
      evaluated_at = excluded.evaluated_at,
      explanation = excluded.explanation,
      source_version = excluded.source_version;

  return public.platform_json_response(
    true,
    'OK',
    'Feature gate cache refreshed.',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'gate_code', v_gate_code,
      'gate_status', coalesce(v_details->>'gate_status', 'unknown'),
      'source_version', v_source_version
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_refresh_feature_gate_cache.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_sync_tenant_commercial_summary(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_gate_code text := coalesce(nullif(btrim(p_params->>'gate_code'), ''), 'billing_access');
  v_sync_result jsonb;
  v_gate_result jsonb;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  v_sync_result := public.platform_sync_tenant_access_from_commercial(jsonb_build_object('tenant_id', v_tenant_id));
  v_gate_result := public.platform_refresh_feature_gate_cache(jsonb_build_object('tenant_id', v_tenant_id, 'gate_code', v_gate_code, 'source_version', 'platform_sync_tenant_commercial_summary/v1'));

  update public.platform_tenant_commercial_account
  set last_state_synced_at = timezone('utc', now())
  where tenant_id = v_tenant_id;

  return public.platform_json_response(
    true,
    'OK',
    'Tenant commercial summary synced.',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'commercial_sync', coalesce(v_sync_result->'details', '{}'::jsonb),
      'gate_refresh', coalesce(v_gate_result->'details', '{}'::jsonb)
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_sync_tenant_commercial_summary.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_record_payment_event(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_provider_code text := lower(trim(coalesce(p_params->>'provider_code', '')));
  v_external_event_id text := nullif(p_params->>'external_event_id', '');
  v_external_payment_id text := nullif(p_params->>'external_payment_id', '');
  v_external_order_id text := nullif(p_params->>'external_order_id', '');
  v_event_type text := lower(trim(coalesce(p_params->>'event_type', '')));
  v_raw_payload jsonb := coalesce(p_params->'raw_payload', coalesce(p_params->'payload', '{}'::jsonb));
  v_resolved_status text := lower(coalesce(nullif(btrim(p_params->>'resolved_status'), ''), 'pending'));
  v_input_payment_order_id uuid := nullif(p_params->>'payment_order_id', '')::uuid;
  v_input_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_should_process_success boolean;
  v_desired_order_status text;
  v_payment_order public.platform_payment_order%rowtype;
  v_existing_event public.platform_payment_event%rowtype;
  v_payment_event public.platform_payment_event%rowtype;
  v_result jsonb;
  v_credit_result jsonb;
  v_sync_result jsonb;
begin
  if v_provider_code = '' then
    return public.platform_json_response(false, 'COMMERCIAL_PROVIDER_REQUIRED', 'provider_code is required.', '{}'::jsonb);
  end if;

  if v_external_event_id is null then
    return public.platform_json_response(false, 'COMMERCIAL_EVENT_ID_REQUIRED', 'external_event_id is required.', '{}'::jsonb);
  end if;

  if v_event_type = '' then
    return public.platform_json_response(false, 'COMMERCIAL_EVENT_TYPE_REQUIRED', 'event_type is required.', '{}'::jsonb);
  end if;

  select * into v_existing_event
  from public.platform_payment_event
  where provider_code = v_provider_code
    and external_event_id = v_external_event_id;

  if found then
    return public.platform_json_response(true, 'OK', 'Payment event already processed.', jsonb_build_object('payment_event', to_jsonb(v_existing_event), 'idempotent_replay', true));
  end if;

  if v_input_payment_order_id is not null then
    select * into v_payment_order
    from public.platform_payment_order
    where id = v_input_payment_order_id
    for update;
  elsif v_external_order_id is not null then
    select * into v_payment_order
    from public.platform_payment_order
    where provider_code = v_provider_code
      and external_order_id = v_external_order_id
    for update;
  end if;

  v_should_process_success := coalesce((p_params->>'is_payment_success')::boolean, v_resolved_status in ('paid','captured','processed','success'));
  v_desired_order_status := case
    when v_should_process_success then 'paid'
    when v_resolved_status in ('failed') then 'failed'
    when v_resolved_status in ('cancelled') then 'cancelled'
    when v_resolved_status in ('expired') then 'expired'
    else 'pending'
  end;

  insert into public.platform_payment_event (
    provider_code,
    external_event_id,
    external_payment_id,
    tenant_id,
    payment_order_id,
    event_type,
    raw_payload,
    process_status
  )
  values (
    v_provider_code,
    v_external_event_id,
    v_external_payment_id,
    coalesce(v_payment_order.tenant_id, v_input_tenant_id),
    v_payment_order.id,
    v_event_type,
    v_raw_payload,
    case when v_payment_order.id is null then 'ignored' else 'pending' end
  )
  returning * into v_payment_event;

  if v_payment_order.id is null then
    update public.platform_payment_event
    set process_status = 'ignored',
        processed_at = timezone('utc', now()),
        error_details = jsonb_build_object('reason', 'payment_order_not_found', 'external_order_id', v_external_order_id)
    where id = v_payment_event.id
    returning * into v_payment_event;

    return public.platform_json_response(true, 'OK', 'Payment event recorded without matching payment order.', jsonb_build_object('payment_event', to_jsonb(v_payment_event), 'idempotent_replay', false));
  end if;

  if v_external_order_id is not null and v_payment_order.external_order_id is null then
    update public.platform_payment_order
    set external_order_id = v_external_order_id,
        updated_at = timezone('utc', now())
    where id = v_payment_order.id
    returning * into v_payment_order;
  end if;

  update public.platform_payment_order
  set status = case when status = 'paid' then status else v_desired_order_status end,
      updated_at = timezone('utc', now())
  where id = v_payment_order.id
  returning * into v_payment_order;

  if v_should_process_success then
    if v_payment_order.invoice_id is not null then
      v_result := public.platform_apply_payment_receipt(jsonb_build_object(
        'tenant_id', v_payment_order.tenant_id,
        'invoice_id', v_payment_order.invoice_id,
        'provider_code', v_provider_code,
        'external_payment_id', coalesce(v_external_payment_id, v_external_event_id),
        'amount', v_payment_order.amount,
        'currency_code', v_payment_order.currency_code,
        'details', jsonb_build_object('external_event_id', v_external_event_id, 'payment_order_id', v_payment_order.id, 'raw_payload', v_raw_payload)
      ));
    else
      v_credit_result := public.platform_apply_payment_credit(jsonb_build_object(
        'tenant_id', v_payment_order.tenant_id,
        'amount', v_payment_order.amount,
        'currency_code', v_payment_order.currency_code,
        'reference_type', 'payment_order',
        'reference_id', v_payment_order.id::text,
        'entry_type', 'payment_credit',
        'direction', 'credit',
        'notes', format('Payment credit via %s', v_provider_code),
        'metadata', jsonb_build_object('external_event_id', v_external_event_id, 'external_payment_id', v_external_payment_id, 'provider_code', v_provider_code)
      ));
      v_result := v_credit_result;
    end if;

    if coalesce((v_result->>'success')::boolean, false) is not true then
      update public.platform_payment_event
      set process_status = 'failed',
          processed_at = timezone('utc', now()),
          error_details = coalesce(v_result->'details', jsonb_build_object('message', v_result->>'message'))
      where id = v_payment_event.id
      returning * into v_payment_event;

      return v_result;
    end if;

    if v_payment_order.settlement_id is not null then
      update public.platform_billing_settlement
      set settlement_status = 'settled',
          settled_at = coalesce(settled_at, timezone('utc', now()))
      where id = v_payment_order.settlement_id
        and tenant_id = v_payment_order.tenant_id
        and settlement_status in ('draft', 'pending_payment');

      update public.platform_invoice
      set invoice_status = 'paid',
          paid_amount = total_amount,
          balance_amount = 0,
          updated_at = timezone('utc', now())
      where settlement_id = v_payment_order.settlement_id
        and tenant_id = v_payment_order.tenant_id
        and invoice_status in ('issued', 'overdue', 'partially_paid');
    end if;

    update public.platform_tenant_subscription
    set subscription_status = case when subscription_status in ('blocked', 'grace', 'expired') then 'active' else subscription_status end,
        updated_at = timezone('utc', now())
    where tenant_id = v_payment_order.tenant_id;
  end if;

  update public.platform_payment_event
  set process_status = 'processed',
      processed_at = timezone('utc', now()),
      payment_order_id = v_payment_order.id,
      tenant_id = v_payment_order.tenant_id
  where id = v_payment_event.id
  returning * into v_payment_event;

  v_sync_result := public.platform_sync_tenant_commercial_summary(jsonb_build_object('tenant_id', v_payment_order.tenant_id));

  return public.platform_json_response(
    true,
    'OK',
    'Payment event recorded.',
    jsonb_build_object(
      'payment_order', to_jsonb(v_payment_order),
      'payment_event', to_jsonb(v_payment_event),
      'processing_result', coalesce(v_result->'details', '{}'::jsonb),
      'summary_sync', coalesce(v_sync_result->'details', '{}'::jsonb),
      'idempotent_replay', false
    )
  );
exception
  when others then
    update public.platform_payment_event
    set process_status = 'failed',
        processed_at = timezone('utc', now()),
        error_details = jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
    where id = v_payment_event.id;

    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_record_payment_event.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

CREATE OR REPLACE FUNCTION public.platform_upsert_tenant_subscription(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_plan_id uuid := nullif(p_params->>'plan_id', '')::uuid;
  v_plan_code text := lower(btrim(coalesce(p_params->>'plan_code', '')));
  v_subscription_status text := coalesce(nullif(btrim(p_params->>'subscription_status'), ''), 'active');
  v_currency_code text := coalesce(nullif(btrim(p_params->>'currency_code'), ''), 'INR');
  v_cycle_anchor_day integer := coalesce(nullif(p_params->>'cycle_anchor_day', '')::integer, 1);
  v_current_cycle_start date := nullif(p_params->>'current_cycle_start', '')::date;
  v_current_cycle_end date := nullif(p_params->>'current_cycle_end', '')::date;
  v_trial_started_at timestamptz := nullif(p_params->>'trial_started_at', '')::timestamptz;
  v_trial_ends_at timestamptz := nullif(p_params->>'trial_ends_at', '')::timestamptz;
  v_grace_until timestamptz := nullif(p_params->>'grace_until', '')::timestamptz;
  v_wallet_required boolean := coalesce((p_params->>'wallet_required')::boolean, true);
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

  insert into public.platform_tenant_commercial_account (tenant_id, commercial_status, dues_state)
  values (v_tenant_id, 'clear', 'clear')
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
    trial_started_at,
    trial_ends_at,
    grace_until,
    wallet_required,
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
    v_trial_started_at,
    v_trial_ends_at,
    v_grace_until,
    v_wallet_required,
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
    trial_started_at = excluded.trial_started_at,
    trial_ends_at = excluded.trial_ends_at,
    grace_until = excluded.grace_until,
    wallet_required = excluded.wallet_required,
    auto_renew = excluded.auto_renew,
    metadata = excluded.metadata
  returning id into v_subscription_id;

  insert into public.platform_wallet_balance (tenant_id, currency_code)
  values (v_tenant_id, v_currency_code)
  on conflict (tenant_id) do update
  set currency_code = excluded.currency_code;

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

CREATE OR REPLACE FUNCTION public.platform_commercial_orchestrator(p_params jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_run_settlement boolean := coalesce((p_params->>'run_settlement')::boolean, true);
  v_run_overdue_sync boolean := coalesce((p_params->>'run_overdue_sync')::boolean, true);
  v_tenant_limit integer := greatest(coalesce(nullif(p_params->>'tenant_limit', '')::integer, 100), 1);
  v_max_cycles_per_tenant integer := greatest(coalesce(nullif(p_params->>'max_cycles_per_tenant', '')::integer, 1), 1);
  v_processed integer := 0;
  v_synced integer := 0;
  v_result jsonb;
  v_row record;
begin
  if v_tenant_id is not null then
    if v_run_settlement then
      v_result := public.platform_process_due_subscription_cycles(jsonb_build_object('tenant_id', v_tenant_id, 'max_cycles', v_max_cycles_per_tenant));
      if coalesce((v_result->>'success')::boolean, false) is not true then
        return v_result;
      end if;
      v_processed := coalesce((v_result->'details'->>'processed_cycles')::integer, 0);
    end if;

    if v_run_overdue_sync then
      perform public.platform_sync_tenant_commercial_summary(jsonb_build_object('tenant_id', v_tenant_id));
      v_synced := 1;
    end if;

    return public.platform_json_response(true, 'OK', 'Commercial orchestrator completed.', jsonb_build_object('tenant_id', v_tenant_id, 'processed_tenants', case when v_processed > 0 or v_synced > 0 then 1 else 0 end, 'processed_cycles', v_processed, 'overdue_syncs', v_synced));
  end if;

  if v_run_settlement then
    for v_row in
      select pts.tenant_id
      from public.platform_tenant_subscription pts
      where pts.subscription_status in ('active', 'trial', 'grace')
        and pts.current_cycle_end is not null
        and pts.current_cycle_end < current_date
      order by pts.current_cycle_end asc
      limit v_tenant_limit
    loop
      v_result := public.platform_process_due_subscription_cycles(jsonb_build_object('tenant_id', v_row.tenant_id, 'max_cycles', v_max_cycles_per_tenant));
      if coalesce((v_result->>'success')::boolean, false) is true then
        v_processed := v_processed + 1;
      end if;

      if v_run_overdue_sync then
        perform public.platform_sync_tenant_commercial_summary(jsonb_build_object('tenant_id', v_row.tenant_id));
        v_synced := v_synced + 1;
      end if;
    end loop;
  end if;

  if v_run_overdue_sync then
    for v_row in
      select distinct pca.tenant_id
      from public.platform_tenant_commercial_account pca
      where pca.dues_state = 'overdue'
      order by pca.tenant_id
      limit v_tenant_limit
    loop
      perform public.platform_sync_tenant_commercial_summary(jsonb_build_object('tenant_id', v_row.tenant_id));
      v_synced := v_synced + 1;
    end loop;
  end if;

  return public.platform_json_response(true, 'OK', 'Commercial orchestrator completed.', jsonb_build_object('processed_tenants', v_processed, 'overdue_syncs', v_synced, 'run_settlement', v_run_settlement, 'run_overdue_sync', v_run_overdue_sync, 'tenant_limit', v_tenant_limit, 'max_cycles_per_tenant', v_max_cycles_per_tenant));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_commercial_orchestrator.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

revoke all on function public.platform_apply_payment_credit(jsonb) from public, anon, authenticated;
revoke all on function public.platform_apply_payment_receipt(jsonb) from public, anon, authenticated;
revoke all on function public.platform_attach_payment_order(jsonb) from public, anon, authenticated;
revoke all on function public.platform_close_billing_cycle(jsonb) from public, anon, authenticated;
revoke all on function public.platform_commercial_orchestrator(jsonb) from public, anon, authenticated;
revoke all on function public.platform_count_billable_users(jsonb) from public, anon, authenticated;
revoke all on function public.platform_create_or_update_subscription(jsonb) from public, anon, authenticated;
revoke all on function public.platform_create_settlement(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_tenant_commercial_gate_state(jsonb) from public, anon, authenticated;
revoke all on function public.platform_initiate_checkout(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_due_subscription_cycles(jsonb) from public, anon, authenticated;
revoke all on function public.platform_reconcile_tenant_commercial_summary(jsonb) from public, anon, authenticated;
revoke all on function public.platform_record_payment_event(jsonb) from public, anon, authenticated;
revoke all on function public.platform_refresh_feature_gate_cache(jsonb) from public, anon, authenticated;
revoke all on function public.platform_sync_tenant_commercial_summary(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_tenant_subscription(jsonb) from public, anon, authenticated;

grant execute on function public.platform_apply_payment_credit(jsonb) to postgres, service_role;
grant execute on function public.platform_apply_payment_receipt(jsonb) to postgres, service_role;
grant execute on function public.platform_attach_payment_order(jsonb) to postgres, service_role;
grant execute on function public.platform_close_billing_cycle(jsonb) to postgres, service_role;
grant execute on function public.platform_commercial_orchestrator(jsonb) to postgres, service_role;
grant execute on function public.platform_count_billable_users(jsonb) to postgres, service_role;
grant execute on function public.platform_create_or_update_subscription(jsonb) to postgres, service_role;
grant execute on function public.platform_create_settlement(jsonb) to postgres, service_role;
grant execute on function public.platform_get_tenant_commercial_gate_state(jsonb) to postgres, service_role;
grant execute on function public.platform_initiate_checkout(jsonb) to postgres, service_role;
grant execute on function public.platform_process_due_subscription_cycles(jsonb) to postgres, service_role;
grant execute on function public.platform_reconcile_tenant_commercial_summary(jsonb) to postgres, service_role;
grant execute on function public.platform_record_payment_event(jsonb) to postgres, service_role;
grant execute on function public.platform_refresh_feature_gate_cache(jsonb) to postgres, service_role;
grant execute on function public.platform_sync_tenant_commercial_summary(jsonb) to postgres, service_role;
grant execute on function public.platform_upsert_tenant_subscription(jsonb) to postgres, service_role;
