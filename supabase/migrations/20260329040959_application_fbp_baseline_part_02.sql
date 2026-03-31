create or replace function public.platform_register_fbp_benefit(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid;
  v_benefit_id uuid := public.platform_try_uuid(p_params->>'benefit_id');
  v_benefit_code text := nullif(lower(btrim(coalesce(p_params->>'benefit_code', ''))), '');
  v_benefit_name text := nullif(btrim(coalesce(p_params->>'benefit_name', '')), '');
  v_tax_section text := nullif(btrim(coalesce(p_params->>'tax_section', '')), '');
  v_benefit_category text := upper(coalesce(nullif(btrim(p_params->>'benefit_category'), ''), 'REIMBURSEMENT'));
  v_tax_regime_applicability text := upper(coalesce(nullif(btrim(p_params->>'tax_regime_applicability'), ''), 'BOTH'));
  v_is_taxable boolean := coalesce((p_params->>'is_taxable')::boolean, false);
  v_benefit_status text := upper(coalesce(nullif(btrim(p_params->>'benefit_status'), ''), 'ACTIVE'));
  v_effective_from date := coalesce(public.platform_fbp_try_date(p_params->>'effective_from'), current_date);
  v_effective_to date := public.platform_fbp_try_date(p_params->>'effective_to');
  v_limit_config jsonb := case when p_params ? 'limit_config' then coalesce(p_params->'limit_config', '{}'::jsonb) else null end;
  v_reimbursement_rules jsonb := case when p_params ? 'reimbursement_rules' then coalesce(p_params->'reimbursement_rules', '{}'::jsonb) else null end;
  v_proration_rules jsonb := case when p_params ? 'proration_rules' then coalesce(p_params->'proration_rules', '{}'::jsonb) else null end;
  v_display_config jsonb := case when p_params ? 'display_config' then coalesce(p_params->'display_config', '{}'::jsonb) else null end;
  v_benefit_metadata jsonb := case when p_params ? 'benefit_metadata' then coalesce(p_params->'benefit_metadata', '{}'::jsonb) else null end;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_actor_user_id := public.platform_try_uuid(v_context->'details'->>'actor_user_id');
  if v_limit_config is not null and jsonb_typeof(v_limit_config) <> 'object' then return public.platform_json_response(false,'LIMIT_CONFIG_INVALID','limit_config must be a JSON object.', '{}'::jsonb); end if;
  if v_reimbursement_rules is not null and jsonb_typeof(v_reimbursement_rules) <> 'object' then return public.platform_json_response(false,'REIMBURSEMENT_RULES_INVALID','reimbursement_rules must be a JSON object.', '{}'::jsonb); end if;
  if v_proration_rules is not null and jsonb_typeof(v_proration_rules) <> 'object' then return public.platform_json_response(false,'PRORATION_RULES_INVALID','proration_rules must be a JSON object.', '{}'::jsonb); end if;
  if v_display_config is not null and jsonb_typeof(v_display_config) <> 'object' then return public.platform_json_response(false,'DISPLAY_CONFIG_INVALID','display_config must be a JSON object.', '{}'::jsonb); end if;
  if v_benefit_metadata is not null and jsonb_typeof(v_benefit_metadata) <> 'object' then return public.platform_json_response(false,'BENEFIT_METADATA_INVALID','benefit_metadata must be a JSON object.', '{}'::jsonb); end if;

  if v_benefit_id is null then
    if v_benefit_code is null or v_benefit_name is null then
      return public.platform_json_response(false,'BENEFIT_FIELDS_REQUIRED','benefit_code and benefit_name are required when creating an FBP benefit.', '{}'::jsonb);
    end if;
    execute format('select benefit_id from %I.wcm_fbp_benefit where lower(benefit_code) = $1', v_schema_name) into v_benefit_id using v_benefit_code;
  end if;

  if v_benefit_id is null then
    execute format('insert into %I.wcm_fbp_benefit (benefit_code, benefit_name, benefit_category, tax_section, tax_regime_applicability, is_taxable, limit_config, reimbursement_rules, proration_rules, display_config, benefit_status, effective_from, effective_to, benefit_metadata) values ($1,$2,$3,$4,$5,$6,coalesce($7,''{}''::jsonb),coalesce($8,''{}''::jsonb),coalesce($9,''{}''::jsonb),coalesce($10,''{}''::jsonb),$11,$12,$13,coalesce($14,''{}''::jsonb)) returning benefit_id', v_schema_name)
      into v_benefit_id using v_benefit_code, v_benefit_name, v_benefit_category, v_tax_section, v_tax_regime_applicability, v_is_taxable, v_limit_config, v_reimbursement_rules, v_proration_rules, v_display_config, v_benefit_status, v_effective_from, v_effective_to, v_benefit_metadata;
  else
    execute format('update %I.wcm_fbp_benefit set benefit_code = coalesce($2, benefit_code), benefit_name = coalesce($3, benefit_name), benefit_category = coalesce($4, benefit_category), tax_section = coalesce($5, tax_section), tax_regime_applicability = coalesce($6, tax_regime_applicability), is_taxable = coalesce($7, is_taxable), limit_config = coalesce($8, limit_config), reimbursement_rules = coalesce($9, reimbursement_rules), proration_rules = coalesce($10, proration_rules), display_config = coalesce($11, display_config), benefit_status = coalesce($12, benefit_status), effective_from = coalesce($13, effective_from), effective_to = coalesce($14, effective_to), benefit_metadata = coalesce($15, benefit_metadata), updated_at = timezone(''utc'', now()) where benefit_id = $1 returning benefit_id', v_schema_name)
      into v_benefit_id using v_benefit_id, v_benefit_code, v_benefit_name, nullif(v_benefit_category, ''), v_tax_section, nullif(v_tax_regime_applicability, ''), case when p_params ? 'is_taxable' then v_is_taxable else null end, v_limit_config, v_reimbursement_rules, v_proration_rules, v_display_config, nullif(v_benefit_status, ''), case when p_params ? 'effective_from' then v_effective_from else null end, case when p_params ? 'effective_to' then v_effective_to else null end, v_benefit_metadata;
  end if;

  perform public.platform_fbp_append_audit(v_schema_name,'FBP_BENEFIT_UPSERTED','FBP',jsonb_build_object('benefit_id', v_benefit_id,'benefit_code', coalesce(v_benefit_code, p_params->>'benefit_code')),v_benefit_id,null,null,null,null,null,v_actor_user_id);
  return public.platform_json_response(true,'OK','FBP benefit registered.',jsonb_build_object('benefit_id', v_benefit_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_fbp_benefit.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_fbp_policy(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid;
  v_policy_id uuid := public.platform_try_uuid(p_params->>'policy_id');
  v_policy_code text := nullif(lower(btrim(coalesce(p_params->>'policy_code', ''))), '');
  v_policy_name text := nullif(btrim(coalesce(p_params->>'policy_name', '')), '');
  v_policy_status text := upper(coalesce(nullif(btrim(p_params->>'policy_status'), ''), 'DRAFT'));
  v_policy_tax_regime text := upper(coalesce(nullif(btrim(p_params->>'policy_tax_regime'), ''), 'BOTH'));
  v_eligibility_rules jsonb := case when p_params ? 'eligibility_rules' then coalesce(p_params->'eligibility_rules', '{}'::jsonb) else null end;
  v_total_annual_limit numeric := case when p_params ? 'total_annual_limit' then coalesce(public.platform_fbp_try_numeric(p_params->>'total_annual_limit'), 0) else null end;
  v_allow_employee_customization boolean := coalesce((p_params->>'allow_employee_customization')::boolean, false);
  v_declaration_mandatory boolean := coalesce((p_params->>'declaration_mandatory')::boolean, true);
  v_version_no integer := coalesce((p_params->>'version_no')::integer, 1);
  v_effective_from date := coalesce(public.platform_fbp_try_date(p_params->>'effective_from'), current_date);
  v_effective_to date := public.platform_fbp_try_date(p_params->>'effective_to');
  v_policy_metadata jsonb := case when p_params ? 'policy_metadata' then coalesce(p_params->'policy_metadata', '{}'::jsonb) else null end;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_actor_user_id := public.platform_try_uuid(v_context->'details'->>'actor_user_id');
  if v_eligibility_rules is not null and jsonb_typeof(v_eligibility_rules) <> 'object' then return public.platform_json_response(false,'ELIGIBILITY_RULES_INVALID','eligibility_rules must be a JSON object.', '{}'::jsonb); end if;
  if v_policy_metadata is not null and jsonb_typeof(v_policy_metadata) <> 'object' then return public.platform_json_response(false,'POLICY_METADATA_INVALID','policy_metadata must be a JSON object.', '{}'::jsonb); end if;

  if v_policy_id is null then
    if v_policy_code is null or v_policy_name is null then return public.platform_json_response(false,'POLICY_FIELDS_REQUIRED','policy_code and policy_name are required when creating an FBP policy.', '{}'::jsonb); end if;
    execute format('select policy_id from %I.wcm_fbp_policy where lower(policy_code) = $1', v_schema_name) into v_policy_id using v_policy_code;
  end if;

  if v_policy_id is null then
    execute format('insert into %I.wcm_fbp_policy (policy_code, policy_name, policy_status, eligibility_rules, total_annual_limit, allow_employee_customization, declaration_mandatory, policy_tax_regime, version_no, effective_from, effective_to, policy_metadata) values ($1,$2,$3,coalesce($4,''{}''::jsonb),$5,$6,$7,$8,$9,$10,$11,coalesce($12,''{}''::jsonb)) returning policy_id', v_schema_name)
      into v_policy_id using v_policy_code, v_policy_name, v_policy_status, v_eligibility_rules, coalesce(v_total_annual_limit, 0), v_allow_employee_customization, v_declaration_mandatory, v_policy_tax_regime, v_version_no, v_effective_from, v_effective_to, v_policy_metadata;
  else
    execute format('update %I.wcm_fbp_policy set policy_code = coalesce($2, policy_code), policy_name = coalesce($3, policy_name), policy_status = coalesce($4, policy_status), eligibility_rules = coalesce($5, eligibility_rules), total_annual_limit = coalesce($6, total_annual_limit), allow_employee_customization = coalesce($7, allow_employee_customization), declaration_mandatory = coalesce($8, declaration_mandatory), policy_tax_regime = coalesce($9, policy_tax_regime), version_no = coalesce($10, version_no), effective_from = coalesce($11, effective_from), effective_to = coalesce($12, effective_to), policy_metadata = coalesce($13, policy_metadata), updated_at = timezone(''utc'', now()) where policy_id = $1 returning policy_id', v_schema_name)
      into v_policy_id using v_policy_id, v_policy_code, v_policy_name, nullif(v_policy_status, ''), v_eligibility_rules, v_total_annual_limit, case when p_params ? 'allow_employee_customization' then v_allow_employee_customization else null end, case when p_params ? 'declaration_mandatory' then v_declaration_mandatory else null end, nullif(v_policy_tax_regime, ''), case when p_params ? 'version_no' then v_version_no else null end, case when p_params ? 'effective_from' then v_effective_from else null end, case when p_params ? 'effective_to' then v_effective_to else null end, v_policy_metadata;
  end if;

  perform public.platform_fbp_append_audit(v_schema_name,'FBP_POLICY_UPSERTED','FBP',jsonb_build_object('policy_id', v_policy_id,'policy_code', coalesce(v_policy_code, p_params->>'policy_code')),null,v_policy_id,null,null,null,null,v_actor_user_id);
  return public.platform_json_response(true,'OK','FBP policy registered.',jsonb_build_object('policy_id', v_policy_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_fbp_policy.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;
create or replace function public.platform_upsert_fbp_policy_benefit(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid;
  v_policy_benefit_id uuid;
  v_policy_id uuid := public.platform_try_uuid(p_params->>'policy_id');
  v_benefit_id uuid := public.platform_try_uuid(p_params->>'benefit_id');
  v_policy_code text := nullif(lower(btrim(coalesce(p_params->>'policy_code', ''))), '');
  v_benefit_code text := nullif(lower(btrim(coalesce(p_params->>'benefit_code', ''))), '');
  v_default_annual_limit numeric := coalesce(public.platform_fbp_try_numeric(p_params->>'default_annual_limit'), 0);
  v_is_mandatory boolean := coalesce((p_params->>'is_mandatory')::boolean, false);
  v_is_default_selected boolean := coalesce((p_params->>'is_default_selected')::boolean, false);
  v_override_rules jsonb := coalesce(p_params->'override_rules', '{}'::jsonb);
  v_display_order integer := coalesce((p_params->>'display_order')::integer, 100);
  v_benefit_status text := upper(coalesce(nullif(btrim(p_params->>'benefit_status'), ''), 'ACTIVE'));
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_actor_user_id := public.platform_try_uuid(v_context->'details'->>'actor_user_id');
  if jsonb_typeof(v_override_rules) <> 'object' then return public.platform_json_response(false,'OVERRIDE_RULES_INVALID','override_rules must be a JSON object.', '{}'::jsonb); end if;
  if v_policy_id is null and v_policy_code is not null then execute format('select policy_id from %I.wcm_fbp_policy where lower(policy_code) = $1', v_schema_name) into v_policy_id using v_policy_code; end if;
  if v_benefit_id is null and v_benefit_code is not null then execute format('select benefit_id from %I.wcm_fbp_benefit where lower(benefit_code) = $1', v_schema_name) into v_benefit_id using v_benefit_code; end if;
  if v_policy_id is null or v_benefit_id is null then return public.platform_json_response(false,'POLICY_BENEFIT_TARGET_REQUIRED','policy_id/policy_code and benefit_id/benefit_code are required.', '{}'::jsonb); end if;

  execute format('select policy_benefit_id from %I.wcm_fbp_policy_benefit where policy_id = $1 and benefit_id = $2', v_schema_name) into v_policy_benefit_id using v_policy_id, v_benefit_id;
  if v_policy_benefit_id is null then
    execute format('insert into %I.wcm_fbp_policy_benefit (policy_id, benefit_id, default_annual_limit, is_mandatory, is_default_selected, override_rules, display_order, benefit_status) values ($1,$2,$3,$4,$5,$6,$7,$8) returning policy_benefit_id', v_schema_name)
      into v_policy_benefit_id using v_policy_id, v_benefit_id, v_default_annual_limit, v_is_mandatory, v_is_default_selected, v_override_rules, v_display_order, v_benefit_status;
  else
    execute format('update %I.wcm_fbp_policy_benefit set default_annual_limit = $2, is_mandatory = $3, is_default_selected = $4, override_rules = $5, display_order = $6, benefit_status = $7, updated_at = timezone(''utc'', now()) where policy_benefit_id = $1 returning policy_benefit_id', v_schema_name)
      into v_policy_benefit_id using v_policy_benefit_id, v_default_annual_limit, v_is_mandatory, v_is_default_selected, v_override_rules, v_display_order, v_benefit_status;
  end if;

  perform public.platform_fbp_append_audit(v_schema_name,'FBP_POLICY_BENEFIT_UPSERTED','FBP',jsonb_build_object('policy_benefit_id', v_policy_benefit_id),v_benefit_id,v_policy_id,null,null,null,null,v_actor_user_id);
  return public.platform_json_response(true,'OK','FBP policy benefit upserted.',jsonb_build_object('policy_benefit_id', v_policy_benefit_id,'policy_id', v_policy_id,'benefit_id', v_benefit_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_upsert_fbp_policy_benefit.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_assign_employee_fbp_policy(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_actor_user_id uuid;
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_policy_id uuid := public.platform_try_uuid(p_params->>'policy_id');
  v_policy_code text := nullif(lower(btrim(coalesce(p_params->>'policy_code', ''))), '');
  v_financial_year text := coalesce(nullif(btrim(p_params->>'financial_year'), ''), public.platform_fbp_financial_year(public.platform_fbp_try_date(p_params->>'effective_start_date')));
  v_elected_tax_regime text := upper(coalesce(nullif(btrim(p_params->>'elected_tax_regime'), ''), 'OLD'));
  v_effective_start_date date := coalesce(public.platform_fbp_try_date(p_params->>'effective_start_date'), current_date);
  v_effective_end_date date := public.platform_fbp_try_date(p_params->>'effective_end_date');
  v_total_allocated_amount numeric := public.platform_fbp_try_numeric(p_params->>'total_allocated_amount');
  v_assignment_metadata jsonb := coalesce(p_params->'assignment_metadata', '{}'::jsonb);
  v_assignment_id uuid;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  v_actor_user_id := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_try_uuid(v_context->'details'->>'actor_user_id'));
  if jsonb_typeof(v_assignment_metadata) <> 'object' then return public.platform_json_response(false,'ASSIGNMENT_METADATA_INVALID','assignment_metadata must be a JSON object.', '{}'::jsonb); end if;
  if v_employee_id is null then return public.platform_json_response(false,'EMPLOYEE_ID_REQUIRED','employee_id is required.', '{}'::jsonb); end if;
  if v_policy_id is null and v_policy_code is not null then execute format('select policy_id, total_annual_limit from %I.wcm_fbp_policy where lower(policy_code) = $1 and policy_status in (''DRAFT'',''ACTIVE'')', v_schema_name) into v_policy_id, v_total_allocated_amount using v_policy_code; end if;
  if v_policy_id is null then return public.platform_json_response(false,'POLICY_ID_REQUIRED','policy_id or policy_code is required.', '{}'::jsonb); end if;
  if v_total_allocated_amount is null then execute format('select total_annual_limit from %I.wcm_fbp_policy where policy_id = $1', v_schema_name) into v_total_allocated_amount using v_policy_id; end if;

  execute format('update %I.wcm_fbp_employee_assignment set assignment_status = ''SUPERSEDED'', effective_end_date = least(coalesce(effective_end_date, $2 - 1), $2 - 1), updated_at = timezone(''utc'', now()) where employee_id = $1 and financial_year = $3 and assignment_status = ''ACTIVE''', v_schema_name)
    using v_employee_id, v_effective_start_date, v_financial_year;

  execute format('insert into %I.wcm_fbp_employee_assignment (employee_id, policy_id, financial_year, elected_tax_regime, total_allocated_amount, effective_start_date, effective_end_date, assignment_status, assignment_metadata, created_by_actor_user_id) values ($1,$2,$3,$4,$5,$6,$7,''ACTIVE'',$8,$9) returning employee_assignment_id', v_schema_name)
    into v_assignment_id using v_employee_id, v_policy_id, v_financial_year, v_elected_tax_regime, coalesce(v_total_allocated_amount, 0), v_effective_start_date, v_effective_end_date, v_assignment_metadata, v_actor_user_id;

  perform public.platform_fbp_append_audit(v_schema_name,'FBP_EMPLOYEE_ASSIGNMENT_UPSERTED','FBP',jsonb_build_object('employee_assignment_id', v_assignment_id,'employee_id', v_employee_id,'financial_year', v_financial_year),null,v_policy_id,v_assignment_id,null,null,null,v_actor_user_id);
  return public.platform_json_response(true,'OK','Employee FBP policy assigned.',jsonb_build_object('employee_assignment_id', v_assignment_id,'employee_id', v_employee_id,'policy_id', v_policy_id,'financial_year', v_financial_year));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_assign_employee_fbp_policy.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_get_fbp_eligible_benefits(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb := public.platform_fbp_resolve_context(p_params);
  v_schema_name text;
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_financial_year text := coalesce(nullif(btrim(p_params->>'financial_year'), ''), public.platform_fbp_financial_year(current_date));
  v_assignment_id uuid;
  v_policy_id uuid;
  v_selected_regime text;
  v_benefits jsonb;
begin
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_employee_id is null then return public.platform_json_response(false,'EMPLOYEE_ID_REQUIRED','employee_id is required.', '{}'::jsonb); end if;

  execute format('select employee_assignment_id, policy_id, elected_tax_regime from %I.wcm_fbp_employee_assignment where employee_id = $1 and financial_year = $2 and assignment_status = ''ACTIVE'' order by effective_start_date desc, created_at desc limit 1', v_schema_name)
    into v_assignment_id, v_policy_id, v_selected_regime using v_employee_id, v_financial_year;
  if v_assignment_id is null then return public.platform_json_response(false,'ACTIVE_ASSIGNMENT_NOT_FOUND','No active FBP assignment found for the employee and financial year.',jsonb_build_object('employee_id', v_employee_id,'financial_year', v_financial_year)); end if;

  execute format('select coalesce(jsonb_agg(jsonb_build_object(''benefit_id'', b.benefit_id,''benefit_code'', b.benefit_code,''benefit_name'', b.benefit_name,''benefit_category'', b.benefit_category,''tax_regime_applicability'', b.tax_regime_applicability,''default_annual_limit'', pb.default_annual_limit,''is_mandatory'', pb.is_mandatory,''is_default_selected'', pb.is_default_selected,''display_order'', pb.display_order) order by pb.display_order, b.benefit_code), ''[]''::jsonb) from %I.wcm_fbp_policy_benefit pb join %I.wcm_fbp_benefit b on b.benefit_id = pb.benefit_id where pb.policy_id = $1 and pb.benefit_status = ''ACTIVE'' and b.benefit_status = ''ACTIVE'' and public.platform_fbp_regime_matches(b.tax_regime_applicability, $2)', v_schema_name, v_schema_name)
    into v_benefits using v_policy_id, v_selected_regime;

  return public.platform_json_response(true,'OK','Eligible FBP benefits resolved.',jsonb_build_object('employee_assignment_id', v_assignment_id,'policy_id', v_policy_id,'financial_year', v_financial_year,'selected_tax_regime', v_selected_regime,'benefits', coalesce(v_benefits, '[]'::jsonb)));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_get_fbp_eligible_benefits.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
