create or replace function public.platform_get_extensible_template_descriptor(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_schema_result jsonb;
  v_columns jsonb;
begin
  v_schema_result := public.platform_get_extensible_attribute_schema(p_params || jsonb_build_object('include_inactive', false));

  if not coalesce((v_schema_result->>'success')::boolean, false) then
    return v_schema_result;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'column_code', attr->>'attribute_code',
        'label', attr->>'ui_label',
        'data_type', attr->>'data_type',
        'required', coalesce((attr->>'is_required')::boolean, false),
        'default_value', attr->'default_value'
      )
      order by coalesce((attr->>'sort_order')::integer, 100), attr->>'attribute_code'
    ),
    '[]'::jsonb
  )
  into v_columns
  from jsonb_array_elements(coalesce(v_schema_result->'details'->'attributes', '[]'::jsonb)) attr;

  return public.platform_json_response(true, 'OK', 'Extensible template descriptor resolved.', jsonb_build_object(
    'entity_code', v_schema_result->'details'->>'entity_code',
    'tenant_id', v_schema_result->'details'->>'tenant_id',
    'target_relation_schema', v_schema_result->'details'->>'target_relation_schema',
    'target_relation_name', v_schema_result->'details'->>'target_relation_name',
    'columns', v_columns
  ));
exception when others then
  return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_get_extensible_template_descriptor.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$$;;
