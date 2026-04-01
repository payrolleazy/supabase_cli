create index if not exists platform_billing_settlement_billing_cycle_id_idx
  on public.platform_billing_settlement using btree (billing_cycle_id)
  where billing_cycle_id is not null;

create index if not exists platform_invoice_settlement_id_idx
  on public.platform_invoice using btree (settlement_id)
  where settlement_id is not null;

create index if not exists platform_payment_order_settlement_id_idx
  on public.platform_payment_order using btree (settlement_id)
  where settlement_id is not null;

create index if not exists platform_payment_order_invoice_id_idx
  on public.platform_payment_order using btree (invoice_id)
  where invoice_id is not null;

create index if not exists platform_payment_event_payment_order_id_idx
  on public.platform_payment_event using btree (payment_order_id)
  where payment_order_id is not null;
