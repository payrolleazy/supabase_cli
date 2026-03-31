begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(14);

select has_table('public', 'platform_actor_tenant_membership', 'F03 exposes the actor-tenant membership table.');
select has_view('public', 'platform_actor_tenant_membership_view', 'F03 exposes the governed actor-tenant membership view.');
select has_function('public', 'platform_register_actor_tenant_membership', array['jsonb'], 'F03 membership registration contract exists.');
select has_function('public', 'platform_resolve_client_execution_context', array['jsonb'], 'F03 client execution-context resolver exists.');
select has_function('public', 'platform_resolve_background_execution_context', array['jsonb'], 'F03 background execution-context resolver exists.');
select has_function('public', 'platform_apply_execution_context', array['jsonb'], 'F03 context application contract exists.');
select has_function('public', 'platform_get_current_execution_context', array[]::text[], 'F03 current execution-context getter exists.');
select ok(
  exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'platform_actor_tenant_membership'
      and c.relrowsecurity
  ),
  'F03 membership table has RLS enabled.'
) as f03_rls_enabled_check;
select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'public'
      and tablename = 'platform_actor_tenant_membership'
  ),
  1,
  'F03 membership table keeps exactly one policy in the current slice.'
) as f03_policy_count_check;
select ok(
  not exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name = 'platform_actor_tenant_membership'
      and grantee in ('anon', 'authenticated')
  ),
  'F03 base membership table is not granted to anon/authenticated.'
) as f03_table_grant_check;
select ok(
  not exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name = 'platform_actor_tenant_membership_view'
      and grantee in ('anon', 'authenticated')
  ),
  'F03 base membership view is not granted to anon/authenticated.'
) as f03_view_grant_check;
select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'platform_apply_execution_context'
      and p.prosecdef
  ),
  'F03 apply_execution_context remains SECURITY DEFINER.'
) as f03_apply_security_check;
select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'platform_get_current_execution_context'
      and not p.prosecdef
  ),
  'F03 get_current_execution_context remains SECURITY INVOKER.'
) as f03_getter_security_check;
select is(
  (
    select count(*)::integer
    from public.platform_gateway_operation
    where binding_ref ilike '%platform_apply_execution_context%'
       or binding_ref ilike '%platform_register_actor_tenant_membership%'
       or binding_ref ilike '%platform_resolve_client_execution_context%'
       or binding_ref ilike '%platform_resolve_background_execution_context%'
  ),
  0,
  'F03 raw execution-context functions are not directly registered as gateway operations.'
) as f03_gateway_binding_check;

select * from finish();

rollback;
