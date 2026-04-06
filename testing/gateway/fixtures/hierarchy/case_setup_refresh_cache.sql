do $$
declare v_result jsonb;
begin
  v_result := public.platform_hierarchy_run_maintenance(jsonb_build_object('source', 'gateway_certification'));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'HIERARCHY maintenance refresh failed for run {{RUN_ID}}: %', v_result::text;
  end if;
end;
$$;

select '{}'::jsonb::text;
