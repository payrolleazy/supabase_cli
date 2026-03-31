create or replace function public.platform_assign_gateway_operation_role(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_operation_code text := nullif(btrim(p_params->>'operation_code'), '');
  v_role_code text := nullif(btrim(p_params->>'role_code'), '');
  v_metadata jsonb := coalesce(p_params->'metadata', '{}'::jsonb);
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Internal caller is required.', '{}'::jsonb);
  end if;

  if v_operation_code is null then
    return public.platform_json_response(false, 'OPERATION_CODE_REQUIRED', 'operation_code is required.', '{}'::jsonb);
  end if;

  if v_role_code is null then
    return public.platform_json_response(false, 'ROLE_CODE_REQUIRED', 'role_code is required.', '{}'::jsonb);
  end if;

  if jsonb_typeof(v_metadata) <> 'object' then
    return public.platform_json_response(false, 'INVALID_METADATA', 'metadata must be a JSON object.', '{}'::jsonb);
  end if;

  if not exists (
    select 1
    from public.platform_gateway_operation
    where operation_code = v_operation_code
  ) then
    return public.platform_json_response(false, 'OPERATION_NOT_FOUND', 'Gateway operation not found.', jsonb_build_object('operation_code', v_operation_code));
  end if;

  if not exists (
    select 1
    from public.platform_access_role
    where role_code = v_role_code
      and role_status = 'active'
  ) then
    return public.platform_json_response(false, 'ROLE_NOT_FOUND', 'Active role not found.', jsonb_build_object('role_code', v_role_code));
  end if;

  insert into public.platform_gateway_operation_role (
    operation_code,
    role_code,
    metadata,
    created_by
  ) values (
    v_operation_code,
    v_role_code,
    v_metadata,
    v_actor_user_id
  )
  on conflict (operation_code, role_code) do update
  set metadata = excluded.metadata,
      created_by = excluded.created_by;

  return public.platform_json_response(true, 'OK', 'Gateway operation role assigned.', jsonb_build_object(
    'operation_code', v_operation_code,
    'role_code', v_role_code
  ));
end;
$function$;

create or replace function public.platform_get_gateway_operation(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_operation_code text := nullif(btrim(p_params->>'operation_code'), '');
  v_result jsonb;
begin
  if v_operation_code is null then
    return public.platform_json_response(false, 'OPERATION_CODE_REQUIRED', 'operation_code is required.', '{}'::jsonb);
  end if;

  select to_jsonb(v)
  into v_result
  from public.platform_rm_gateway_operation_catalog v
  where v.operation_code = v_operation_code;

  if v_result is null then
    return public.platform_json_response(false, 'OPERATION_NOT_FOUND', 'Gateway operation not found.', jsonb_build_object('operation_code', v_operation_code));
  end if;

  return public.platform_json_response(true, 'OK', 'Gateway operation resolved.', v_result);
end;
$function$;

create or replace function public.platform_validate_gateway_access(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_operation_code text := nullif(btrim(p_params->>'operation_code'), '');
  v_actor_user_id uuid := public.platform_current_actor_user_id();
  v_tenant_id uuid := public.platform_current_tenant_id();
  v_operation_status text;
  v_profile_status text;
  v_membership_status text;
  v_routing_status text;
  v_client_access_allowed boolean;
  v_allowed_role_codes text[];
  v_active_role_codes text[];
begin
  if v_operation_code is null then
    return public.platform_json_response(false, 'OPERATION_CODE_REQUIRED', 'operation_code is required.', '{}'::jsonb);
  end if;

  select
    pgo.operation_status,
    coalesce(
      array_agg(pgor.role_code order by pgor.role_code)
        filter (where pgor.role_code is not null),
      '{}'::text[]
    )
  into
    v_operation_status,
    v_allowed_role_codes
  from public.platform_gateway_operation pgo
  left join public.platform_gateway_operation_role pgor
    on pgor.operation_code = pgo.operation_code
  where pgo.operation_code = v_operation_code
  group by pgo.operation_status;

  if not found then
    return public.platform_json_response(false, 'OPERATION_NOT_FOUND', 'Gateway operation not found.', jsonb_build_object('operation_code', v_operation_code));
  end if;

  if v_operation_status <> 'active' then
    return public.platform_json_response(false, 'OPERATION_DISABLED', 'Gateway operation is not active.', jsonb_build_object('operation_code', v_operation_code, 'operation_status', v_operation_status));
  end if;

  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_CONTEXT_REQUIRED', 'Actor execution context is required.', '{}'::jsonb);
  end if;

  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_CONTEXT_REQUIRED', 'Tenant execution context is required.', '{}'::jsonb);
  end if;

  select
    pap.profile_status,
    patmv.membership_status,
    patmv.routing_status,
    patmv.client_access_allowed,
    coalesce(
      array_agg(parg.role_code order by parg.role_code)
        filter (where parg.grant_status = 'active' and par.role_status = 'active'),
      '{}'::text[]
    )
  into
    v_profile_status,
    v_membership_status,
    v_routing_status,
    v_client_access_allowed,
    v_active_role_codes
  from public.platform_actor_tenant_membership_view patmv
  join public.platform_actor_profile pap
    on pap.actor_user_id = patmv.actor_user_id
  left join public.platform_actor_role_grant parg
    on parg.tenant_id = patmv.tenant_id
   and parg.actor_user_id = patmv.actor_user_id
  left join public.platform_access_role par
    on par.role_code = parg.role_code
  where patmv.actor_user_id = v_actor_user_id
    and patmv.tenant_id = v_tenant_id
  group by
    pap.profile_status,
    patmv.membership_status,
    patmv.routing_status,
    patmv.client_access_allowed;

  if not found then
    return public.platform_json_response(false, 'ACTOR_ACCESS_NOT_FOUND', 'Actor access context is not available for the current tenant.', jsonb_build_object('actor_user_id', v_actor_user_id, 'tenant_id', v_tenant_id));
  end if;

  if v_profile_status <> 'active' then
    return public.platform_json_response(false, 'ACTOR_PROFILE_INACTIVE', 'Actor profile is not active.', jsonb_build_object('profile_status', v_profile_status));
  end if;

  if v_membership_status <> 'active' or v_routing_status <> 'enabled' then
    return public.platform_json_response(false, 'ACTOR_MEMBERSHIP_NOT_ACTIVE', 'Actor membership routing is not active.', jsonb_build_object('membership_status', v_membership_status, 'routing_status', v_routing_status));
  end if;

  if coalesce(v_client_access_allowed, false) = false then
    return public.platform_json_response(false, 'TENANT_ACCESS_BLOCKED', 'Client access is blocked for the current tenant.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if coalesce(array_length(v_allowed_role_codes, 1), 0) > 0
     and not coalesce(v_active_role_codes, '{}'::text[]) && v_allowed_role_codes then
    return public.platform_json_response(false, 'INSUFFICIENT_ROLE', 'Actor does not hold a permitted active role for this operation.', jsonb_build_object('allowed_role_codes', v_allowed_role_codes, 'active_role_codes', coalesce(v_active_role_codes, '{}'::text[])));
  end if;

  return public.platform_json_response(true, 'OK', 'Gateway access validated.', jsonb_build_object(
    'actor_user_id', v_actor_user_id,
    'tenant_id', v_tenant_id,
    'allowed_role_codes', coalesce(v_allowed_role_codes, '{}'::text[]),
    'active_role_codes', coalesce(v_active_role_codes, '{}'::text[])
  ));
end;
$function$;;
