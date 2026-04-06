create temp table if not exists pg_temp.hierarchy_case_tokens (token_key text primary key, token_value text not null);
truncate table pg_temp.hierarchy_case_tokens;

do $$
declare
  v_schema_name text;
  v_group_id bigint;
begin
  select schema_name into v_schema_name from public.platform_tenant where tenant_id = '{{HIER_TENANT_ID}}'::uuid;
  if v_schema_name is null then raise exception 'HIERARCHY tenant not found for run {{RUN_ID}}'; end if;
  execute format('select position_group_id from %I.hierarchy_position_group where position_group_code = $1 limit 1', v_schema_name)
  into v_group_id using 'hier-extra-grp-{{RUN_ID}}';
  if v_group_id is null then raise exception 'HIERARCHY extra position group not found for run {{RUN_ID}}'; end if;
  insert into pg_temp.hierarchy_case_tokens (token_key, token_value) values ('HIER_EXTRA_GROUP_ID', v_group_id::text);
end;
$$;

select json_object_agg(token_key, token_value)::text from pg_temp.hierarchy_case_tokens;
