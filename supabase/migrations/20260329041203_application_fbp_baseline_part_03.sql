create or replace function public.platform_initialize_fbp_declaration(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_financial_year text := coalesce(nullif(btrim(p_params->>'financial_year'), ''), public.platform_fbp_financial_year(current_date));
  v_assignment_id uuid;
  v_declaration_id uuid;
  v_declaration_code text;
  v_item_count integer := 0;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_employee_id is null then return public.platform_json_response(false,'EMPLOYEE_ID_REQUIRED','employee_id is required.', '{}'::jsonb); end if;

  execute format('select employee_assignment_id from %I.wcm_fbp_employee_assignment where employee_id = $1 and financial_year = $2 and assignment_status = ''ACTIVE'' order by effective_start_date desc, created_at desc limit 1', v_schema_name)
    into v_assignment_id using v_employee_id, v_financial_year;
  if v_assignment_id is null then return public.platform_json_response(false,'ACTIVE_ASSIGNMENT_NOT_FOUND','No active FBP assignment found for the employee and financial year.',jsonb_build_object('employee_id', v_employee_id,'financial_year', v_financial_year)); end if;

  execute format('select declaration_id from %I.wcm_fbp_declaration where employee_assignment_id = $1 and declaration_status in (''DRAFT'',''SUBMITTED'',''HR_REVIEW'',''APPROVED'',''LOCKED'') order by created_at desc limit 1', v_schema_name)
    into v_declaration_id using v_assignment_id;
  if v_declaration_id is not null then return public.platform_json_response(false,'DECLARATION_ALREADY_EXISTS','An active FBP declaration already exists for this assignment.',jsonb_build_object('declaration_id', v_declaration_id)); end if;

  v_declaration_code := format('FBP-DEC-%s-%s', replace(v_financial_year, '-', ''), substring(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  execute format('insert into %I.wcm_fbp_declaration (employee_assignment_id, employee_id, declaration_code, financial_year, declaration_status, total_declared_amount, created_at, updated_at) values ($1,$2,$3,$4,''DRAFT'',0,timezone(''utc'', now()),timezone(''utc'', now())) returning declaration_id', v_schema_name)
    into v_declaration_id using v_assignment_id, v_employee_id, v_declaration_code, v_financial_year;

  execute format(
    'insert into %I.wcm_fbp_declaration_item (declaration_id, benefit_id, linked_component_id, declared_annual_amount, declared_monthly_amount, utilized_amount, pending_reimbursement_amount, balance_amount, item_status)
     select $1, pb.benefit_id, c.component_id, 0, 0, 0, 0, 0, ''ACTIVE''
       from %I.wcm_fbp_policy_benefit pb
       join %I.wcm_fbp_employee_assignment ea on ea.policy_id = pb.policy_id
       join %I.wcm_fbp_benefit b on b.benefit_id = pb.benefit_id
       left join %I.wcm_component c on lower(c.component_code) = lower(b.benefit_code)
      where ea.employee_assignment_id = $2
        and pb.benefit_status = ''ACTIVE''
        and b.benefit_status = ''ACTIVE''
        and public.platform_fbp_regime_matches(b.tax_regime_applicability, ea.elected_tax_regime)',
    v_schema_name, v_schema_name, v_schema_name, v_schema_name, v_schema_name
  ) using v_declaration_id, v_assignment_id;
  get diagnostics v_item_count = row_count;

  perform public.platform_fbp_append_audit(v_schema_name,'FBP_DECLARATION_INITIALIZED','FBP',jsonb_build_object('declaration_id', v_declaration_id,'items_created', v_item_count),null,null,v_assignment_id,v_declaration_id,null,null,v_actor_user_id);
  return public.platform_json_response(true,'OK','FBP declaration initialized.',jsonb_build_object('declaration_id', v_declaration_id,'declaration_code', v_declaration_code,'items_created', v_item_count));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_initialize_fbp_declaration.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_upsert_fbp_declaration_item(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_declaration_item_id uuid := public.platform_try_uuid(p_params->>'declaration_item_id');
  v_declaration_id uuid := public.platform_try_uuid(p_params->>'declaration_id');
  v_benefit_id uuid := public.platform_try_uuid(p_params->>'benefit_id');
  v_benefit_code text := nullif(lower(btrim(coalesce(p_params->>'benefit_code', ''))), '');
  v_declaration_status text;
  v_current_annual numeric;
  v_current_monthly numeric;
  v_declared_annual numeric;
  v_declared_monthly numeric;
  v_linked_component_id bigint := case when p_params ? 'linked_component_id' then (p_params->>'linked_component_id')::bigint else null end;
  v_item_metadata jsonb := case when p_params ? 'item_metadata' then coalesce(p_params->'item_metadata', '{}'::jsonb) else null end;
  v_item_status text := upper(nullif(btrim(coalesce(p_params->>'item_status', '')), ''));
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_item_metadata is not null and jsonb_typeof(v_item_metadata) <> 'object' then return public.platform_json_response(false,'ITEM_METADATA_INVALID','item_metadata must be a JSON object.', '{}'::jsonb); end if;

  if v_declaration_item_id is null then
    if v_declaration_id is null then return public.platform_json_response(false,'DECLARATION_ITEM_TARGET_REQUIRED','declaration_item_id or declaration_id is required.', '{}'::jsonb); end if;
    if v_benefit_id is null and v_benefit_code is not null then execute format('select benefit_id from %I.wcm_fbp_benefit where lower(benefit_code) = $1', v_schema_name) into v_benefit_id using v_benefit_code; end if;
    if v_benefit_id is null then return public.platform_json_response(false,'BENEFIT_ID_REQUIRED','benefit_id or benefit_code is required when declaration_item_id is not supplied.', '{}'::jsonb); end if;
    execute format('select declaration_item_id from %I.wcm_fbp_declaration_item where declaration_id = $1 and benefit_id = $2', v_schema_name)
      into v_declaration_item_id using v_declaration_id, v_benefit_id;
  end if;

  execute format('select di.declared_annual_amount, di.declared_monthly_amount, d.declaration_status from %I.wcm_fbp_declaration_item di join %I.wcm_fbp_declaration d on d.declaration_id = di.declaration_id where di.declaration_item_id = $1', v_schema_name, v_schema_name)
    into v_current_annual, v_current_monthly, v_declaration_status using v_declaration_item_id;
  if v_declaration_status is null then return public.platform_json_response(false,'DECLARATION_ITEM_NOT_FOUND','FBP declaration item not found.', '{}'::jsonb); end if;
  if v_declaration_status <> 'DRAFT' then return public.platform_json_response(false,'DECLARATION_NOT_EDITABLE','Only draft declarations can be edited.',jsonb_build_object('declaration_status', v_declaration_status)); end if;

  v_declared_annual := case when p_params ? 'declared_annual_amount' then coalesce(public.platform_fbp_try_numeric(p_params->>'declared_annual_amount'), 0) else v_current_annual end;
  v_declared_monthly := case when p_params ? 'declared_monthly_amount' then coalesce(public.platform_fbp_try_numeric(p_params->>'declared_monthly_amount'), 0) else v_current_monthly end;
  if p_params ? 'declared_annual_amount' and not (p_params ? 'declared_monthly_amount') then v_declared_monthly := round(v_declared_annual / 12.0, 2); end if;
  if p_params ? 'declared_monthly_amount' and not (p_params ? 'declared_annual_amount') then v_declared_annual := round(v_declared_monthly * 12.0, 2); end if;

  execute format('update %I.wcm_fbp_declaration_item set declared_annual_amount = $2, declared_monthly_amount = $3, linked_component_id = coalesce($4, linked_component_id), item_status = coalesce($5, item_status), item_metadata = coalesce($6, item_metadata), updated_at = timezone(''utc'', now()) where declaration_item_id = $1', v_schema_name)
    using v_declaration_item_id, v_declared_annual, v_declared_monthly, v_linked_component_id, v_item_status, v_item_metadata;

  perform public.platform_fbp_recalculate_item_internal(v_schema_name, v_declaration_item_id);
  perform public.platform_fbp_append_audit(v_schema_name,'FBP_DECLARATION_ITEM_UPSERTED','FBP',jsonb_build_object('declaration_item_id', v_declaration_item_id,'declared_annual_amount', v_declared_annual,'declared_monthly_amount', v_declared_monthly),null,null,null,v_declaration_id,null,null,v_actor_user_id);
  return public.platform_json_response(true,'OK','FBP declaration item updated.',jsonb_build_object('declaration_item_id', v_declaration_item_id,'declared_annual_amount', v_declared_annual,'declared_monthly_amount', v_declared_monthly));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_upsert_fbp_declaration_item.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_submit_fbp_declaration(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_declaration_id uuid := public.platform_try_uuid(p_params->>'declaration_id');
  v_total_declared numeric;
  v_total_allocated numeric;
  v_item_count integer;
  v_assignment_id uuid;
  v_status text;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_declaration_id is null then return public.platform_json_response(false,'DECLARATION_ID_REQUIRED','declaration_id is required.', '{}'::jsonb); end if;

  execute format('select d.employee_assignment_id, d.declaration_status, count(di.declaration_item_id)::int, coalesce(sum(di.declared_annual_amount), 0), ea.total_allocated_amount from %I.wcm_fbp_declaration d left join %I.wcm_fbp_declaration_item di on di.declaration_id = d.declaration_id join %I.wcm_fbp_employee_assignment ea on ea.employee_assignment_id = d.employee_assignment_id where d.declaration_id = $1 group by d.employee_assignment_id, d.declaration_status, ea.total_allocated_amount', v_schema_name, v_schema_name, v_schema_name)
    into v_assignment_id, v_status, v_item_count, v_total_declared, v_total_allocated using v_declaration_id;
  if v_assignment_id is null then return public.platform_json_response(false,'DECLARATION_NOT_FOUND','FBP declaration not found.', '{}'::jsonb); end if;
  if v_status <> 'DRAFT' then return public.platform_json_response(false,'DECLARATION_NOT_EDITABLE','Only draft declarations can be submitted.',jsonb_build_object('declaration_status', v_status)); end if;
  if coalesce(v_item_count, 0) = 0 then return public.platform_json_response(false,'DECLARATION_ITEMS_REQUIRED','No declaration items found for this declaration.', '{}'::jsonb); end if;
  if coalesce(v_total_declared, 0) > coalesce(v_total_allocated, 0) then return public.platform_json_response(false,'DECLARATION_EXCEEDS_ALLOCATION','Total declaration exceeds allocated amount.',jsonb_build_object('declared_amount', v_total_declared,'allocated_amount', v_total_allocated)); end if;

  execute format('update %I.wcm_fbp_declaration set declaration_status = ''SUBMITTED'', total_declared_amount = $2, submitted_at = timezone(''utc'', now()), submitted_by_actor_user_id = $3, updated_at = timezone(''utc'', now()) where declaration_id = $1', v_schema_name)
    using v_declaration_id, v_total_declared, v_actor_user_id;

  perform public.platform_fbp_append_audit(v_schema_name,'FBP_DECLARATION_SUBMITTED','FBP',jsonb_build_object('declaration_id', v_declaration_id,'total_declared_amount', v_total_declared,'item_count', v_item_count),null,null,v_assignment_id,v_declaration_id,null,null,v_actor_user_id);
  return public.platform_json_response(true,'OK','FBP declaration submitted.',jsonb_build_object('declaration_id', v_declaration_id,'total_declared_amount', v_total_declared,'item_count', v_item_count));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_submit_fbp_declaration.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;
create or replace function public.platform_review_fbp_declaration(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_declaration_id uuid := public.platform_try_uuid(p_params->>'declaration_id');
  v_action text := upper(coalesce(nullif(btrim(p_params->>'action'), ''), ''));
  v_comments text := nullif(btrim(coalesce(p_params->>'review_comments', '')), '');
  v_current_status text;
  v_assignment_id uuid;
  v_synced_count integer := 0;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_declaration_id is null then return public.platform_json_response(false,'DECLARATION_ID_REQUIRED','declaration_id is required.', '{}'::jsonb); end if;
  if v_action not in ('APPROVE', 'REJECT') then return public.platform_json_response(false,'INVALID_ACTION','action must be APPROVE or REJECT.', '{}'::jsonb); end if;

  execute format('select declaration_status, employee_assignment_id from %I.wcm_fbp_declaration where declaration_id = $1 for update', v_schema_name)
    into v_current_status, v_assignment_id using v_declaration_id;
  if v_current_status is null then return public.platform_json_response(false,'DECLARATION_NOT_FOUND','FBP declaration not found.', '{}'::jsonb); end if;
  if v_current_status not in ('SUBMITTED', 'HR_REVIEW') then return public.platform_json_response(false,'DECLARATION_REVIEW_STATE_INVALID','FBP declaration is not in a reviewable state.',jsonb_build_object('declaration_status', v_current_status)); end if;

  execute format('update %I.wcm_fbp_declaration set declaration_status = $2, reviewed_at = timezone(''utc'', now()), reviewed_by_actor_user_id = $3, review_comments = $4, updated_at = timezone(''utc'', now()) where declaration_id = $1', v_schema_name)
    using v_declaration_id, case when v_action = 'APPROVE' then 'APPROVED' else 'REJECTED' end, v_actor_user_id, v_comments;

  if v_action = 'APPROVE' then
    v_synced_count := public.platform_fbp_sync_to_payroll_internal(v_schema_name, v_declaration_id, v_actor_user_id);
  end if;

  perform public.platform_fbp_append_audit(v_schema_name,'FBP_DECLARATION_REVIEWED','FBP',jsonb_build_object('declaration_id', v_declaration_id,'action', v_action,'synced_components', v_synced_count),null,null,v_assignment_id,v_declaration_id,null,null,v_actor_user_id);
  return public.platform_json_response(true,'OK','FBP declaration reviewed.',jsonb_build_object('declaration_id', v_declaration_id,'action', v_action,'synced_components', v_synced_count));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_review_fbp_declaration.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_validate_fbp_claim_limits(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_declaration_item_id uuid := public.platform_try_uuid(p_params->>'declaration_item_id');
  v_claimed_amount numeric := coalesce(public.platform_fbp_try_numeric(p_params->>'claimed_amount'), 0);
  v_claim_date date := coalesce(public.platform_fbp_try_date(p_params->>'claim_date'), current_date);
  v_balance_amount numeric;
  v_monthly_limit numeric;
  v_monthly_used numeric;
  v_is_valid boolean;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_declaration_item_id is null then return public.platform_json_response(false,'DECLARATION_ITEM_ID_REQUIRED','declaration_item_id is required.', '{}'::jsonb); end if;
  if v_claimed_amount <= 0 then return public.platform_json_response(false,'CLAIMED_AMOUNT_INVALID','claimed_amount must be greater than zero.', '{}'::jsonb); end if;

  execute format(
    'with item_limit as (
       select di.balance_amount, public.platform_fbp_try_numeric(b.limit_config->''per_month''->>''max_amount'') as monthly_limit
         from %I.wcm_fbp_declaration_item di
         join %I.wcm_fbp_benefit b on b.benefit_id = di.benefit_id
        where di.declaration_item_id = $1
     ), monthly_usage as (
       select coalesce(sum(c.claimed_amount), 0) as used_this_month
         from %I.wcm_fbp_claim c
        where c.declaration_item_id = $1
          and date_trunc(''month'', c.expense_date) = date_trunc(''month'', $2)
          and c.claim_status not in (''REJECTED'', ''CANCELLED'')
     )
     select i.balance_amount, i.monthly_limit, u.used_this_month
       from item_limit i, monthly_usage u',
    v_schema_name, v_schema_name, v_schema_name
  ) into v_balance_amount, v_monthly_limit, v_monthly_used using v_declaration_item_id, v_claim_date;

  if v_balance_amount is null then return public.platform_json_response(false,'DECLARATION_ITEM_NOT_FOUND','FBP declaration item not found for claim validation.', '{}'::jsonb); end if;
  v_is_valid := (v_claimed_amount <= v_balance_amount) and (v_monthly_limit is null or (coalesce(v_monthly_used, 0) + v_claimed_amount) <= v_monthly_limit);
  if not v_is_valid then
    return public.platform_json_response(false,'CLAIM_LIMIT_VIOLATION','The claim exceeds monthly or remaining balance limits.',jsonb_build_object('balance_available', v_balance_amount,'monthly_limit', v_monthly_limit,'monthly_used', v_monthly_used,'claimed_amount', v_claimed_amount));
  end if;

  return public.platform_json_response(true,'OK','FBP claim limits validated.',jsonb_build_object('balance_available', v_balance_amount,'monthly_limit', v_monthly_limit,'monthly_used', v_monthly_used,'claimed_amount', v_claimed_amount));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_validate_fbp_claim_limits.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_submit_fbp_claim(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_declaration_item_id uuid := public.platform_try_uuid(p_params->>'declaration_item_id');
  v_expense_date date := coalesce(public.platform_fbp_try_date(p_params->>'expense_date'), current_date);
  v_claimed_amount numeric := coalesce(public.platform_fbp_try_numeric(p_params->>'claimed_amount'), 0);
  v_expense_description text := nullif(btrim(coalesce(p_params->>'expense_description', '')), '');
  v_merchant_name text := nullif(btrim(coalesce(p_params->>'merchant_name', '')), '');
  v_claim_metadata jsonb := coalesce(p_params->'claim_metadata', '{}'::jsonb);
  v_declaration_status text;
  v_financial_year text;
  v_requires_bill boolean;
  v_claim_id uuid;
  v_claim_code text;
  v_validation jsonb;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if jsonb_typeof(v_claim_metadata) <> 'object' then return public.platform_json_response(false,'CLAIM_METADATA_INVALID','claim_metadata must be a JSON object.', '{}'::jsonb); end if;
  if v_employee_id is null or v_declaration_item_id is null then return public.platform_json_response(false,'CLAIM_TARGET_REQUIRED','employee_id and declaration_item_id are required.', '{}'::jsonb); end if;
  if v_expense_description is null then return public.platform_json_response(false,'EXPENSE_DESCRIPTION_REQUIRED','expense_description is required.', '{}'::jsonb); end if;

  v_validation := public.platform_validate_fbp_claim_limits(jsonb_build_object('tenant_id', public.platform_try_uuid(v_context->'details'->>'tenant_id'),'declaration_item_id', v_declaration_item_id,'claimed_amount', v_claimed_amount,'claim_date', v_expense_date,'source', 'platform_submit_fbp_claim'));
  if coalesce((v_validation->>'success')::boolean, false) is not true then return v_validation; end if;

  execute format(
    'select d.declaration_status, d.financial_year, coalesce((b.reimbursement_rules->>''requires_bill'')::boolean, false)
       from %I.wcm_fbp_declaration_item di
       join %I.wcm_fbp_declaration d on d.declaration_id = di.declaration_id
       join %I.wcm_fbp_benefit b on b.benefit_id = di.benefit_id
      where di.declaration_item_id = $1 and d.employee_id = $2',
    v_schema_name, v_schema_name, v_schema_name
  ) into v_declaration_status, v_financial_year, v_requires_bill using v_declaration_item_id, v_employee_id;
  if v_declaration_status is null then return public.platform_json_response(false,'DECLARATION_ITEM_NOT_FOUND','FBP declaration item not found for employee.', '{}'::jsonb); end if;
  if v_declaration_status not in ('APPROVED', 'LOCKED') then return public.platform_json_response(false,'DECLARATION_NOT_APPROVED','Claims can only be submitted against approved or locked declarations.',jsonb_build_object('declaration_status', v_declaration_status)); end if;

  v_claim_code := format('FBP-CLM-%s-%s', replace(v_financial_year, '-', ''), substring(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  execute format('insert into %I.wcm_fbp_claim (declaration_item_id, employee_id, claim_code, financial_year, expense_date, expense_description, merchant_name, claimed_amount, approved_amount, rejected_amount, claim_status, claim_metadata) values ($1,$2,$3,$4,$5,$6,$7,$8,0,0,$9,$10) returning claim_id', v_schema_name)
    into v_claim_id using v_declaration_item_id, v_employee_id, v_claim_code, v_financial_year, v_expense_date, v_expense_description, v_merchant_name, v_claimed_amount, case when v_requires_bill then 'PENDING_UPLOAD' else 'UNDER_REVIEW' end, v_claim_metadata;

  execute format('update %I.wcm_fbp_declaration_item set pending_reimbursement_amount = pending_reimbursement_amount + $2, updated_at = timezone(''utc'', now()) where declaration_item_id = $1', v_schema_name)
    using v_declaration_item_id, v_claimed_amount;
  perform public.platform_fbp_recalculate_item_internal(v_schema_name, v_declaration_item_id);
  perform public.platform_fbp_append_audit(v_schema_name,'FBP_CLAIM_SUBMITTED','FBP',jsonb_build_object('claim_id', v_claim_id,'claimed_amount', v_claimed_amount,'requires_bill', v_requires_bill),null,null,null,null,v_claim_id,null,v_actor_user_id);
  return public.platform_json_response(true,'OK','FBP claim submitted.',jsonb_build_object('claim_id', v_claim_id,'claim_code', v_claim_code,'claim_status', case when v_requires_bill then 'PENDING_UPLOAD' else 'UNDER_REVIEW' end));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_submit_fbp_claim.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
