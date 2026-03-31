create or replace function public.platform_attach_fbp_claim_document(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_claim_id uuid := public.platform_try_uuid(p_params->>'claim_id');
  v_document_id uuid := public.platform_try_uuid(p_params->>'document_id');
  v_binding_id uuid;
  v_claim_status text;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_claim_id is null or v_document_id is null then return public.platform_json_response(false,'CLAIM_DOCUMENT_TARGET_REQUIRED','claim_id and document_id are required.', '{}'::jsonb); end if;

  execute format('select claim_status from %I.wcm_fbp_claim where claim_id = $1', v_schema_name) into v_claim_status using v_claim_id;
  if v_claim_status is null then return public.platform_json_response(false,'CLAIM_NOT_FOUND','FBP claim not found.', '{}'::jsonb); end if;

  if not exists (
    select 1
    from public.platform_document_record pdr
    where pdr.document_id = v_document_id
      and pdr.tenant_id = public.platform_try_uuid(v_context->'details'->>'tenant_id')
      and pdr.document_status = 'active'
  ) then
    return public.platform_json_response(false,'DOCUMENT_NOT_AVAILABLE','The supplied document is not active for the current tenant.',jsonb_build_object('document_id', v_document_id));
  end if;

  execute format('insert into %I.wcm_fbp_claim_document_binding (claim_id, document_id, binding_status, bound_by_actor_user_id, binding_metadata) values ($1,$2,''ACTIVE'',$3,''{}''::jsonb) on conflict (claim_id, document_id) do update set binding_status = ''ACTIVE'', bound_by_actor_user_id = excluded.bound_by_actor_user_id, updated_at = timezone(''utc'', now()) returning claim_document_binding_id', v_schema_name)
    into v_binding_id using v_claim_id, v_document_id, v_actor_user_id;

  if v_claim_status = 'PENDING_UPLOAD' then
    execute format('update %I.wcm_fbp_claim set claim_status = ''UNDER_REVIEW'', updated_at = timezone(''utc'', now()) where claim_id = $1', v_schema_name)
      using v_claim_id;
  end if;

  perform public.platform_fbp_append_audit(v_schema_name,'FBP_CLAIM_DOCUMENT_ATTACHED','FBP',jsonb_build_object('claim_id', v_claim_id,'document_id', v_document_id,'binding_id', v_binding_id),null,null,null,null,v_claim_id,null,v_actor_user_id);
  return public.platform_json_response(true,'OK','FBP claim document attached.',jsonb_build_object('claim_document_binding_id', v_binding_id,'claim_id', v_claim_id,'document_id', v_document_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_attach_fbp_claim_document.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;
create or replace function public.platform_review_fbp_claim(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_claim_id uuid := public.platform_try_uuid(p_params->>'claim_id');
  v_action text := upper(coalesce(nullif(btrim(p_params->>'action'), ''), ''));
  v_approved_amount numeric := public.platform_fbp_try_numeric(p_params->>'approved_amount');
  v_comments text := nullif(btrim(coalesce(p_params->>'review_comments', '')), '');
  v_claim_status text;
  v_claimed_amount numeric;
  v_declaration_item_id uuid;
  v_requires_bill boolean;
  v_has_document boolean := false;
  v_declaration_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_claim_id is null then return public.platform_json_response(false,'CLAIM_ID_REQUIRED','claim_id is required.', '{}'::jsonb); end if;
  if v_action not in ('APPROVE', 'REJECT') then return public.platform_json_response(false,'INVALID_ACTION','action must be APPROVE or REJECT.', '{}'::jsonb); end if;

  execute format(
    'select c.claim_status, c.claimed_amount, c.declaration_item_id, coalesce((b.reimbursement_rules->>''requires_bill'')::boolean, false), di.declaration_id
       from %I.wcm_fbp_claim c
       join %I.wcm_fbp_declaration_item di on di.declaration_item_id = c.declaration_item_id
       join %I.wcm_fbp_benefit b on b.benefit_id = di.benefit_id
      where c.claim_id = $1
      for update',
    v_schema_name, v_schema_name, v_schema_name
  ) into v_claim_status, v_claimed_amount, v_declaration_item_id, v_requires_bill, v_declaration_id using v_claim_id;

  if v_claim_status is null then return public.platform_json_response(false,'CLAIM_NOT_FOUND','FBP claim not found.', '{}'::jsonb); end if;
  if v_claim_status not in ('UNDER_REVIEW', 'PENDING_UPLOAD') then return public.platform_json_response(false,'CLAIM_REVIEW_STATE_INVALID','Claim is not in a reviewable state.',jsonb_build_object('claim_status', v_claim_status)); end if;
  if v_action = 'APPROVE' then
    v_approved_amount := coalesce(v_approved_amount, v_claimed_amount);
    if v_approved_amount <= 0 then return public.platform_json_response(false,'APPROVED_AMOUNT_INVALID','approved_amount must be greater than zero for APPROVE.',jsonb_build_object('claimed_amount', v_claimed_amount,'approved_amount', v_approved_amount)); end if;
    if v_approved_amount > v_claimed_amount then return public.platform_json_response(false,'APPROVED_AMOUNT_INVALID','approved_amount cannot exceed claimed_amount.',jsonb_build_object('claimed_amount', v_claimed_amount,'approved_amount', v_approved_amount)); end if;
  end if;

  if v_action = 'APPROVE' and v_requires_bill then
    execute format(
      'select exists(
         select 1
           from %I.wcm_fbp_claim_document_binding
          where claim_id = $1
            and binding_status = ''ACTIVE''
       )',
      v_schema_name
    ) into v_has_document using v_claim_id;

    if not v_has_document then
      return public.platform_json_response(false,'CLAIM_DOCUMENT_REQUIRED','A governed claim document is required before approval.',jsonb_build_object('claim_id', v_claim_id));
    end if;
  end if;

  if v_action = 'APPROVE' then
    execute format(
      'update %I.wcm_fbp_claim
          set claim_status = ''APPROVED'',
              approved_amount = $2,
              rejected_amount = greatest(0, claimed_amount - $2),
              approver_level_1_actor_user_id = $3,
              approver_level_1_at = timezone(''utc'', now()),
              approver_level_1_comments = $4,
              updated_at = timezone(''utc'', now())
        where claim_id = $1',
      v_schema_name
    ) using v_claim_id, v_approved_amount, v_actor_user_id, v_comments;

    execute format(
      'update %I.wcm_fbp_declaration_item
          set utilized_amount = utilized_amount + $2,
              pending_reimbursement_amount = greatest(0, pending_reimbursement_amount - $3),
              updated_at = timezone(''utc'', now())
        where declaration_item_id = $1',
      v_schema_name
    ) using v_declaration_item_id, v_approved_amount, v_claimed_amount;
  else
    execute format(
      'update %I.wcm_fbp_claim
          set claim_status = ''REJECTED'',
              approved_amount = 0,
              rejected_amount = claimed_amount,
              approver_level_1_actor_user_id = $2,
              approver_level_1_at = timezone(''utc'', now()),
              approver_level_1_comments = $3,
              updated_at = timezone(''utc'', now())
        where claim_id = $1',
      v_schema_name
    ) using v_claim_id, v_actor_user_id, v_comments;

    execute format(
      'update %I.wcm_fbp_declaration_item
          set pending_reimbursement_amount = greatest(0, pending_reimbursement_amount - $2),
              updated_at = timezone(''utc'', now())
        where declaration_item_id = $1',
      v_schema_name
    ) using v_declaration_item_id, v_claimed_amount;
  end if;

  perform public.platform_fbp_recalculate_item_internal(v_schema_name, v_declaration_item_id);
  perform public.platform_fbp_append_audit(v_schema_name,'FBP_CLAIM_REVIEWED','FBP',jsonb_build_object('claim_id', v_claim_id,'action', v_action,'approved_amount', case when v_action = 'APPROVE' then v_approved_amount else 0 end),null,null,null,v_declaration_id,v_claim_id,null,v_actor_user_id);
  return public.platform_json_response(true,'OK','FBP claim reviewed.',jsonb_build_object('claim_id', v_claim_id,'action', v_action));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_review_fbp_claim.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_auto_approve_fbp_claims(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_tenant_id uuid;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_processed integer := 0;
  v_has_document boolean;
  v_result jsonb;
  r_claim record;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');

  for r_claim in execute format(
    'select c.claim_id,
            c.claimed_amount,
            coalesce(public.platform_fbp_try_numeric(b.reimbursement_rules->>''auto_approve_up_to''), 0) as auto_limit,
            coalesce((b.reimbursement_rules->>''requires_bill'')::boolean, false) as requires_bill
       from %I.wcm_fbp_claim c
       join %I.wcm_fbp_declaration_item di on di.declaration_item_id = c.declaration_item_id
       join %I.wcm_fbp_benefit b on b.benefit_id = di.benefit_id
      where c.claim_status = ''UNDER_REVIEW''',
    v_schema_name, v_schema_name, v_schema_name
  ) loop
    if r_claim.auto_limit <= 0 or r_claim.claimed_amount > r_claim.auto_limit then
      continue;
    end if;

    if r_claim.requires_bill then
      execute format(
        'select exists(
           select 1
             from %I.wcm_fbp_claim_document_binding
            where claim_id = $1
              and binding_status = ''ACTIVE''
         )',
        v_schema_name
      ) into v_has_document using r_claim.claim_id;

      if not coalesce(v_has_document, false) then
        continue;
      end if;
    end if;

    v_result := public.platform_review_fbp_claim(jsonb_build_object(
      'tenant_id', v_tenant_id,
      'claim_id', r_claim.claim_id,
      'action', 'APPROVE',
      'approved_amount', r_claim.claimed_amount,
      'actor_user_id', v_actor_user_id,
      'source', 'platform_auto_approve_fbp_claims'
    ));

    if coalesce((v_result->>'success')::boolean, false) is true then
      v_processed := v_processed + 1;
    end if;
  end loop;

  return public.platform_json_response(true,'OK','FBP claim auto-approval completed.',jsonb_build_object('processed_claims', v_processed));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_auto_approve_fbp_claims.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_process_fbp_yearend_settlement(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_financial_year text := nullif(btrim(coalesce(p_params->>'financial_year', '')), '');
  v_settlement_type text := upper(coalesce(nullif(btrim(p_params->>'settlement_type'), ''), 'SPECIAL_ALLOWANCE'));
  v_process_in_payroll_period date := public.platform_fbp_try_date(p_params->>'processed_in_payroll_period');
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_processed_count integer := 0;
  v_total_unutilized numeric := 0;
  v_taxable_amount numeric;
  v_settlement_id uuid;
  r_dec record;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_financial_year is null then return public.platform_json_response(false,'FINANCIAL_YEAR_REQUIRED','financial_year is required.', '{}'::jsonb); end if;
  if v_settlement_type not in ('LAPSE', 'CARRY_FORWARD', 'CASH_OUT', 'SPECIAL_ALLOWANCE') then return public.platform_json_response(false,'SETTLEMENT_TYPE_INVALID','settlement_type is invalid.', '{}'::jsonb); end if;

  for r_dec in execute format(
    'select d.declaration_id,
            d.employee_id,
            d.total_declared_amount,
            coalesce(sum(di.utilized_amount), 0) as total_utilized
       from %I.wcm_fbp_declaration d
       join %I.wcm_fbp_declaration_item di on di.declaration_id = d.declaration_id
      where d.financial_year = $1
        and d.declaration_status in (''APPROVED'', ''LOCKED'')
        and ($2::uuid is null or d.employee_id = $2)
      group by d.declaration_id, d.employee_id, d.total_declared_amount',
    v_schema_name, v_schema_name
  ) using v_financial_year, v_employee_id loop
    if coalesce(r_dec.total_declared_amount, 0) <= coalesce(r_dec.total_utilized, 0) then continue; end if;
    v_taxable_amount := case when v_settlement_type in ('LAPSE', 'SPECIAL_ALLOWANCE') then (r_dec.total_declared_amount - r_dec.total_utilized) else 0 end;

    execute format(
      'insert into %I.wcm_fbp_yearend_settlement (
         declaration_id, employee_id, financial_year, total_declared, total_utilized, unutilized_amount, taxable_unutilized_amount,
         settlement_type, settlement_status, processed_in_payroll_period, processed_at, settlement_metadata
       )
       values ($1,$2,$3,$4,$5,$6,$7,$8,''PROCESSED'',$9,timezone(''utc'', now()),''{}''::jsonb)
       on conflict (declaration_id, settlement_type)
       do update set total_declared = excluded.total_declared, total_utilized = excluded.total_utilized, unutilized_amount = excluded.unutilized_amount,
                     taxable_unutilized_amount = excluded.taxable_unutilized_amount, processed_in_payroll_period = excluded.processed_in_payroll_period,
                     processed_at = timezone(''utc'', now()), updated_at = timezone(''utc'', now())
       returning yearend_settlement_id',
      v_schema_name
    ) into v_settlement_id using r_dec.declaration_id, r_dec.employee_id, v_financial_year, r_dec.total_declared_amount, r_dec.total_utilized, (r_dec.total_declared_amount - r_dec.total_utilized), v_taxable_amount, v_settlement_type, v_process_in_payroll_period;

    execute format(
      'update %I.wcm_fbp_declaration
          set declaration_status = ''LOCKED'', locked_at = timezone(''utc'', now()), locked_reason = $2, updated_at = timezone(''utc'', now())
        where declaration_id = $1',
      v_schema_name
    ) using r_dec.declaration_id, format('Year-end settlement: %s', v_settlement_type);

    perform public.platform_fbp_append_audit(v_schema_name,'FBP_YEAR_END_SETTLEMENT_PROCESSED','FBP',jsonb_build_object('settlement_id', v_settlement_id,'settlement_type', v_settlement_type),null,null,null,r_dec.declaration_id,null,v_settlement_id,v_actor_user_id);
    v_processed_count := v_processed_count + 1;
    v_total_unutilized := v_total_unutilized + (r_dec.total_declared_amount - r_dec.total_utilized);
  end loop;

  return public.platform_json_response(true,'OK','FBP year-end settlement processed.',jsonb_build_object('financial_year', v_financial_year,'settlement_type', v_settlement_type,'processed_declarations', v_processed_count,'total_unutilized_amount', v_total_unutilized));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_process_fbp_yearend_settlement.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
