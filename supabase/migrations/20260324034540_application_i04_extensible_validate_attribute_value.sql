create or replace function public.platform_validate_extensible_attribute_value(
  p_attribute jsonb,
  p_value jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_data_type text := coalesce(nullif(btrim(p_attribute->>'data_type'), ''), 'jsonb');
  v_rules jsonb := coalesce(p_attribute->'validation_rules', '{}'::jsonb);
  v_scalar_text text;
  v_numeric numeric;
begin
  if p_value is null or p_value = 'null'::jsonb then
    return jsonb_build_object('valid', true);
  end if;

  case v_data_type
    when 'text' then
      if jsonb_typeof(p_value) <> 'string' then
        return jsonb_build_object('valid', false, 'reason', 'Expected string value.');
      end if;
      v_scalar_text := p_value #>> '{}';
      if v_rules ? 'min_length' and length(v_scalar_text) < greatest((v_rules->>'min_length')::integer, 0) then
        return jsonb_build_object('valid', false, 'reason', 'String value is shorter than min_length.');
      end if;
      if v_rules ? 'max_length' and length(v_scalar_text) > greatest((v_rules->>'max_length')::integer, 0) then
        return jsonb_build_object('valid', false, 'reason', 'String value exceeds max_length.');
      end if;
      if v_rules ? 'pattern' and v_scalar_text !~ (v_rules->>'pattern') then
        return jsonb_build_object('valid', false, 'reason', 'String value does not match required pattern.');
      end if;
    when 'integer' then
      if jsonb_typeof(p_value) <> 'number' then
        return jsonb_build_object('valid', false, 'reason', 'Expected integer number value.');
      end if;
      begin
        v_numeric := (p_value #>> '{}')::numeric;
      exception when others then
        return jsonb_build_object('valid', false, 'reason', 'Invalid numeric value.');
      end;
      if trunc(v_numeric) <> v_numeric then
        return jsonb_build_object('valid', false, 'reason', 'Expected integer number value.');
      end if;
      if v_rules ? 'min' and v_numeric < (v_rules->>'min')::numeric then
        return jsonb_build_object('valid', false, 'reason', 'Integer value is below min.');
      end if;
      if v_rules ? 'max' and v_numeric > (v_rules->>'max')::numeric then
        return jsonb_build_object('valid', false, 'reason', 'Integer value exceeds max.');
      end if;
    when 'numeric' then
      if jsonb_typeof(p_value) <> 'number' then
        return jsonb_build_object('valid', false, 'reason', 'Expected numeric value.');
      end if;
      begin
        v_numeric := (p_value #>> '{}')::numeric;
      exception when others then
        return jsonb_build_object('valid', false, 'reason', 'Invalid numeric value.');
      end;
      if v_rules ? 'min' and v_numeric < (v_rules->>'min')::numeric then
        return jsonb_build_object('valid', false, 'reason', 'Numeric value is below min.');
      end if;
      if v_rules ? 'max' and v_numeric > (v_rules->>'max')::numeric then
        return jsonb_build_object('valid', false, 'reason', 'Numeric value exceeds max.');
      end if;
    when 'boolean' then
      if jsonb_typeof(p_value) <> 'boolean' then
        return jsonb_build_object('valid', false, 'reason', 'Expected boolean value.');
      end if;
    when 'uuid' then
      if jsonb_typeof(p_value) <> 'string' then
        return jsonb_build_object('valid', false, 'reason', 'Expected UUID string value.');
      end if;
      begin
        perform (p_value #>> '{}')::uuid;
      exception when others then
        return jsonb_build_object('valid', false, 'reason', 'Invalid UUID value.');
      end;
    when 'date' then
      if jsonb_typeof(p_value) <> 'string' then
        return jsonb_build_object('valid', false, 'reason', 'Expected date string value.');
      end if;
      begin
        perform (p_value #>> '{}')::date;
      exception when others then
        return jsonb_build_object('valid', false, 'reason', 'Invalid date value.');
      end;
    when 'timestamp' then
      if jsonb_typeof(p_value) <> 'string' then
        return jsonb_build_object('valid', false, 'reason', 'Expected timestamp string value.');
      end if;
      begin
        perform (p_value #>> '{}')::timestamptz;
      exception when others then
        return jsonb_build_object('valid', false, 'reason', 'Invalid timestamp value.');
      end;
    when 'object' then
      if jsonb_typeof(p_value) <> 'object' then
        return jsonb_build_object('valid', false, 'reason', 'Expected object value.');
      end if;
    when 'array' then
      if jsonb_typeof(p_value) <> 'array' then
        return jsonb_build_object('valid', false, 'reason', 'Expected array value.');
      end if;
      if v_rules ? 'min_items' and jsonb_array_length(p_value) < greatest((v_rules->>'min_items')::integer, 0) then
        return jsonb_build_object('valid', false, 'reason', 'Array has fewer items than min_items.');
      end if;
      if v_rules ? 'max_items' and jsonb_array_length(p_value) > greatest((v_rules->>'max_items')::integer, 0) then
        return jsonb_build_object('valid', false, 'reason', 'Array has more items than max_items.');
      end if;
    when 'jsonb' then
      null;
    else
      return jsonb_build_object('valid', false, 'reason', 'Unsupported data_type.');
  end case;

  if v_rules ? 'allowed_values' and jsonb_typeof(v_rules->'allowed_values') = 'array' then
    if not exists (
      select 1
      from jsonb_array_elements(v_rules->'allowed_values') allowed(value)
      where allowed.value = p_value
    ) then
      return jsonb_build_object('valid', false, 'reason', 'Value is not in allowed_values.');
    end if;
  end if;

  return jsonb_build_object('valid', true);
exception when others then
  return jsonb_build_object('valid', false, 'reason', sqlerrm);
end;
$$;;
