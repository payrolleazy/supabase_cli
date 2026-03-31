create or replace function public.platform_fbp_benefit_catalog_rows()
returns table (
  tenant_id uuid,
  benefit_id uuid,
  benefit_code text,
  benefit_name text,
  benefit_category text,
  tax_regime_applicability text,
  benefit_status text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid, benefit_id, benefit_code, benefit_name, benefit_category, tax_regime_applicability, benefit_status, updated_at
       from %I.wcm_fbp_benefit
      order by lower(benefit_code), benefit_id',
    v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_fbp_benefit_catalog with (security_invoker = true) as select * from public.platform_fbp_benefit_catalog_rows();

create or replace function public.platform_fbp_policy_catalog_rows()
returns table (
  tenant_id uuid,
  policy_id uuid,
  policy_code text,
  policy_name text,
  policy_tax_regime text,
  total_annual_limit numeric,
  benefit_count bigint,
  policy_status text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid,
            p.policy_id,
            p.policy_code,
            p.policy_name,
            p.policy_tax_regime,
            p.total_annual_limit,
            count(pb.policy_benefit_id)::bigint as benefit_count,
            p.policy_status,
            p.updated_at
       from %I.wcm_fbp_policy p
       left join %I.wcm_fbp_policy_benefit pb on pb.policy_id = p.policy_id
      group by p.policy_id
      order by lower(p.policy_code), p.policy_id',
    v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_fbp_policy_catalog with (security_invoker = true) as select * from public.platform_fbp_policy_catalog_rows();

create or replace function public.platform_fbp_employee_dashboard_rows()
returns table (
  tenant_id uuid,
  employee_id uuid,
  employee_code text,
  employee_name text,
  financial_year text,
  employee_assignment_id uuid,
  policy_code text,
  elected_tax_regime text,
  total_allocated_amount numeric,
  total_declared_amount numeric,
  total_utilized_amount numeric,
  total_pending_reimbursement_amount numeric,
  total_balance_amount numeric,
  latest_declaration_status text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid,
            ea.employee_id,
            e.employee_code,
            trim(concat(coalesce(e.first_name, ''''), '' '', coalesce(e.last_name, ''''))),
            ea.financial_year,
            ea.employee_assignment_id,
            p.policy_code,
            ea.elected_tax_regime,
            ea.total_allocated_amount,
            coalesce(d.total_declared_amount, 0),
            coalesce(sum(di.utilized_amount), 0),
            coalesce(sum(di.pending_reimbursement_amount), 0),
            coalesce(sum(di.balance_amount), 0),
            d.declaration_status,
            greatest(ea.updated_at, coalesce(d.updated_at, ea.updated_at))
       from %I.wcm_fbp_employee_assignment ea
       join %I.wcm_employee e on e.employee_id = ea.employee_id
       join %I.wcm_fbp_policy p on p.policy_id = ea.policy_id
       left join lateral (
         select d1.declaration_id, d1.total_declared_amount, d1.declaration_status, d1.updated_at
           from %I.wcm_fbp_declaration d1
          where d1.employee_assignment_id = ea.employee_assignment_id
          order by d1.created_at desc, d1.declaration_id desc
          limit 1
       ) d on true
       left join %I.wcm_fbp_declaration_item di on di.declaration_id = d.declaration_id
      group by ea.employee_assignment_id, e.employee_code, e.first_name, e.last_name, p.policy_code, d.declaration_id, d.total_declared_amount, d.declaration_status, d.updated_at
      order by ea.financial_year desc, e.employee_code',
    v_schema_name, v_schema_name, v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_fbp_employee_dashboard with (security_invoker = true) as select * from public.platform_fbp_employee_dashboard_rows();
create or replace function public.platform_fbp_pending_approval_rows()
returns table (
  tenant_id uuid,
  queue_kind text,
  reference_id uuid,
  employee_id uuid,
  employee_code text,
  employee_name text,
  reference_code text,
  current_status text,
  amount numeric,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select * from (
       select $1::uuid as tenant_id,
              ''DECLARATION''::text as queue_kind,
              d.declaration_id as reference_id,
              d.employee_id,
              e.employee_code,
              trim(concat(coalesce(e.first_name, ''''), '' '', coalesce(e.last_name, ''''))) as employee_name,
              d.declaration_code as reference_code,
              d.declaration_status as current_status,
              d.total_declared_amount as amount,
              d.created_at,
              d.updated_at
         from %I.wcm_fbp_declaration d
         join %I.wcm_employee e on e.employee_id = d.employee_id
        where d.declaration_status in (''SUBMITTED'', ''HR_REVIEW'')
       union all
       select $1::uuid as tenant_id,
              ''CLAIM''::text as queue_kind,
              c.claim_id as reference_id,
              c.employee_id,
              e.employee_code,
              trim(concat(coalesce(e.first_name, ''''), '' '', coalesce(e.last_name, ''''))) as employee_name,
              c.claim_code as reference_code,
              c.claim_status as current_status,
              c.claimed_amount as amount,
              c.created_at,
              c.updated_at
         from %I.wcm_fbp_claim c
         join %I.wcm_employee e on e.employee_id = c.employee_id
        where c.claim_status in (''UNDER_REVIEW'', ''PENDING_UPLOAD'')
     ) q
     order by q.updated_at desc, q.created_at desc, q.reference_id',
    v_schema_name, v_schema_name, v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_fbp_pending_approvals with (security_invoker = true) as select * from public.platform_fbp_pending_approval_rows();

create or replace function public.platform_fbp_claim_queue_rows()
returns table (
  tenant_id uuid,
  claim_id uuid,
  employee_id uuid,
  employee_code text,
  claim_code text,
  claim_status text,
  claimed_amount numeric,
  approved_amount numeric,
  expense_date date,
  benefit_code text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid,
            c.claim_id,
            c.employee_id,
            e.employee_code,
            c.claim_code,
            c.claim_status,
            c.claimed_amount,
            c.approved_amount,
            c.expense_date,
            b.benefit_code,
            c.created_at,
            c.updated_at
       from %I.wcm_fbp_claim c
       join %I.wcm_employee e on e.employee_id = c.employee_id
       join %I.wcm_fbp_declaration_item di on di.declaration_item_id = c.declaration_item_id
       join %I.wcm_fbp_benefit b on b.benefit_id = di.benefit_id
      order by c.updated_at desc, c.created_at desc, c.claim_id',
    v_schema_name, v_schema_name, v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_fbp_claim_queue with (security_invoker = true) as select * from public.platform_fbp_claim_queue_rows();

create or replace function public.platform_fbp_monthly_ledger_rows()
returns table (
  tenant_id uuid,
  employee_id uuid,
  employee_code text,
  declaration_item_id uuid,
  benefit_code text,
  payroll_period date,
  monthly_deduction_amount numeric,
  reimbursed_amount numeric,
  ledger_status text,
  processed_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid,
            l.employee_id,
            e.employee_code,
            l.declaration_item_id,
            b.benefit_code,
            l.payroll_period,
            l.monthly_deduction_amount,
            l.reimbursed_amount,
            l.ledger_status,
            l.processed_at
       from %I.wcm_fbp_monthly_ledger l
       join %I.wcm_employee e on e.employee_id = l.employee_id
       join %I.wcm_fbp_declaration_item di on di.declaration_item_id = l.declaration_item_id
       join %I.wcm_fbp_benefit b on b.benefit_id = di.benefit_id
      order by l.payroll_period desc, e.employee_code, l.monthly_ledger_id',
    v_schema_name, v_schema_name, v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_fbp_monthly_ledger with (security_invoker = true) as select * from public.platform_fbp_monthly_ledger_rows();

create or replace function public.platform_fbp_yearend_settlement_status_rows()
returns table (
  tenant_id uuid,
  employee_id uuid,
  employee_code text,
  declaration_id uuid,
  financial_year text,
  settlement_type text,
  unutilized_amount numeric,
  taxable_unutilized_amount numeric,
  processed_in_payroll_period date,
  settlement_status text,
  processed_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context('{}'::jsonb);
  v_schema_name text;
  v_tenant_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_tenant_id := public.platform_try_uuid(v_context->'details'->>'tenant_id');
  return query execute format(
    'select $1::uuid,
            s.employee_id,
            e.employee_code,
            s.declaration_id,
            s.financial_year,
            s.settlement_type,
            s.unutilized_amount,
            s.taxable_unutilized_amount,
            s.processed_in_payroll_period,
            s.settlement_status,
            s.processed_at
       from %I.wcm_fbp_yearend_settlement s
       join %I.wcm_employee e on e.employee_id = s.employee_id
      order by s.financial_year desc, e.employee_code, s.yearend_settlement_id',
    v_schema_name, v_schema_name
  ) using v_tenant_id;
end;
$function$;
create or replace view public.platform_rm_fbp_yearend_settlement_status with (security_invoker = true) as select * from public.platform_fbp_yearend_settlement_status_rows();
revoke all on public.wcm_fbp_benefit from public, anon, authenticated;
revoke all on public.wcm_fbp_policy from public, anon, authenticated;
revoke all on public.wcm_fbp_policy_benefit from public, anon, authenticated;
revoke all on public.wcm_fbp_employee_assignment from public, anon, authenticated;
revoke all on public.wcm_fbp_declaration from public, anon, authenticated;
revoke all on public.wcm_fbp_declaration_item from public, anon, authenticated;
revoke all on public.wcm_fbp_claim from public, anon, authenticated;
revoke all on public.wcm_fbp_claim_document_binding from public, anon, authenticated;
revoke all on public.wcm_fbp_monthly_ledger from public, anon, authenticated;
revoke all on public.wcm_fbp_yearend_settlement from public, anon, authenticated;
revoke all on public.wcm_fbp_audit_event from public, anon, authenticated;
revoke all on public.platform_rm_fbp_benefit_catalog from public, anon, authenticated;
revoke all on public.platform_rm_fbp_policy_catalog from public, anon, authenticated;
revoke all on public.platform_rm_fbp_employee_dashboard from public, anon, authenticated;
revoke all on public.platform_rm_fbp_pending_approvals from public, anon, authenticated;
revoke all on public.platform_rm_fbp_claim_queue from public, anon, authenticated;
revoke all on public.platform_rm_fbp_monthly_ledger from public, anon, authenticated;
revoke all on public.platform_rm_fbp_yearend_settlement_status from public, anon, authenticated;

revoke all on function public.platform_fbp_module_template_version() from public, anon, authenticated;
revoke all on function public.platform_fbp_try_date(text) from public, anon, authenticated;
revoke all on function public.platform_fbp_try_numeric(text) from public, anon, authenticated;
revoke all on function public.platform_fbp_financial_year(date) from public, anon, authenticated;
revoke all on function public.platform_fbp_regime_matches(text,text) from public, anon, authenticated;
revoke all on function public.platform_fbp_append_audit(text,text,text,jsonb,uuid,uuid,uuid,uuid,uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function public.platform_fbp_resolve_context(jsonb) from public, anon, authenticated;
revoke all on function public.platform_fbp_recalculate_item_internal(text,uuid) from public, anon, authenticated;
revoke all on function public.platform_fbp_sync_to_payroll_internal(text,uuid,uuid) from public, anon, authenticated;
revoke all on function public.platform_apply_fbp_to_tenant(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_fbp_benefit(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_fbp_policy(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_fbp_policy_benefit(jsonb) from public, anon, authenticated;
revoke all on function public.platform_assign_employee_fbp_policy(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_fbp_eligible_benefits(jsonb) from public, anon, authenticated;
revoke all on function public.platform_initialize_fbp_declaration(jsonb) from public, anon, authenticated;
revoke all on function public.platform_upsert_fbp_declaration_item(jsonb) from public, anon, authenticated;
revoke all on function public.platform_submit_fbp_declaration(jsonb) from public, anon, authenticated;
revoke all on function public.platform_review_fbp_declaration(jsonb) from public, anon, authenticated;
revoke all on function public.platform_validate_fbp_claim_limits(jsonb) from public, anon, authenticated;
revoke all on function public.platform_submit_fbp_claim(jsonb) from public, anon, authenticated;
revoke all on function public.platform_attach_fbp_claim_document(jsonb) from public, anon, authenticated;
revoke all on function public.platform_review_fbp_claim(jsonb) from public, anon, authenticated;
revoke all on function public.platform_auto_approve_fbp_claims(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_fbp_yearend_settlement(jsonb) from public, anon, authenticated;
revoke all on function public.platform_fbp_benefit_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_fbp_policy_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_fbp_employee_dashboard_rows() from public, anon, authenticated;
revoke all on function public.platform_fbp_pending_approval_rows() from public, anon, authenticated;
revoke all on function public.platform_fbp_claim_queue_rows() from public, anon, authenticated;
revoke all on function public.platform_fbp_monthly_ledger_rows() from public, anon, authenticated;
revoke all on function public.platform_fbp_yearend_settlement_status_rows() from public, anon, authenticated;

grant select on public.platform_rm_fbp_benefit_catalog to service_role;
grant select on public.platform_rm_fbp_policy_catalog to service_role;
grant select on public.platform_rm_fbp_employee_dashboard to service_role;
grant select on public.platform_rm_fbp_pending_approvals to service_role;
grant select on public.platform_rm_fbp_claim_queue to service_role;
grant select on public.platform_rm_fbp_monthly_ledger to service_role;
grant select on public.platform_rm_fbp_yearend_settlement_status to service_role;

grant execute on function public.platform_fbp_module_template_version() to service_role;
grant execute on function public.platform_fbp_resolve_context(jsonb) to service_role;
grant execute on function public.platform_apply_fbp_to_tenant(jsonb) to service_role;
grant execute on function public.platform_register_fbp_benefit(jsonb) to service_role;
grant execute on function public.platform_register_fbp_policy(jsonb) to service_role;
grant execute on function public.platform_upsert_fbp_policy_benefit(jsonb) to service_role;
grant execute on function public.platform_assign_employee_fbp_policy(jsonb) to service_role;
grant execute on function public.platform_get_fbp_eligible_benefits(jsonb) to service_role;
grant execute on function public.platform_initialize_fbp_declaration(jsonb) to service_role;
grant execute on function public.platform_upsert_fbp_declaration_item(jsonb) to service_role;
grant execute on function public.platform_submit_fbp_declaration(jsonb) to service_role;
grant execute on function public.platform_review_fbp_declaration(jsonb) to service_role;
grant execute on function public.platform_validate_fbp_claim_limits(jsonb) to service_role;
grant execute on function public.platform_submit_fbp_claim(jsonb) to service_role;
grant execute on function public.platform_attach_fbp_claim_document(jsonb) to service_role;
grant execute on function public.platform_review_fbp_claim(jsonb) to service_role;
grant execute on function public.platform_auto_approve_fbp_claims(jsonb) to service_role;
grant execute on function public.platform_process_fbp_yearend_settlement(jsonb) to service_role;

do $$
declare
  v_template_version text := public.platform_fbp_module_template_version();
  v_result jsonb;
begin
  v_result := public.platform_register_template_version(jsonb_build_object('template_version', v_template_version,'template_scope', 'module','module_code', 'FBP','template_status', 'released','description', 'FBP tenant-owned flexible benefits baseline.','metadata', jsonb_build_object('slice', 'FBP','module_code', 'FBP')));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'FBP template version registration failed: %', v_result::text; end if;

  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'FBP','source_schema_name', 'public','source_table_name', 'wcm_fbp_benefit','target_table_name', 'wcm_fbp_benefit','clone_order', 100,'notes', jsonb_build_object('slice', 'FBP','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'FBP benefit registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'FBP','source_schema_name', 'public','source_table_name', 'wcm_fbp_policy','target_table_name', 'wcm_fbp_policy','clone_order', 110,'notes', jsonb_build_object('slice', 'FBP','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'FBP policy registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'FBP','source_schema_name', 'public','source_table_name', 'wcm_fbp_policy_benefit','target_table_name', 'wcm_fbp_policy_benefit','clone_order', 120,'notes', jsonb_build_object('slice', 'FBP','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'FBP policy benefit registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'FBP','source_schema_name', 'public','source_table_name', 'wcm_fbp_employee_assignment','target_table_name', 'wcm_fbp_employee_assignment','clone_order', 130,'notes', jsonb_build_object('slice', 'FBP','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'FBP assignment registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'FBP','source_schema_name', 'public','source_table_name', 'wcm_fbp_declaration','target_table_name', 'wcm_fbp_declaration','clone_order', 140,'notes', jsonb_build_object('slice', 'FBP','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'FBP declaration registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'FBP','source_schema_name', 'public','source_table_name', 'wcm_fbp_declaration_item','target_table_name', 'wcm_fbp_declaration_item','clone_order', 150,'notes', jsonb_build_object('slice', 'FBP','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'FBP declaration item registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'FBP','source_schema_name', 'public','source_table_name', 'wcm_fbp_claim','target_table_name', 'wcm_fbp_claim','clone_order', 160,'notes', jsonb_build_object('slice', 'FBP','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'FBP claim registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'FBP','source_schema_name', 'public','source_table_name', 'wcm_fbp_claim_document_binding','target_table_name', 'wcm_fbp_claim_document_binding','clone_order', 170,'notes', jsonb_build_object('slice', 'FBP','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'FBP claim document binding registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'FBP','source_schema_name', 'public','source_table_name', 'wcm_fbp_monthly_ledger','target_table_name', 'wcm_fbp_monthly_ledger','clone_order', 180,'notes', jsonb_build_object('slice', 'FBP','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'FBP monthly ledger registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'FBP','source_schema_name', 'public','source_table_name', 'wcm_fbp_yearend_settlement','target_table_name', 'wcm_fbp_yearend_settlement','clone_order', 190,'notes', jsonb_build_object('slice', 'FBP','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'FBP year-end settlement registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'FBP','source_schema_name', 'public','source_table_name', 'wcm_fbp_audit_event','target_table_name', 'wcm_fbp_audit_event','clone_order', 200,'notes', jsonb_build_object('slice', 'FBP','kind', 'tenant_owned_table'))); if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'FBP audit registration failed: %', v_result::text; end if;
end;
$$;;
