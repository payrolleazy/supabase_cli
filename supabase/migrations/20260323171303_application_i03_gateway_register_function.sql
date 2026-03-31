create or replace function public.platform_register_gateway_operation(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_operation_code text := nullif(btrim(p_params->>'operation_code'), '');
  v_operation_mode text := lower(coalesce(nullif(p_params->>'operation_mode', ''), ''));
  v_dispatch_kind text := lower(coalesce(nullif(p_params->>'dispatch_kind', ''), ''));
  v_operation_status text := lower(coalesce(nullif(p_params->>'operation_status', ''), 'draft'));
  v_route_policy text := lower(coalesce(nullif(p_params->>'route_policy', ''), 'tenant_required'));
  v_tenant_requirement text := lower(coalesce(nullif(p_params->>'tenant_requirement', ''), 'required'));
  v_idempotency_policy text := lower(coalesce(nullif(p_params->>'idempotency_policy', ''), 'optional'));
  v_rate_limit_policy text := lower(coalesce(nullif(p_params->>'rate_limit_policy', ''), 'default'));
  v_max_limit integer := null;
  v_binding_ref text := nullif(btrim(p_params->>'binding_ref'), '');
  v_dispatch_config jsonb := coalesce(p_params->'dispatch_config', '{}'::jsonb);
  v_static_params jsonb := coalesce(p_params->'static_params', '{}'::jsonb);
  v_request_contract jsonb := coalesce(p_params->'request_contract', '{}'::jsonb);
  v_response_contract jsonb := coalesce(p_params->'response_contract', '{}'::jsonb);
  v_group_name text := nullif(btrim(p_params->>'group_name'), '');
  v_synopsis text := nullif(btrim(p_params->>'synopsis'), '');
  v_description text := nullif(btrim(p_params->>'description'), '');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_exists boolean := false;
  v_select_columns text[] := '{}'::text[];
  v_filter_columns text[] := '{}'::text[];
  v_sort_columns text[] := '{}'::text[];
  v_tenant_column text := null;
  v_actor_column text := null;
  v_missing_columns text[] := '{}'::text[];
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Internal caller is required.', '{}'::jsonb);
  end if;

  if v_operation_code is null then
    return public.platform_json_response(false, 'OPERATION_CODE_REQUIRED', 'operation_code is required.', '{}'::jsonb);
  end if;

  if v_operation_mode not in ('read', 'mutate', 'action') then
    return public.platform_json_response(false, 'INVALID_OPERATION_MODE', 'operation_mode is invalid.', jsonb_build_object('operation_mode', v_operation_mode));
  end if;

  if v_dispatch_kind not in ('read_surface', 'mutation_adapter', 'function_action') then
    return public.platform_json_response(false, 'INVALID_DISPATCH_KIND', 'dispatch_kind is invalid.', jsonb_build_object('dispatch_kind', v_dispatch_kind));
  end if;

  if v_route_policy <> 'tenant_required' then
    return public.platform_json_response(false, 'INVALID_ROUTE_POLICY', 'route_policy is invalid for this baseline.', jsonb_build_object('route_policy', v_route_policy));
  end if;

  if v_tenant_requirement <> 'required' then
    return public.platform_json_response(false, 'INVALID_TENANT_REQUIREMENT', 'tenant_requirement is invalid for this baseline.', jsonb_build_object('tenant_requirement', v_tenant_requirement));
  end if;

  if v_idempotency_policy not in ('none', 'optional', 'required') then
    return public.platform_json_response(false, 'INVALID_IDEMPOTENCY_POLICY', 'idempotency_policy is invalid.', jsonb_build_object('idempotency_policy', v_idempotency_policy));
  end if;

  if v_rate_limit_policy <> 'default' then
    return public.platform_json_response(false, 'INVALID_RATE_LIMIT_POLICY', 'rate_limit_policy is invalid for this baseline.', jsonb_build_object('rate_limit_policy', v_rate_limit_policy));
  end if;

  if v_operation_status not in ('draft', 'active', 'disabled') then
    return public.platform_json_response(false, 'INVALID_OPERATION_STATUS', 'operation_status is invalid.', jsonb_build_object('operation_status', v_operation_status));
  end if;

  if v_binding_ref is null then
    return public.platform_json_response(false, 'BINDING_REF_REQUIRED', 'binding_ref is required.', '{}'::jsonb);
  end if;

  if jsonb_typeof(v_dispatch_config) <> 'object'
    or jsonb_typeof(v_static_params) <> 'object'
    or jsonb_typeof(v_request_contract) <> 'object'
    or jsonb_typeof(v_response_contract) <> 'object'
    or jsonb_typeof(v_metadata) <> 'object'
  then
    return public.platform_json_response(false, 'INVALID_JSON_CONFIG', 'dispatch/static/request/response/metadata must be JSON objects.', '{}'::jsonb);
  end if;

  if nullif(p_params->>'max_limit_per_request', '') is not null then
    begin
      v_max_limit := (p_params->>'max_limit_per_request')::integer;
    exception
      when others then
        return public.platform_json_response(false, 'INVALID_MAX_LIMIT', 'max_limit_per_request must be an integer.', '{}'::jsonb);
    end;
  end if;

  if v_max_limit is not null and (v_max_limit <= 0 or v_max_limit > 5000) then
    return public.platform_json_response(false, 'INVALID_MAX_LIMIT', 'max_limit_per_request must be between 1 and 5000.', jsonb_build_object('max_limit_per_request', v_max_limit));
  end if;

  if v_operation_mode = 'read' and v_dispatch_kind <> 'read_surface' then
    return public.platform_json_response(false, 'MODE_DISPATCH_MISMATCH', 'read mode requires read_surface dispatch.', '{}'::jsonb);
  elsif v_operation_mode = 'mutate' and v_dispatch_kind <> 'mutation_adapter' then
    return public.platform_json_response(false, 'MODE_DISPATCH_MISMATCH', 'mutate mode requires mutation_adapter dispatch.', '{}'::jsonb);
  elsif v_operation_mode = 'action' and v_dispatch_kind <> 'function_action' then
    return public.platform_json_response(false, 'MODE_DISPATCH_MISMATCH', 'action mode requires function_action dispatch.', '{}'::jsonb);
  end if;

  if v_dispatch_kind = 'read_surface' then
    select exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = v_binding_ref
        and c.relkind in ('v', 'm')
    ) into v_exists;

    if not v_exists then
      return public.platform_json_response(false, 'READ_SURFACE_NOT_FOUND', 'binding_ref must reference a public view or materialized view.', jsonb_build_object('binding_ref', v_binding_ref));
    end if;
    if (v_dispatch_config ? 'select_columns' and jsonb_typeof(v_dispatch_config->'select_columns') <> 'array')
      or (v_dispatch_config ? 'filter_columns' and jsonb_typeof(v_dispatch_config->'filter_columns') <> 'array')
      or (v_dispatch_config ? 'sort_columns' and jsonb_typeof(v_dispatch_config->'sort_columns') <> 'array')
    then
      return public.platform_json_response(false, 'INVALID_DISPATCH_CONFIG', 'select_columns, filter_columns, and sort_columns must be JSON arrays when present.', '{}'::jsonb);
    end if;

    select coalesce(array_agg(value), '{}'::text[])
    into v_select_columns
    from jsonb_array_elements_text(coalesce(v_dispatch_config->'select_columns', '[]'::jsonb));

    select coalesce(array_agg(value), '{}'::text[])
    into v_filter_columns
    from jsonb_array_elements_text(coalesce(v_dispatch_config->'filter_columns', '[]'::jsonb));

    select coalesce(array_agg(value), '{}'::text[])
    into v_sort_columns
    from jsonb_array_elements_text(coalesce(v_dispatch_config->'sort_columns', '[]'::jsonb));

    v_tenant_column := nullif(v_dispatch_config->>'tenant_column', '');
    v_actor_column := nullif(v_dispatch_config->>'actor_column', '');

    if coalesce(array_length(v_select_columns, 1), 0) = 0 then
      return public.platform_json_response(false, 'SELECT_COLUMNS_REQUIRED', 'read_surface operations require dispatch_config.select_columns.', '{}'::jsonb);
    end if;

    with configured_columns as (
      select distinct column_name
      from (
        select unnest(v_select_columns) as column_name
        union all
        select unnest(v_filter_columns) as column_name
        union all
        select unnest(v_sort_columns) as column_name
        union all
        select v_tenant_column where v_tenant_column is not null
        union all
        select v_actor_column where v_actor_column is not null
      ) configured
      where column_name is not null
    ), missing_columns as (
      select cc.column_name
      from configured_columns cc
      where not exists (
        select 1
        from information_schema.columns ic
        where ic.table_schema = 'public'
          and ic.table_name = v_binding_ref
          and ic.column_name = cc.column_name
      )
    )
    select coalesce(array_agg(column_name order by column_name), '{}'::text[])
    into v_missing_columns
    from missing_columns;

    if coalesce(array_length(v_missing_columns, 1), 0) > 0 then
      return public.platform_json_response(false, 'INVALID_READ_COLUMN_BINDING', 'dispatch_config references columns not present on the bound read surface.', jsonb_build_object('binding_ref', v_binding_ref, 'missing_columns', v_missing_columns));
    end if;
  else
    if v_binding_ref = any (array['platform_execute_gateway_request', 'platform_execute_gateway_read', 'platform_execute_gateway_mutation', 'platform_execute_gateway_action']) then
      return public.platform_json_response(false, 'INVALID_FUNCTION_BINDING', 'Gateway dispatch functions cannot be registered as gateway bindings.', jsonb_build_object('binding_ref', v_binding_ref));
    end if;

    select exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = v_binding_ref
        and p.pronargs = 1
        and oidvectortypes(p.proargtypes) = 'jsonb'
    ) into v_exists;

    if not v_exists then
      return public.platform_json_response(false, 'FUNCTION_BINDING_NOT_FOUND', 'binding_ref must reference a public function(jsonb).', jsonb_build_object('binding_ref', v_binding_ref));
    end if;
  end if;

  insert into public.platform_gateway_operation (
    operation_code,
    operation_mode,
    dispatch_kind,
    operation_status,
    route_policy,
    tenant_requirement,
    idempotency_policy,
    rate_limit_policy,
    max_limit_per_request,
    binding_ref,
    dispatch_config,
    static_params,
    request_contract,
    response_contract,
    group_name,
    synopsis,
    description,
    metadata,
    created_by,
    updated_by
  ) values (
    v_operation_code,
    v_operation_mode,
    v_dispatch_kind,
    v_operation_status,
    v_route_policy,
    v_tenant_requirement,
    v_idempotency_policy,
    v_rate_limit_policy,
    v_max_limit,
    v_binding_ref,
    v_dispatch_config,
    v_static_params,
    v_request_contract,
    v_response_contract,
    v_group_name,
    v_synopsis,
    v_description,
    v_metadata,
    v_actor_user_id,
    v_actor_user_id
  )
  on conflict (operation_code) do update
  set operation_mode = excluded.operation_mode,
      dispatch_kind = excluded.dispatch_kind,
      operation_status = excluded.operation_status,
      route_policy = excluded.route_policy,
      tenant_requirement = excluded.tenant_requirement,
      idempotency_policy = excluded.idempotency_policy,
      rate_limit_policy = excluded.rate_limit_policy,
      max_limit_per_request = excluded.max_limit_per_request,
      binding_ref = excluded.binding_ref,
      dispatch_config = excluded.dispatch_config,
      static_params = excluded.static_params,
      request_contract = excluded.request_contract,
      response_contract = excluded.response_contract,
      group_name = excluded.group_name,
      synopsis = excluded.synopsis,
      description = excluded.description,
      metadata = excluded.metadata,
      updated_at = timezone('utc', now()),
      updated_by = excluded.updated_by;

  return public.platform_json_response(true, 'OK', 'Gateway operation registered.', jsonb_build_object(
    'operation_code', v_operation_code,
    'operation_mode', v_operation_mode,
    'dispatch_kind', v_dispatch_kind,
    'route_policy', v_route_policy,
    'tenant_requirement', v_tenant_requirement,
    'rate_limit_policy', v_rate_limit_policy,
    'binding_ref', v_binding_ref
  ));
end;
$function$;;
