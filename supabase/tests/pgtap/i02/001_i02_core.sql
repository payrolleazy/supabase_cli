begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(27);

select has_table('public', 'platform_client_provision_request', 'I02 exposes the client provision-request table.');
select has_table('public', 'platform_client_provision_event', 'I02 exposes the client provision-event table.');
select has_table('public', 'platform_client_purchase_checkout', 'I02 exposes the client purchase-checkout table.');
select has_table('public', 'platform_client_purchase_event', 'I02 exposes the client purchase-event table.');
select has_table('public', 'platform_owner_bootstrap_token', 'I02 exposes the owner bootstrap-token table.');
select has_table('public', 'platform_schema_provisioning_run', 'I02 exposes the schema provisioning-run table.');
select has_view('public', 'platform_rm_client_provision_state', 'I02 exposes the client provision-state read model.');
select has_view('public', 'platform_schema_provisioning_view', 'I02 exposes the schema provisioning view.');
select ok(to_regprocedure('public.platform_capture_client_provision_intent(jsonb)') is not null, 'I02 exposes the capture-intent contract.') as i02_capture_intent_exists;
select ok(to_regprocedure('public.platform_get_client_provision_state(jsonb)') is not null, 'I02 exposes the client provision-state contract.') as i02_get_provision_state_exists;
select ok(to_regprocedure('public.platform_accept_purchase_activation(jsonb)') is not null, 'I02 exposes the purchase-activation contract.') as i02_accept_purchase_activation_exists;
select ok(to_regprocedure('public.platform_issue_owner_bootstrap_token(jsonb)') is not null, 'I02 exposes the owner bootstrap-token issue contract.') as i02_issue_owner_bootstrap_token_exists;
select ok(to_regprocedure('public.platform_get_owner_bootstrap_context(jsonb)') is not null, 'I02 exposes the owner bootstrap-context contract.') as i02_get_bootstrap_context_exists;
select ok(to_regprocedure('public.platform_consume_owner_bootstrap_token(jsonb)') is not null, 'I02 exposes the owner bootstrap-token consume contract.') as i02_consume_bootstrap_token_exists;
select ok(to_regprocedure('public.platform_bootstrap_client_tenant_header(jsonb)') is not null, 'I02 exposes the tenant-header bootstrap contract.') as i02_bootstrap_tenant_header_exists;
select ok(to_regprocedure('public.platform_bind_client_owner_admin(jsonb)') is not null, 'I02 exposes the owner-admin bind contract.') as i02_bind_owner_admin_exists;
select ok(to_regprocedure('public.platform_seed_client_owner_setup_state(jsonb)') is not null, 'I02 exposes the owner setup-state seed contract.') as i02_seed_owner_setup_exists;
select ok(not exists (
  select 1
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_accept_purchase_activation',
      'platform_bind_client_owner_admin',
      'platform_capture_client_provision_intent',
      'platform_consume_owner_bootstrap_token',
      'platform_get_client_provision_state',
      'platform_get_owner_bootstrap_context',
      'platform_issue_owner_bootstrap_token',
      'platform_seed_client_owner_setup_state'
    )
    and grantee in ('anon', 'authenticated')
), 'I02 core runtime contracts are not executable by anon/authenticated.') as i02_low_privilege_grant_check;
select is((
  select count(*)::integer
  from information_schema.role_routine_grants
  where routine_schema = 'public'
    and routine_name in (
      'platform_accept_purchase_activation',
      'platform_bind_client_owner_admin',
      'platform_capture_client_provision_intent',
      'platform_consume_owner_bootstrap_token',
      'platform_get_client_provision_state',
      'platform_get_owner_bootstrap_context',
      'platform_issue_owner_bootstrap_token',
      'platform_seed_client_owner_setup_state'
    )
    and grantee = 'service_role'
), 8, 'I02 core runtime contracts are executable by service_role in the current slice.');
select is((
  select count(*)::integer
  from public.platform_read_model_catalog
  where module_code = 'I02'
    and object_name = 'platform_rm_client_provision_state'
), 1, 'I02 owns the client provision-state read-model catalog entry.');
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_client_provision_request'), 'I02 client provision-request keeps RLS enabled.') as i02_provision_request_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_client_purchase_checkout'), 'I02 client purchase-checkout keeps RLS enabled.') as i02_purchase_checkout_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_client_purchase_event'), 'I02 client purchase-event keeps RLS enabled.') as i02_purchase_event_rls_check;
select ok((select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_owner_bootstrap_token'), 'I02 owner bootstrap-token table keeps RLS enabled.') as i02_bootstrap_token_rls_check;
select is((
  select count(*)::integer
  from public.platform_async_worker_registry
  where module_code = 'I02'
), 0, 'I02 currently keeps no dedicated async-worker registry rows in the current slice.');
select is((
  select count(*)::integer
  from public.platform_gateway_operation
  where operation_code ilike '%purchase%'
     or operation_code ilike '%provision%'
     or operation_code ilike '%bootstrap%'
     or binding_ref ilike '%purchase%'
     or binding_ref ilike '%provision%'
     or binding_ref ilike '%bootstrap%'
), 0, 'I02 currently keeps no platform gateway-operation rows in the current slice.');
select is((
  select count(*)::integer
  from cron.job
  where command ilike '%purchase%'
     or command ilike '%provision%'
     or command ilike '%bootstrap%'
     or command ilike '%owner%'
     or command ilike '%credential%'
), 0, 'I02 currently keeps no dedicated cron jobs in the current slice.');

select * from finish();

rollback;

