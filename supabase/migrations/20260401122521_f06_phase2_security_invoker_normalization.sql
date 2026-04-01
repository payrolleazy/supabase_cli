do $$
declare
  v_row record;
  v_altered_count integer := 0;
  v_expected_count integer := 99;
  v_remaining_non_invoker_views integer;
begin
  for v_row in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname like 'platform_rm_%'
      and c.relkind = 'v'
      and coalesce((select bool_or(option_name = 'security_invoker' and option_value = 'true') from pg_options_to_table(c.reloptions)), false) is not true
    order by c.relname
  loop
    execute format('alter view public.%I set (security_invoker = true)', v_row.relname);
    v_altered_count := v_altered_count + 1;
  end loop;

  if v_altered_count <> v_expected_count then
    raise exception 'F06 Phase 2 expected to alter % views, altered %.', v_expected_count, v_altered_count;
  end if;

  select count(*)::int
  into v_remaining_non_invoker_views
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname like 'platform_rm_%'
    and c.relkind = 'v'
    and coalesce((select bool_or(option_name = 'security_invoker' and option_value = 'true') from pg_options_to_table(c.reloptions)), false) is not true;

  if v_remaining_non_invoker_views <> 0 then
    raise exception 'F06 Phase 2 incomplete: % non-security-invoker plain views remain.', v_remaining_non_invoker_views;
  end if;
end
$$;

