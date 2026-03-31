create or replace function public.platform_close_billing_cycle(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_cycle_id uuid := nullif(p_params->>'billing_cycle_id', '')::uuid;
  v_cycle public.platform_billing_cycle%rowtype;
  v_invoice public.platform_invoice%rowtype;
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

  select *
  into v_cycle
  from public.platform_billing_cycle
  where id = v_cycle_id
    and tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'COMMERCIAL_BILLING_CYCLE_NOT_FOUND', 'Billing cycle not found.', jsonb_build_object('billing_cycle_id', v_cycle_id));
  end if;

  if v_cycle.cycle_status <> 'open' then
    return public.platform_json_response(false, 'COMMERCIAL_INVALID_CYCLE_STATE', 'Billing cycle is not open.', jsonb_build_object('billing_cycle_id', v_cycle_id, 'cycle_status', v_cycle.cycle_status));
  end if;

  select coalesce(round(sum(line_amount)::numeric, 2), 0)
  into v_subtotal
  from public.platform_billable_unit_ledger
  where tenant_id = v_tenant_id
    and occurred_on between v_cycle.cycle_start and v_cycle.cycle_end
    and billing_cycle_id is null
    and entry_status = 'recorded';

  v_invoice_no := public.platform_build_invoice_no(v_cycle.cycle_end);

  insert into public.platform_invoice (
    tenant_id,
    billing_cycle_id,
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
    v_invoice_no,
    'issued',
    current_date,
    v_cycle.invoice_due_date,
    v_cycle.currency_code,
    v_subtotal,
    v_subtotal,
    0,
    v_subtotal,
    jsonb_build_object(
      'billing_cycle_id', v_cycle.id,
      'cycle_start', v_cycle.cycle_start,
      'cycle_end', v_cycle.cycle_end
    )
  )
  returning * into v_invoice;

  update public.platform_billing_cycle
  set
    cycle_status = case when v_subtotal = 0 then 'paid' else 'invoiced' end,
    subtotal_amount = v_subtotal,
    total_amount = v_subtotal,
    balance_amount = v_subtotal,
    closed_at = timezone('utc', now())
  where id = v_cycle.id
  returning * into v_cycle;

  update public.platform_billable_unit_ledger
  set
    billing_cycle_id = v_cycle.id,
    invoice_id = v_invoice.id,
    entry_status = 'invoiced'
  where tenant_id = v_tenant_id
    and occurred_on between v_cycle.cycle_start and v_cycle.cycle_end
    and billing_cycle_id is null
    and entry_status = 'recorded';

  update public.platform_tenant_commercial_account
  set
    last_invoiced_at = timezone('utc', now()),
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
      'total_amount', v_invoice.total_amount
    )
  );
exception
  when unique_violation then
    return public.platform_json_response(false, 'COMMERCIAL_DUPLICATE_INVOICE', 'Invoice already exists for this billing cycle.', jsonb_build_object('billing_cycle_id', v_cycle_id));
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_close_billing_cycle.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_apply_payment_receipt(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
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
  on conflict (provider_code, external_payment_id) do update
  set details = public.platform_payment_receipt.details
  returning * into v_receipt;

  v_new_paid := round((v_invoice.paid_amount + v_amount)::numeric, 2);
  v_new_balance := greatest(round((v_invoice.total_amount - v_new_paid)::numeric, 2), 0);

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
      'invoice_balance_amount', v_invoice.balance_amount
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_apply_payment_receipt.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

revoke all on table public.platform_plan_catalog from public, anon, authenticated;
revoke all on table public.platform_plan_metric_rate from public, anon, authenticated;
revoke all on table public.platform_tenant_commercial_account from public, anon, authenticated;
revoke all on table public.platform_tenant_subscription from public, anon, authenticated;
revoke all on table public.platform_billing_cycle from public, anon, authenticated;
revoke all on table public.platform_invoice from public, anon, authenticated;
revoke all on table public.platform_payment_receipt from public, anon, authenticated;
revoke all on table public.platform_billable_unit_ledger from public, anon, authenticated;

revoke all on function public.platform_get_effective_plan_rate(uuid, text, date) from public, anon, authenticated;
revoke all on function public.platform_build_invoice_no(date) from public, anon, authenticated;
revoke all on function public.platform_register_plan(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_plan_metric_rate(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_tenant_subscription(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_billable_unit(jsonb) from public, anon, authenticated;
revoke all on function public.platform_open_billing_cycle(jsonb) from public, anon, authenticated;
revoke all on function public.platform_close_billing_cycle(jsonb) from public, anon, authenticated;
revoke all on function public.platform_apply_payment_receipt(jsonb) from public, anon, authenticated;
revoke all on function public.platform_sync_tenant_access_from_commercial(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_tenant_commercial_state(jsonb) from public, anon, authenticated;

grant usage, select on sequence public.platform_invoice_no_seq to service_role;
grant select, insert, update, delete on table public.platform_plan_catalog to service_role;
grant select, insert, update, delete on table public.platform_plan_metric_rate to service_role;
grant select, insert, update, delete on table public.platform_tenant_commercial_account to service_role;
grant select, insert, update, delete on table public.platform_tenant_subscription to service_role;
grant select, insert, update, delete on table public.platform_billing_cycle to service_role;
grant select, insert, update, delete on table public.platform_invoice to service_role;
grant select, insert, update, delete on table public.platform_payment_receipt to service_role;
grant select, insert, update, delete on table public.platform_billable_unit_ledger to service_role;
grant execute on function public.platform_register_plan(jsonb) to service_role;
grant execute on function public.platform_register_plan_metric_rate(jsonb) to service_role;
grant execute on function public.platform_upsert_tenant_subscription(jsonb) to service_role;
grant execute on function public.platform_register_billable_unit(jsonb) to service_role;
grant execute on function public.platform_open_billing_cycle(jsonb) to service_role;
grant execute on function public.platform_close_billing_cycle(jsonb) to service_role;
grant execute on function public.platform_apply_payment_receipt(jsonb) to service_role;
grant execute on function public.platform_sync_tenant_access_from_commercial(jsonb) to service_role;
grant execute on function public.platform_get_tenant_commercial_state(jsonb) to service_role;;
