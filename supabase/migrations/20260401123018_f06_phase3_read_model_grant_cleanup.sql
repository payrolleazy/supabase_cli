do $$
declare
  v_row record;
  v_cleaned_count integer := 0;
  v_expected_count integer := 65;
  v_remaining_broad_count integer;
begin
  for v_row in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname like 'platform_rm_%'
      and c.relkind in ('v','m')
      and (
        coalesce(c.relacl::text, '') ilike '%anon=%'
        or coalesce(c.relacl::text, '') ilike '%authenticated=%'
        or coalesce(c.relacl::text, '') ilike '%=r/%'
      )
    order by c.relname
  loop
    execute format('revoke all on public.%I from public, anon, authenticated', v_row.relname);
    execute format('grant select on public.%I to service_role', v_row.relname);
    v_cleaned_count := v_cleaned_count + 1;
  end loop;

  if v_cleaned_count <> v_expected_count then
    raise exception 'F06 Phase 3 expected to clean % views, cleaned %.', v_expected_count, v_cleaned_count;
  end if;

  select count(*)::int
  into v_remaining_broad_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname like 'platform_rm_%'
    and c.relkind in ('v','m')
    and (
      coalesce(c.relacl::text, '') ilike '%anon=%'
      or coalesce(c.relacl::text, '') ilike '%authenticated=%'
      or coalesce(c.relacl::text, '') ilike '%=r/%'
    );

  if v_remaining_broad_count <> 0 then
    raise exception 'F06 Phase 3 incomplete: % broad-grant platform_rm_* surfaces remain.', v_remaining_broad_count;
  end if;
end
$$;


