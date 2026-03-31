create or replace function public.platform_execute_gateway_read(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_operation_code text := nullif(btrim(p_params->>'operation_code'), '');
  v_request_id uuid := coalesce(public.platform_try_uuid(p_params->>'request_id'), gen_random_uuid());
  v_actor_user_id uuid := public.platform_current_actor_user_id();
  v_tenant_id uuid := public.platform_current_tenant_id();
  v_operation public.platform_gateway_operation%rowtype;
  v_payload jsonb := coalesce(p_params->'payload', '{}'::jsonb);
  v_select_columns text[];
  v_filter_columns text[];
  v_sort_columns text[];
  v_tenant_column text := null;
  v_actor_column text := null;
  v_limit integer := 100;
  v_offset integer := 0;
  v_where_clauses text[] := '{}'::text[];
  v_order_clause text := '';
  v_select_clause text;
  v_count_sql text;
  v_query_sql text;
  v_total_records bigint := 0;
  v_data jsonb := '[]'::jsonb;
  v_filter_key text;
  v_filter_value jsonb;
  v_order_item jsonb;
  v_order_column text;
  v_order_direction text;
begin
  if v_operation_code is null then
    return public.platform_json_response(false, 'OPERATION_CODE_REQUIRED', 'operation_code is required.', '{}'::jsonb);
  end if;

  select *
  into v_operation
  from public.platform_gateway_operation
  where operation_code = v_operation_code
    and operation_mode = 'read'
    and operation_status = 'active';

  if not found then
    return public.platform_json_response(false, 'READ_OPERATION_NOT_FOUND', 'Active read operation not found.', jsonb_build_object('operation_code', v_operation_code));
  end if;

  select coalesce(array_agg(value), '{}'::text[])
  into v_select_columns
  from jsonb_array_elements_text(coalesce(v_operation.dispatch_config->'select_columns', '[]'::jsonb));

  select coalesce(array_agg(value), '{}'::text[])
  into v_filter_columns
  from jsonb_array_elements_text(coalesce(v_operation.dispatch_config->'filter_columns', '[]'::jsonb));

  select coalesce(array_agg(value), '{}'::text[])
  into v_sort_columns
  from jsonb_array_elements_text(coalesce(v_operation.dispatch_config->'sort_columns', '[]'::jsonb));

  v_tenant_column := nullif(v_operation.dispatch_config->>'tenant_column', '');
  v_actor_column := nullif(v_operation.dispatch_config->>'actor_column', '');

  if coalesce(array_length(v_select_columns, 1), 0) = 0 then
    return public.platform_json_response(false, 'SELECT_COLUMNS_REQUIRED', 'Read operation is missing select_columns.', jsonb_build_object('operation_code', v_operation_code));
  end if;

  if nullif(v_payload->>'limit', '') is not null then
    begin
      v_limit := greatest((v_payload->>'limit')::integer, 1);
    exception
      when others then
        return public.platform_json_response(false, 'INVALID_LIMIT', 'limit must be an integer.', '{}'::jsonb);
    end;
  elsif v_operation.max_limit_per_request is not null then
    v_limit := v_operation.max_limit_per_request;
  end if;

  if v_operation.max_limit_per_request is not null then
    v_limit := least(v_limit, v_operation.max_limit_per_request);
  end if;

  if nullif(v_payload->>'offset', '') is not null then
    begin
      v_offset := greatest((v_payload->>'offset')::integer, 0);
    exception
      when others then
        return public.platform_json_response(false, 'INVALID_OFFSET', 'offset must be an integer.', '{}'::jsonb);
    end;
  end if;

  if v_tenant_column is not null then
    v_where_clauses := array_append(v_where_clauses, format('src.%I = %L::uuid', v_tenant_column, v_tenant_id));
  end if;

  if v_actor_column is not null then
    v_where_clauses := array_append(v_where_clauses, format('src.%I = %L::uuid', v_actor_column, v_actor_user_id));
  end if;

  if jsonb_typeof(v_payload->'filters') = 'object' then
    for v_filter_key, v_filter_value in
      select key, value
      from jsonb_each(v_payload->'filters')
    loop
      if not (v_filter_key = any(v_filter_columns)) then
        return public.platform_json_response(false, 'FILTER_NOT_ALLOWED', 'Filter column is not allowed for this operation.', jsonb_build_object('filter_key', v_filter_key));
      end if;

      v_where_clauses := array_append(
        v_where_clauses,
        format('src.%I::text = %L', v_filter_key, v_filter_value #>> '{}')
      );
    end loop;
  end if;

  if jsonb_typeof(v_payload->'order_by') = 'array' then
    for v_order_item in
      select value
      from jsonb_array_elements(v_payload->'order_by')
    loop
      v_order_column := nullif(btrim(v_order_item->>'column'), '');
      v_order_direction := lower(coalesce(nullif(v_order_item->>'direction', ''), 'asc'));

      if v_order_column is null then
        return public.platform_json_response(false, 'ORDER_COLUMN_REQUIRED', 'order_by entries require column.', '{}'::jsonb);
      end if;

      if not (v_order_column = any(v_sort_columns)) then
        return public.platform_json_response(false, 'ORDER_COLUMN_NOT_ALLOWED', 'Sort column is not allowed for this operation.', jsonb_build_object('column', v_order_column));
      end if;

      if v_order_direction not in ('asc', 'desc') then
        return public.platform_json_response(false, 'ORDER_DIRECTION_INVALID', 'Sort direction must be asc or desc.', jsonb_build_object('direction', v_order_direction));
      end if;

      v_order_clause := v_order_clause || case when v_order_clause = '' then ' order by ' else ', ' end
        || format('src.%I %s', v_order_column, upper(v_order_direction));
    end loop;
  end if;

  select string_agg(format('src.%I', c), ', ')
  into v_select_clause
  from unnest(v_select_columns) as c;

  v_count_sql := format(
    'select count(*) from public.%I as src%s',
    v_operation.binding_ref,
    case
      when coalesce(array_length(v_where_clauses, 1), 0) > 0
        then ' where ' || array_to_string(v_where_clauses, ' and ')
      else ''
    end
  );

  v_query_sql := format(
    'select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from (select %s from public.%I as src%s%s limit %s offset %s) t',
    v_select_clause,
    v_operation.binding_ref,
    case
      when coalesce(array_length(v_where_clauses, 1), 0) > 0
        then ' where ' || array_to_string(v_where_clauses, ' and ')
      else ''
    end,
    v_order_clause,
    v_limit,
    v_offset
  );

  execute v_count_sql into v_total_records;
  execute v_query_sql into v_data;

  return public.platform_json_response(true, 'OK', 'Gateway read executed.', jsonb_build_object(
    'operation_code', v_operation_code,
    'mode', 'read',
    'request_id', v_request_id,
    'actor_user_id', v_actor_user_id,
    'tenant_id', v_tenant_id,
    'total_records', coalesce(v_total_records, 0),
    'limit', v_limit,
    'offset', v_offset,
    'data', coalesce(v_data, '[]'::jsonb)
  ));
exception
  when others then
    return public.platform_json_response(false, 'READ_EXECUTION_FAILED', 'Unexpected error while executing gateway read.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_execute_gateway_mutation(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_operation_code text := nullif(btrim(p_params->>'operation_code'), '');
  v_request_id uuid := coalesce(public.platform_try_uuid(p_params->>'request_id'), gen_random_uuid());
  v_actor_user_id uuid := public.platform_current_actor_user_id();
  v_tenant_id uuid := public.platform_current_tenant_id();
  v_operation public.platform_gateway_operation%rowtype;
  v_payload jsonb := coalesce(p_params->'payload', '{}'::jsonb);
  v_final_params jsonb;
  v_result jsonb;
begin
  if v_operation_code is null then
    return public.platform_json_response(false, 'OPERATION_CODE_REQUIRED', 'operation_code is required.', '{}'::jsonb);
  end if;

  select *
  into v_operation
  from public.platform_gateway_operation
  where operation_code = v_operation_code
    and operation_mode = 'mutate'
    and operation_status = 'active';

  if not found then
    return public.platform_json_response(false, 'MUTATION_OPERATION_NOT_FOUND', 'Active mutation operation not found.', jsonb_build_object('operation_code', v_operation_code));
  end if;

  if jsonb_typeof(v_payload) <> 'object' then
    return public.platform_json_response(false, 'INVALID_PAYLOAD', 'payload must be a JSON object.', '{}'::jsonb);
  end if;

  v_final_params := coalesce(v_operation.static_params, '{}'::jsonb)
    || v_payload
    || jsonb_build_object(
      'operation_code', v_operation_code,
      'request_id', v_request_id,
      'tenant_id', v_tenant_id,
      'actor_user_id', v_actor_user_id
    );

  execute format('select public.%I($1)', v_operation.binding_ref)
  into v_result
  using v_final_params;

  if v_result is null then
    v_result := public.platform_json_response(true, 'OK', 'Mutation executed.', '{}'::jsonb);
  elsif jsonb_typeof(v_result) <> 'object' or not (v_result ? 'success') then
    v_result := public.platform_json_response(true, 'OK', 'Mutation executed.', jsonb_build_object('result', v_result));
  end if;

  return jsonb_build_object(
    'success', coalesce((v_result->>'success')::boolean, true),
    'code', coalesce(v_result->>'code', 'OK'),
    'message', coalesce(v_result->>'message', 'Gateway mutation executed.'),
    'details', coalesce(v_result->'details', '{}'::jsonb) || jsonb_build_object(
      'operation_code', v_operation_code,
      'mode', 'mutate',
      'request_id', v_request_id,
      'actor_user_id', v_actor_user_id,
      'tenant_id', v_tenant_id
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'MUTATION_EXECUTION_FAILED', 'Unexpected error while executing gateway mutation.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_execute_gateway_action(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_operation_code text := nullif(btrim(p_params->>'operation_code'), '');
  v_request_id uuid := coalesce(public.platform_try_uuid(p_params->>'request_id'), gen_random_uuid());
  v_actor_user_id uuid := public.platform_current_actor_user_id();
  v_tenant_id uuid := public.platform_current_tenant_id();
  v_operation public.platform_gateway_operation%rowtype;
  v_payload jsonb := coalesce(p_params->'payload', '{}'::jsonb);
  v_final_params jsonb;
  v_result jsonb;
begin
  if v_operation_code is null then
    return public.platform_json_response(false, 'OPERATION_CODE_REQUIRED', 'operation_code is required.', '{}'::jsonb);
  end if;

  select *
  into v_operation
  from public.platform_gateway_operation
  where operation_code = v_operation_code
    and operation_mode = 'action'
    and operation_status = 'active';

  if not found then
    return public.platform_json_response(false, 'ACTION_OPERATION_NOT_FOUND', 'Active action operation not found.', jsonb_build_object('operation_code', v_operation_code));
  end if;

  if jsonb_typeof(v_payload) <> 'object' then
    return public.platform_json_response(false, 'INVALID_PAYLOAD', 'payload must be a JSON object.', '{}'::jsonb);
  end if;

  v_final_params := coalesce(v_operation.static_params, '{}'::jsonb)
    || v_payload
    || jsonb_build_object(
      'operation_code', v_operation_code,
      'request_id', v_request_id,
      'tenant_id', v_tenant_id,
      'actor_user_id', v_actor_user_id
    );

  execute format('select public.%I($1)', v_operation.binding_ref)
  into v_result
  using v_final_params;

  if v_result is null then
    v_result := public.platform_json_response(true, 'OK', 'Action executed.', '{}'::jsonb);
  elsif jsonb_typeof(v_result) <> 'object' or not (v_result ? 'success') then
    v_result := public.platform_json_response(true, 'OK', 'Action executed.', jsonb_build_object('result', v_result));
  end if;

  return jsonb_build_object(
    'success', coalesce((v_result->>'success')::boolean, true),
    'code', coalesce(v_result->>'code', 'OK'),
    'message', coalesce(v_result->>'message', 'Gateway action executed.'),
    'details', coalesce(v_result->'details', '{}'::jsonb) || jsonb_build_object(
      'operation_code', v_operation_code,
      'mode', 'action',
      'request_id', v_request_id,
      'actor_user_id', v_actor_user_id,
      'tenant_id', v_tenant_id
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'ACTION_EXECUTION_FAILED', 'Unexpected error while executing gateway action.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
