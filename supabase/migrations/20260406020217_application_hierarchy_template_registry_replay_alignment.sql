do $do$
declare
  v_result jsonb;
  v_row jsonb;
begin
  v_result := public.platform_register_template_version(
    jsonb_build_object(
      'template_version', 'hierarchy_v1',
      'template_scope', 'module',
      'template_status', 'released',
      'foundation_version', 'I06',
      'description', 'HIERARCHY tenant-owned position and occupancy baseline.',
      'release_notes', jsonb_build_object(
        'slice', 'HIERARCHY',
        'module_code', 'HIERARCHY',
        'depends_on', jsonb_build_array('WCM_CORE', 'I03', 'I04', 'F06'),
        'tenant_owned_tables', jsonb_build_array(
          'hierarchy_position_group',
          'hierarchy_position',
          'hierarchy_position_occupancy',
          'hierarchy_position_occupancy_history'
        )
      )
    )
  );

  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'HIERARCHY template-version replay alignment failed: %', v_result;
  end if;

  for v_row in
    select *
    from jsonb_array_elements(
      $json$
      [
        {
          "template_version": "hierarchy_v1",
          "module_code": "HIERARCHY",
          "source_schema_name": "public",
          "source_table_name": "hierarchy_position_group",
          "target_table_name": "hierarchy_position_group",
          "clone_order": 200,
          "clone_enabled": true,
          "seed_mode": "none",
          "seed_filter": {},
          "notes": {"kind": "tenant_owned_table", "slice": "HIERARCHY"}
        },
        {
          "template_version": "hierarchy_v1",
          "module_code": "HIERARCHY",
          "source_schema_name": "public",
          "source_table_name": "hierarchy_position",
          "target_table_name": "hierarchy_position",
          "clone_order": 210,
          "clone_enabled": true,
          "seed_mode": "none",
          "seed_filter": {},
          "notes": {"kind": "tenant_owned_table", "slice": "HIERARCHY"}
        },
        {
          "template_version": "hierarchy_v1",
          "module_code": "HIERARCHY",
          "source_schema_name": "public",
          "source_table_name": "hierarchy_position_occupancy",
          "target_table_name": "hierarchy_position_occupancy",
          "clone_order": 220,
          "clone_enabled": true,
          "seed_mode": "none",
          "seed_filter": {},
          "notes": {"kind": "tenant_owned_table", "slice": "HIERARCHY"}
        },
        {
          "template_version": "hierarchy_v1",
          "module_code": "HIERARCHY",
          "source_schema_name": "public",
          "source_table_name": "hierarchy_position_occupancy_history",
          "target_table_name": "hierarchy_position_occupancy_history",
          "clone_order": 230,
          "clone_enabled": true,
          "seed_mode": "none",
          "seed_filter": {},
          "notes": {"kind": "tenant_owned_table", "slice": "HIERARCHY"}
        }
      ]
      $json$::jsonb
    )
  loop
    v_result := public.platform_register_template_table(v_row);
    if coalesce((v_result->>'success')::boolean, false) is not true then
      raise exception 'HIERARCHY template-table replay alignment failed for %: %', v_row->>'source_table_name', v_result;
    end if;
  end loop;
end;
$do$;