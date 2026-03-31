create or replace function public.platform_sync_tenant_access_from_commercial(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_resolve_tenant_id(p_params);
  v_overdue_since date;
  v_background_stop_from timestamptz;
  v_dormant_started_at timestamptz;
  v_new_access_state text;
  v_new_billing_state text;
  v_reason_details jsonb;
  v_access_row public.platform_tenant_access_state%rowtype;
  v_actor uuid := auth.uid();
  v_now timestamptz := timezone('utc', now());
begin
  if v_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id or tenant_code is required.', '{}'::jsonb);
  end if;

  update public.platform_invoice
  set invoice_status = 'overdue'
  where tenant_id = v_tenant_id
    and balance_amount > 0
    and due_date < current_date
    and invoice_status in ('issued', 'partially_paid');

  select min(due_date)
  into v_overdue_since
  from public.platform_invoice
  where tenant_id = v_tenant_id
    and balance_amount > 0
    and due_date < current_date
    and invoice_status in ('overdue', 'issued', 'partially_paid');

  select *
  into v_access_row
  from public.platform_tenant_access_state
  where tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'TENANT_NOT_FOUND', 'Tenant access state not found.', jsonb_build_object('tenant_id', v_tenant_id));
  end if;

  if v_access_row.access_state in ('disabled', 'terminated') then
    return public.platform_json_response(true, 'OK', 'Commercial sync skipped because tenant access state is terminal.', jsonb_build_object('tenant_id', v_tenant_id, 'access_state', v_access_row.access_state));
  end if;

  if v_overdue_since is null then
    update public.platform_tenant_commercial_account
    set
      commercial_status = 'clear',
      dues_state = 'clear',
      overdue_since = null,
      dormant_access_from = null,
      background_stop_from = null,
      last_state_synced_at = v_now
    where tenant_id = v_tenant_id;

    if v_access_row.access_state in ('dormant_access_blocked', 'dormant_background_blocked') then
      update public.platform_tenant_access_state
      set
        access_state = 'active',
        reason_code = null,
        reason_details = '{}'::jsonb,
        billing_state = 'current',
        dormant_started_at = null,
        background_stop_at = null,
        restored_at = v_now,
        updated_by = v_actor
      where tenant_id = v_tenant_id;

      perform public.platform_append_status_history(v_tenant_id, 'access', v_access_row.access_state, 'active', 'COMMERCIAL_DUES_CLEARED', '{}'::jsonb, v_actor, 'platform_sync_tenant_access_from_commercial');
      if v_access_row.billing_state is distinct from 'current' then
        perform public.platform_append_status_history(v_tenant_id, 'billing', v_access_row.billing_state, 'current', 'COMMERCIAL_DUES_CLEARED', '{}'::jsonb, v_actor, 'platform_sync_tenant_access_from_commercial');
      end if;
    end if;

    return public.platform_json_response(true, 'OK', 'Commercial state synced and tenant is clear.', jsonb_build_object('tenant_id', v_tenant_id, 'access_state', 'active', 'billing_state', 'current'));
  end if;

  v_background_stop_from := timezone('utc', v_overdue_since::timestamp) + interval '60 days';
  v_dormant_started_at := coalesce(v_access_row.dormant_started_at, v_now);
  v_new_access_state := case
    when v_now >= v_background_stop_from then 'dormant_background_blocked'
    else 'dormant_access_blocked'
  end;
  v_new_billing_state := case
    when v_new_access_state = 'dormant_background_blocked' then 'suspended'
    else 'overdue'
  end;
  v_reason_details := jsonb_build_object(
    'overdue_since', v_overdue_since,
    'background_stop_from', v_background_stop_from
  );

  update public.platform_tenant_commercial_account
  set
    commercial_status = v_new_access_state,
    dues_state = 'overdue',
    overdue_since = v_overdue_since,
    dormant_access_from = coalesce(dormant_access_from, v_dormant_started_at),
    background_stop_from = v_background_stop_from,
    last_state_synced_at = v_now
  where tenant_id = v_tenant_id;

  update public.platform_tenant_access_state
  set
    access_state = v_new_access_state,
    reason_code = 'COMMERCIAL_DUES_OVERDUE',
    reason_details = v_reason_details,
    billing_state = v_new_billing_state,
    dormant_started_at = v_dormant_started_at,
    background_stop_at = v_background_stop_from,
    restored_at = null,
    updated_by = v_actor
  where tenant_id = v_tenant_id;

  if v_access_row.access_state is distinct from v_new_access_state then
    perform public.platform_append_status_history(v_tenant_id, 'access', v_access_row.access_state, v_new_access_state, 'COMMERCIAL_DUES_OVERDUE', v_reason_details, v_actor, 'platform_sync_tenant_access_from_commercial');
  end if;

  if v_access_row.billing_state is distinct from v_new_billing_state then
    perform public.platform_append_status_history(v_tenant_id, 'billing', v_access_row.billing_state, v_new_billing_state, 'COMMERCIAL_DUES_OVERDUE', v_reason_details, v_actor, 'platform_sync_tenant_access_from_commercial');
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'Commercial state synced and tenant access updated.',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'overdue_since', v_overdue_since,
      'access_state', v_new_access_state,
      'billing_state', v_new_billing_state,
      'background_stop_from', v_background_stop_from
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_sync_tenant_access_from_commercial.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$;;
