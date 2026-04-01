begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(28);

select has_table('public', 'platform_employee_usage_snapshot', 'F05 exposes the employee-usage snapshot table.');
select has_table('public', 'platform_billing_settlement', 'F05 exposes the billing-settlement table.');
select has_table('public', 'platform_wallet_balance', 'F05 exposes the wallet-balance table.');
select has_table('public', 'platform_wallet_ledger', 'F05 exposes the wallet-ledger table.');
select has_table('public', 'platform_payment_order', 'F05 exposes the payment-order table.');
select has_table('public', 'platform_payment_event', 'F05 exposes the payment-event table.');
select has_table('public', 'platform_feature_gate_cache', 'F05 exposes the feature-gate cache table.');
select has_view('public', 'platform_tenant_commercial_state_view', 'F05 exposes the tenant commercial-state view.');
select has_view('public', 'platform_rm_tenant_commercial_state', 'F05 exposes the read-model commercial-state view.');
select has_function('public', 'platform_apply_payment_credit', array['jsonb'], 'F05 wallet-credit contract exists.');
select has_function('public', 'platform_create_or_update_subscription', array['jsonb'], 'F05 subscription upsert contract exists.');
select has_function('public', 'platform_get_tenant_commercial_gate_state', array['jsonb'], 'F05 commercial-gate state contract exists.');
select has_function('public', 'platform_initiate_checkout', array['jsonb'], 'F05 checkout-initiation contract exists.');
select has_function('public', 'platform_record_payment_event', array['jsonb'], 'F05 payment-event contract exists.');
select has_function('public', 'platform_create_settlement', array['jsonb'], 'F05 settlement contract exists.');
select has_function('public', 'platform_process_due_subscription_cycles', array['jsonb'], 'F05 due-cycle processing contract exists.');
select has_function('public', 'platform_refresh_feature_gate_cache', array['jsonb'], 'F05 feature-gate refresh contract exists.');
select has_function('public', 'platform_sync_tenant_commercial_summary', array['jsonb'], 'F05 commercial-summary sync contract exists.');
select has_function('public', 'platform_commercial_orchestrator', array['jsonb'], 'F05 commercial orchestrator exists.');
select ok(exists (select 1 from pg_extension where extname = 'pg_cron'), 'F05 keeps pg_cron installed.') as f05_pg_cron_installed_check;
select ok(exists (select 1 from pg_extension where extname = 'pg_net'), 'F05 keeps pg_net installed.') as f05_pg_net_installed_check;
select ok(exists (select 1 from cron.job where jobname = 'f05-commercial-orchestrator' and active), 'F05 keeps the commercial orchestrator cron job active.') as f05_cron_job_active_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_billing_settlement'), 'F05 billing-settlement table has RLS enabled.') as f05_billing_settlement_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_wallet_balance'), 'F05 wallet-balance table has RLS enabled.') as f05_wallet_balance_rls_check;
select is((select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'platform_billing_settlement'), 1, 'F05 billing-settlement table keeps exactly one policy in the current slice.');
select is((select count(*)::integer from pg_policies where schemaname = 'public' and tablename = 'platform_payment_order'), 1, 'F05 payment-order table keeps exactly one policy in the current slice.');
select ok(not exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_apply_payment_credit',
      'platform_initiate_checkout',
      'platform_record_payment_event',
      'platform_create_settlement',
      'platform_process_due_subscription_cycles',
      'platform_refresh_feature_gate_cache',
      'platform_sync_tenant_commercial_summary',
      'platform_commercial_orchestrator'
    )
    and grantee in ('anon', 'authenticated')
), 'F05 commercial runtime functions are not executable by anon/authenticated.') as f05_runtime_grant_check;
select is((
  select count(*)::integer
  from public.platform_gateway_operation
  where binding_ref in (
    'platform_apply_payment_credit',
    'platform_create_or_update_subscription',
    'platform_get_tenant_commercial_gate_state',
    'platform_initiate_checkout',
    'platform_record_payment_event',
    'platform_create_settlement',
    'platform_process_due_subscription_cycles',
    'platform_refresh_feature_gate_cache',
    'platform_sync_tenant_commercial_summary',
    'platform_commercial_orchestrator'
  )
), 0, 'F05 raw commercial runtime contracts are not directly registered as gateway operations.');

select * from finish();

rollback;