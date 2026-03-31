alter view public.platform_tenant_commercial_state_view set (security_invoker = true);

create index if not exists idx_platform_billing_cycle_subscription_id
on public.platform_billing_cycle (subscription_id);

create index if not exists idx_platform_payment_receipt_invoice_id
on public.platform_payment_receipt (invoice_id);

create index if not exists idx_platform_billable_unit_ledger_invoice_id
on public.platform_billable_unit_ledger (invoice_id);

create index if not exists idx_platform_billable_unit_ledger_reversal_of_id
on public.platform_billable_unit_ledger (reversal_of_id);;
