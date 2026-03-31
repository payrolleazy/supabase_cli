create or replace function public.platform_register_actor_tenant_membership(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_actor_user_id uuid := public.platform_try_uuid(p_params->>'actor_user_id');
  v_membership_status text := lower(coalesce(nullif(p_params->>'membership_status', ''), 'active'));
  v_routing_status text := lower(coalesce(nullif(p_params->>'routing_status', ''), case when v_membership_status = 'active' then 'enabled' else 'blocked' end));
  v_has_default_flag boolean := p_params ? 'is_default_tenant';
  v_requested_default boolean := case when v_has_default_flag then (p_params->>'is_default_tenant')::boolean else false end;
  v_make_default boolean := false;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(false, 'INTERNAL_CALLER_REQUIRED', 'Internal caller is required.', '{}'::jsonb);
  end if;

  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_USER_ID_REQUIRED', 'actor_user_id is required.', '{}'::jsonb);
  end if;

  if v_membership_status not in ('active', 'invited', 'disabled', 'revoked') then
    return public.platform_json_response(false, 'INVALID_MEMBERSHIP_STATUS', 'membership_status is invalid.', jsonb_build_object('membership_status', v_membership_status));
  end if;

  if v_routing_status not in ('enabled', 'blocked') then
    return public.platform_json_response(false, 'INVALID_ROUTING_STATUS', 'routing_status is invalid.', jsonb_build_object('routing_status', v_routing_status));
  end if;

  if not exists (
    select 1
    from public.platform_tenant pt
    where pt.tenant_id = v_tenant_id
  ) then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_requested_default then
    v_make_default := true;
  elsif not v_has_default_flag
    and v_membership_status = 'active'
    and v_routing_status = 'enabled'
    and not exists (
      select 1
      from public.platform_actor_tenant_membership patm
      where patm.actor_user_id = v_actor_user_id
        and patm.membership_status = 'active'
        and patm.routing_status = 'enabled'
        and patm.is_default_tenant = true
    ) then
    v_make_default := true;
  end if;

  if v_make_default then
    update public.platform_actor_tenant_membership
    set is_default_tenant = false
    where actor_user_id = v_actor_user_id
      and is_default_tenant = true;
  end if;

  insert into public.platform_actor_tenant_membership (
    tenant_id,
    actor_user_id,
    membership_status,
    is_default_tenant,
    routing_status,
    linked_at,
    linked_by,
    disabled_at,
    metadata
  )
  values (
    v_tenant_id,
    v_actor_user_id,
    v_membership_status,
    v_make_default,
    v_routing_status,
    now(),
    public.platform_resolve_actor(),
    case
      when v_membership_status in ('disabled', 'revoked') or v_routing_status = 'blocked' then now()
      else null
    end,
    coalesce(p_params->'metadata', '{}'::jsonb)
  )
  on conflict (tenant_id, actor_user_id) do update
  set membership_status = excluded.membership_status,
      is_default_tenant = excluded.is_default_tenant,
      routing_status = excluded.routing_status,
      linked_at = excluded.linked_at,
      linked_by = excluded.linked_by,
      disabled_at = excluded.disabled_at,
      metadata = excluded.metadata,
      updated_at = now();

  return public.platform_json_response(
    true,
    'OK',
    'Actor tenant membership registered.',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'actor_user_id', v_actor_user_id,
      'membership_status', v_membership_status,
      'routing_status', v_routing_status,
      'is_default_tenant', v_make_default
    )
  );
exception
  when others then
    return public.platform_json_response(
      false,
      'UNEXPECTED_ERROR',
      'Unexpected error in platform_register_actor_tenant_membership.',
      jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
    );
end;
$function$;;
