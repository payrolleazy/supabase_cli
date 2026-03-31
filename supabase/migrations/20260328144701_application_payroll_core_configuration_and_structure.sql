set search_path = public, pg_temp;

create or replace function public.platform_register_payroll_area(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_area_code text := upper(nullif(btrim(coalesce(p_params->>'area_code', '')), ''));
  v_area_name text := nullif(btrim(coalesce(p_params->>'area_name', '')), '');
  v_payroll_frequency text := upper(coalesce(nullif(btrim(p_params->>'payroll_frequency'), ''), 'MONTHLY'));
  v_currency_code text := upper(coalesce(nullif(btrim(p_params->>'currency_code'), ''), 'INR'));
  v_country_code text := upper(nullif(btrim(coalesce(p_params->>'country_code', '')), ''));
  v_area_status text := upper(coalesce(nullif(btrim(p_params->>'area_status'), ''), 'ACTIVE'));
  v_area_metadata jsonb := coalesce(p_params->'area_metadata', '{}'::jsonb);
  v_payroll_area_id uuid;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_area_code is null then return public.platform_json_response(false,'AREA_CODE_REQUIRED','area_code is required.', '{}'::jsonb); end if;
  if v_area_name is null then return public.platform_json_response(false,'AREA_NAME_REQUIRED','area_name is required.', '{}'::jsonb); end if;
  if jsonb_typeof(v_area_metadata) <> 'object' then return public.platform_json_response(false,'AREA_METADATA_INVALID','area_metadata must be a JSON object.', '{}'::jsonb); end if;

  execute format('select payroll_area_id from %I.wcm_payroll_area where lower(area_code) = lower($1)', v_schema_name) into v_payroll_area_id using v_area_code;
  if v_payroll_area_id is null then
    execute format('insert into %I.wcm_payroll_area (area_code, area_name, payroll_frequency, currency_code, country_code, area_status, area_metadata) values ($1,$2,$3,$4,$5,$6,$7) returning payroll_area_id', v_schema_name)
      into v_payroll_area_id using v_area_code, v_area_name, v_payroll_frequency, v_currency_code, v_country_code, v_area_status, v_area_metadata;
  else
    execute format('update %I.wcm_payroll_area set area_name = $2, payroll_frequency = $3, currency_code = $4, country_code = $5, area_status = $6, area_metadata = $7, updated_at = timezone(''utc'', now()) where payroll_area_id = $1', v_schema_name)
      using v_payroll_area_id, v_area_name, v_payroll_frequency, v_currency_code, v_country_code, v_area_status, v_area_metadata;
  end if;

  return public.platform_json_response(true,'OK','Payroll area upserted.',jsonb_build_object('payroll_area_id', v_payroll_area_id,'area_code', v_area_code));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_payroll_area.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_payroll_component(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_component_code text := upper(nullif(btrim(coalesce(p_params->>'component_code', '')), ''));
  v_component_name text := nullif(btrim(coalesce(p_params->>'component_name', '')), '');
  v_component_kind text := upper(coalesce(nullif(btrim(p_params->>'component_kind'), ''), 'EARNING'));
  v_calculation_method text := upper(coalesce(nullif(btrim(p_params->>'calculation_method'), ''), 'INPUT'));
  v_payslip_label text := nullif(btrim(coalesce(p_params->>'payslip_label', '')), '');
  v_is_taxable boolean := coalesce((p_params->>'is_taxable')::boolean, false);
  v_is_proratable boolean := coalesce((p_params->>'is_proratable')::boolean, false);
  v_display_order integer := coalesce(public.platform_payroll_core_try_integer(p_params->>'display_order'), 100);
  v_component_status text := upper(coalesce(nullif(btrim(p_params->>'component_status'), ''), 'ACTIVE'));
  v_rule_definition jsonb := coalesce(p_params->'default_rule_definition', '{}'::jsonb);
  v_component_metadata jsonb := coalesce(p_params->'component_metadata', '{}'::jsonb);
  v_component_id bigint;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_component_code is null then return public.platform_json_response(false,'COMPONENT_CODE_REQUIRED','component_code is required.', '{}'::jsonb); end if;
  if v_component_name is null then return public.platform_json_response(false,'COMPONENT_NAME_REQUIRED','component_name is required.', '{}'::jsonb); end if;
  if jsonb_typeof(v_rule_definition) <> 'object' or jsonb_typeof(v_component_metadata) <> 'object' then return public.platform_json_response(false,'COMPONENT_JSON_INVALID','Component JSON fields must be objects.', '{}'::jsonb); end if;

  execute format('select component_id from %I.wcm_component where lower(component_code) = lower($1)', v_schema_name) into v_component_id using v_component_code;
  if v_component_id is null then
    execute format('insert into %I.wcm_component (component_code, component_name, component_kind, calculation_method, payslip_label, is_taxable, is_proratable, display_order, component_status, default_rule_definition, component_metadata) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) returning component_id', v_schema_name)
      into v_component_id using v_component_code, v_component_name, v_component_kind, v_calculation_method, v_payslip_label, v_is_taxable, v_is_proratable, v_display_order, v_component_status, v_rule_definition, v_component_metadata;
  else
    execute format('update %I.wcm_component set component_name = $2, component_kind = $3, calculation_method = $4, payslip_label = $5, is_taxable = $6, is_proratable = $7, display_order = $8, component_status = $9, default_rule_definition = $10, component_metadata = $11, updated_at = timezone(''utc'', now()) where component_id = $1', v_schema_name)
      using v_component_id, v_component_name, v_component_kind, v_calculation_method, v_payslip_label, v_is_taxable, v_is_proratable, v_display_order, v_component_status, v_rule_definition, v_component_metadata;
  end if;

  return public.platform_json_response(true,'OK','Payroll component upserted.',jsonb_build_object('component_id', v_component_id,'component_code', v_component_code));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_payroll_component.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_component_dependency(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_component_id bigint := coalesce(public.platform_payroll_core_try_integer(p_params->>'component_id'), 0);
  v_depends_on_component_id bigint := coalesce(public.platform_payroll_core_try_integer(p_params->>'depends_on_component_id'), 0);
  v_dependency_kind text := upper(coalesce(nullif(btrim(p_params->>'dependency_kind'), ''), 'REQUIRES'));
  v_dependency_metadata jsonb := coalesce(p_params->'dependency_metadata', '{}'::jsonb);
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_component_id <= 0 or v_depends_on_component_id <= 0 then return public.platform_json_response(false,'COMPONENT_IDS_REQUIRED','component_id and depends_on_component_id are required.', '{}'::jsonb); end if;
  if v_component_id = v_depends_on_component_id then return public.platform_json_response(false,'DEPENDENCY_SELF_REFERENCE','A component cannot depend on itself.', '{}'::jsonb); end if;
  if jsonb_typeof(v_dependency_metadata) <> 'object' then return public.platform_json_response(false,'DEPENDENCY_METADATA_INVALID','dependency_metadata must be a JSON object.', '{}'::jsonb); end if;

  execute format('insert into %I.wcm_component_dependency (component_id, depends_on_component_id, dependency_kind, dependency_metadata) values ($1,$2,$3,$4) on conflict (component_id, depends_on_component_id) do update set dependency_kind = excluded.dependency_kind, dependency_metadata = excluded.dependency_metadata', v_schema_name)
    using v_component_id, v_depends_on_component_id, v_dependency_kind, v_dependency_metadata;

  return public.platform_json_response(true,'OK','Component dependency upserted.',jsonb_build_object('component_id', v_component_id,'depends_on_component_id', v_depends_on_component_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_component_dependency.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_component_rule_template(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_template_code text := lower(nullif(btrim(coalesce(p_params->>'template_code', '')), ''));
  v_template_name text := nullif(btrim(coalesce(p_params->>'template_name', '')), '');
  v_component_id bigint := public.platform_payroll_core_try_integer(p_params->>'component_id');
  v_template_status text := upper(coalesce(nullif(btrim(p_params->>'template_status'), ''), 'ACTIVE'));
  v_rule_definition jsonb := coalesce(p_params->'rule_definition', '{}'::jsonb);
  v_template_metadata jsonb := coalesce(p_params->'template_metadata', '{}'::jsonb);
  v_template_id uuid;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_template_code is null then return public.platform_json_response(false,'TEMPLATE_CODE_REQUIRED','template_code is required.', '{}'::jsonb); end if;
  if v_template_name is null then return public.platform_json_response(false,'TEMPLATE_NAME_REQUIRED','template_name is required.', '{}'::jsonb); end if;
  if jsonb_typeof(v_rule_definition) <> 'object' or jsonb_typeof(v_template_metadata) <> 'object' then return public.platform_json_response(false,'RULE_TEMPLATE_JSON_INVALID','rule_definition and template_metadata must be JSON objects.', '{}'::jsonb); end if;

  execute format('select component_rule_template_id from %I.wcm_component_rule_template where lower(template_code) = lower($1)', v_schema_name) into v_template_id using v_template_code;
  if v_template_id is null then
    execute format('insert into %I.wcm_component_rule_template (template_code, template_name, component_id, template_status, rule_definition, template_metadata) values ($1,$2,$3,$4,$5,$6) returning component_rule_template_id', v_schema_name)
      into v_template_id using v_template_code, v_template_name, v_component_id, v_template_status, v_rule_definition, v_template_metadata;
  else
    execute format('update %I.wcm_component_rule_template set template_name = $2, component_id = $3, template_status = $4, rule_definition = $5, template_metadata = $6, updated_at = timezone(''utc'', now()) where component_rule_template_id = $1', v_schema_name)
      using v_template_id, v_template_name, v_component_id, v_template_status, v_rule_definition, v_template_metadata;
  end if;

  return public.platform_json_response(true,'OK','Component rule template upserted.',jsonb_build_object('component_rule_template_id', v_template_id,'template_code', v_template_code));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_component_rule_template.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_register_pay_structure(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_payroll_area_id uuid := public.platform_try_uuid(p_params->>'payroll_area_id');
  v_structure_code text := upper(nullif(btrim(coalesce(p_params->>'structure_code', '')), ''));
  v_structure_name text := nullif(btrim(coalesce(p_params->>'structure_name', '')), '');
  v_structure_status text := upper(coalesce(nullif(btrim(p_params->>'structure_status'), ''), 'DRAFT'));
  v_effective_from date := coalesce(public.platform_payroll_core_try_date(p_params->>'effective_from'), current_date);
  v_effective_to date := public.platform_payroll_core_try_date(p_params->>'effective_to');
  v_structure_metadata jsonb := coalesce(p_params->'structure_metadata', '{}'::jsonb);
  v_pay_structure_id uuid;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_payroll_area_id is null then return public.platform_json_response(false,'PAYROLL_AREA_ID_REQUIRED','payroll_area_id is required.', '{}'::jsonb); end if;
  if v_structure_code is null then return public.platform_json_response(false,'STRUCTURE_CODE_REQUIRED','structure_code is required.', '{}'::jsonb); end if;
  if v_structure_name is null then return public.platform_json_response(false,'STRUCTURE_NAME_REQUIRED','structure_name is required.', '{}'::jsonb); end if;
  if jsonb_typeof(v_structure_metadata) <> 'object' then return public.platform_json_response(false,'STRUCTURE_METADATA_INVALID','structure_metadata must be a JSON object.', '{}'::jsonb); end if;

  execute format('select pay_structure_id from %I.wcm_pay_structure where lower(structure_code) = lower($1)', v_schema_name) into v_pay_structure_id using v_structure_code;
  if v_pay_structure_id is null then
    execute format('insert into %I.wcm_pay_structure (payroll_area_id, structure_code, structure_name, structure_status, effective_from, effective_to, structure_metadata) values ($1,$2,$3,$4,$5,$6,$7) returning pay_structure_id', v_schema_name)
      into v_pay_structure_id using v_payroll_area_id, v_structure_code, v_structure_name, v_structure_status, v_effective_from, v_effective_to, v_structure_metadata;
  else
    execute format('update %I.wcm_pay_structure set payroll_area_id = $2, structure_name = $3, structure_status = $4, effective_from = $5, effective_to = $6, structure_metadata = $7, updated_at = timezone(''utc'', now()) where pay_structure_id = $1', v_schema_name)
      using v_pay_structure_id, v_payroll_area_id, v_structure_name, v_structure_status, v_effective_from, v_effective_to, v_structure_metadata;
  end if;

  return public.platform_json_response(true,'OK','Pay structure upserted.',jsonb_build_object('pay_structure_id', v_pay_structure_id,'structure_code', v_structure_code));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_register_pay_structure.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_upsert_pay_structure_component(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_pay_structure_id uuid := public.platform_try_uuid(p_params->>'pay_structure_id');
  v_component_id bigint := public.platform_payroll_core_try_integer(p_params->>'component_id');
  v_display_order integer := coalesce(public.platform_payroll_core_try_integer(p_params->>'display_order'), 100);
  v_component_status text := upper(coalesce(nullif(btrim(p_params->>'component_status'), ''), 'ACTIVE'));
  v_staged_rule_definition jsonb := coalesce(p_params->'staged_rule_definition', '{}'::jsonb);
  v_eligibility_rule_definition jsonb := coalesce(p_params->'eligibility_rule_definition', '{}'::jsonb);
  v_existing_rule jsonb;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_pay_structure_id is null then return public.platform_json_response(false,'PAY_STRUCTURE_ID_REQUIRED','pay_structure_id is required.', '{}'::jsonb); end if;
  if coalesce(v_component_id, 0) <= 0 then return public.platform_json_response(false,'COMPONENT_ID_REQUIRED','component_id is required.', '{}'::jsonb); end if;
  if jsonb_typeof(v_staged_rule_definition) <> 'object' or jsonb_typeof(v_eligibility_rule_definition) <> 'object' then return public.platform_json_response(false,'PAY_STRUCTURE_COMPONENT_JSON_INVALID','Rule-definition fields must be JSON objects.', '{}'::jsonb); end if;

  if v_staged_rule_definition = '{}'::jsonb then
    execute format('select default_rule_definition from %I.wcm_component where component_id = $1', v_schema_name) into v_existing_rule using v_component_id;
    v_staged_rule_definition := coalesce(v_existing_rule, '{}'::jsonb);
  end if;

  execute format('insert into %I.wcm_pay_structure_component (pay_structure_id, component_id, staged_rule_definition, eligibility_rule_definition, display_order, component_status) values ($1,$2,$3,$4,$5,$6) on conflict (pay_structure_id, component_id) do update set staged_rule_definition = excluded.staged_rule_definition, eligibility_rule_definition = excluded.eligibility_rule_definition, display_order = excluded.display_order, component_status = excluded.component_status, updated_at = timezone(''utc'', now())', v_schema_name)
    using v_pay_structure_id, v_component_id, v_staged_rule_definition, v_eligibility_rule_definition, v_display_order, v_component_status;

  return public.platform_json_response(true,'OK','Pay-structure component upserted.',jsonb_build_object('pay_structure_id', v_pay_structure_id,'component_id', v_component_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_upsert_pay_structure_component.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_validate_pay_structure(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_pay_structure_id uuid := public.platform_try_uuid(p_params->>'pay_structure_id');
  v_component_count integer := 0;
  v_component_codes jsonb := '[]'::jsonb;
  v_missing_dependencies jsonb := '[]'::jsonb;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_pay_structure_id is null then return public.platform_json_response(false,'PAY_STRUCTURE_ID_REQUIRED','pay_structure_id is required.', '{}'::jsonb); end if;

  execute format('select count(*) from %I.wcm_pay_structure_component where pay_structure_id = $1 and component_status = ''ACTIVE''', v_schema_name) into v_component_count using v_pay_structure_id;
  if v_component_count = 0 then
    return public.platform_json_response(false,'PAY_STRUCTURE_COMPONENTS_REQUIRED','At least one active pay-structure component is required before validation.',jsonb_build_object('pay_structure_id', v_pay_structure_id));
  end if;

  execute format('select coalesce(jsonb_agg(c.component_code order by psc.display_order, c.component_code), ''[]''::jsonb) from %I.wcm_pay_structure_component psc join %I.wcm_component c on c.component_id = psc.component_id where psc.pay_structure_id = $1 and psc.component_status = ''ACTIVE''', v_schema_name, v_schema_name)
    into v_component_codes using v_pay_structure_id;

  execute format(
    'with active_components as (
       select component_id from %I.wcm_pay_structure_component where pay_structure_id = $1 and component_status = ''ACTIVE''
     )
     select coalesce(jsonb_agg(jsonb_build_object(''component_id'', d.component_id, ''depends_on_component_id'', d.depends_on_component_id) order by d.component_id, d.depends_on_component_id), ''[]''::jsonb)
       from %I.wcm_component_dependency d
      where d.component_id in (select component_id from active_components)
        and d.depends_on_component_id not in (select component_id from active_components)',
    v_schema_name,
    v_schema_name
  ) into v_missing_dependencies using v_pay_structure_id;

  if jsonb_array_length(v_missing_dependencies) > 0 then
    return public.platform_json_response(false,'PAY_STRUCTURE_DEPENDENCY_MISSING','One or more component dependencies are missing from the structure.',jsonb_build_object('pay_structure_id', v_pay_structure_id,'missing_dependencies', v_missing_dependencies));
  end if;

  return public.platform_json_response(true,'OK','Pay structure validated.',jsonb_build_object('pay_structure_id', v_pay_structure_id,'component_count', v_component_count,'component_codes', v_component_codes));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_validate_pay_structure.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_activate_pay_structure(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_pay_structure_id uuid := public.platform_try_uuid(p_params->>'pay_structure_id');
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_validation jsonb;
  v_next_version integer := 1;
  v_snapshot jsonb;
  v_pay_structure_version_id uuid;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_pay_structure_id is null then return public.platform_json_response(false,'PAY_STRUCTURE_ID_REQUIRED','pay_structure_id is required.', '{}'::jsonb); end if;

  v_validation := public.platform_validate_pay_structure(jsonb_build_object('tenant_id', public.platform_try_uuid(v_context->'details'->>'tenant_id'),'pay_structure_id', v_pay_structure_id,'source', 'platform_activate_pay_structure'));
  if coalesce((v_validation->>'success')::boolean, false) is not true then return v_validation; end if;

  execute format('select coalesce(max(version_no), 0) + 1 from %I.wcm_pay_structure_version where pay_structure_id = $1', v_schema_name) into v_next_version using v_pay_structure_id;
  execute format(
    'select jsonb_build_object(''components'', coalesce(jsonb_agg(jsonb_build_object(''component_id'', c.component_id, ''component_code'', c.component_code, ''component_name'', c.component_name, ''component_kind'', c.component_kind, ''calculation_method'', c.calculation_method, ''display_order'', psc.display_order, ''payslip_label'', c.payslip_label, ''is_taxable'', c.is_taxable, ''is_proratable'', c.is_proratable, ''rule_definition'', coalesce(psc.staged_rule_definition, c.default_rule_definition, ''{}''::jsonb), ''eligibility_rule_definition'', coalesce(psc.eligibility_rule_definition, ''{}''::jsonb)) order by psc.display_order, c.component_code), ''[]''::jsonb))
       from %I.wcm_pay_structure_component psc
       join %I.wcm_component c on c.component_id = psc.component_id
      where psc.pay_structure_id = $1 and psc.component_status = ''ACTIVE''',
    v_schema_name,
    v_schema_name
  ) into v_snapshot using v_pay_structure_id;

  execute format('update %I.wcm_pay_structure_version set version_status = ''SUPERSEDED'', updated_at = timezone(''utc'', now()) where pay_structure_id = $1 and version_status = ''ACTIVE''', v_schema_name) using v_pay_structure_id;
  execute format('insert into %I.wcm_pay_structure_version (pay_structure_id, version_no, version_status, version_snapshot, activated_at, activated_by_actor_user_id) values ($1,$2,''ACTIVE'',$3,timezone(''utc'', now()),$4) returning pay_structure_version_id', v_schema_name)
    into v_pay_structure_version_id using v_pay_structure_id, v_next_version, coalesce(v_snapshot, jsonb_build_object('components', '[]'::jsonb)), v_actor_user_id;
  execute format('update %I.wcm_pay_structure set active_version_no = $2, structure_status = ''ACTIVE'', updated_at = timezone(''utc'', now()) where pay_structure_id = $1', v_schema_name)
    using v_pay_structure_id, v_next_version;

  return public.platform_json_response(true,'OK','Pay structure activated.',jsonb_build_object('pay_structure_id', v_pay_structure_id,'pay_structure_version_id', v_pay_structure_version_id,'version_no', v_next_version));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_activate_pay_structure.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_assign_employee_pay_structure(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_pay_structure_id uuid := public.platform_try_uuid(p_params->>'pay_structure_id');
  v_pay_structure_version_id uuid := public.platform_try_uuid(p_params->>'pay_structure_version_id');
  v_effective_from date := coalesce(public.platform_payroll_core_try_date(p_params->>'effective_from'), current_date);
  v_effective_to date := public.platform_payroll_core_try_date(p_params->>'effective_to');
  v_override_inputs jsonb := coalesce(p_params->'override_inputs', '{}'::jsonb);
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_assignment_id uuid;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_employee_id is null then return public.platform_json_response(false,'EMPLOYEE_ID_REQUIRED','employee_id is required.', '{}'::jsonb); end if;
  if v_pay_structure_id is null then return public.platform_json_response(false,'PAY_STRUCTURE_ID_REQUIRED','pay_structure_id is required.', '{}'::jsonb); end if;
  if jsonb_typeof(v_override_inputs) <> 'object' then return public.platform_json_response(false,'OVERRIDE_INPUTS_INVALID','override_inputs must be a JSON object.', '{}'::jsonb); end if;

  if v_pay_structure_version_id is null then
    execute format('select pay_structure_version_id from %I.wcm_pay_structure_version where pay_structure_id = $1 and version_status = ''ACTIVE'' order by version_no desc limit 1', v_schema_name)
      into v_pay_structure_version_id using v_pay_structure_id;
  end if;
  if v_pay_structure_version_id is null then return public.platform_json_response(false,'PAY_STRUCTURE_VERSION_REQUIRED','An active pay-structure version is required before assignment.',jsonb_build_object('pay_structure_id', v_pay_structure_id)); end if;

  execute format('update %I.wcm_employee_pay_structure_assignment set assignment_status = ''SUPERSEDED'', effective_to = least(coalesce(effective_to, $2 - 1), $2 - 1), updated_at = timezone(''utc'', now()) where employee_id = $1 and assignment_status = ''ACTIVE'' and effective_from <= $2 and coalesce(effective_to, $2) >= $2', v_schema_name)
    using v_employee_id, v_effective_from;

  execute format('insert into %I.wcm_employee_pay_structure_assignment (employee_id, pay_structure_id, pay_structure_version_id, effective_from, effective_to, assignment_status, override_inputs, assigned_by_actor_user_id) values ($1,$2,$3,$4,$5,''ACTIVE'',$6,$7) returning employee_pay_structure_assignment_id', v_schema_name)
    into v_assignment_id using v_employee_id, v_pay_structure_id, v_pay_structure_version_id, v_effective_from, v_effective_to, v_override_inputs, v_actor_user_id;

  return public.platform_json_response(true,'OK','Employee pay structure assigned.',jsonb_build_object('employee_pay_structure_assignment_id', v_assignment_id,'employee_id', v_employee_id,'pay_structure_id', v_pay_structure_id,'pay_structure_version_id', v_pay_structure_version_id));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_assign_employee_pay_structure.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_get_employee_pay_structure_components(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_context jsonb;
  v_schema_name text;
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_effective_on date := coalesce(public.platform_payroll_core_try_date(p_params->>'effective_on'), current_date);
  v_assignment record;
begin
  v_context := public.platform_payroll_core_resolve_context(p_params);
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';
  if v_employee_id is null then return public.platform_json_response(false,'EMPLOYEE_ID_REQUIRED','employee_id is required.', '{}'::jsonb); end if;

  execute format('select a.employee_pay_structure_assignment_id, a.pay_structure_id, a.pay_structure_version_id, ps.structure_code, psv.version_no, psv.version_snapshot, a.override_inputs from %I.wcm_employee_pay_structure_assignment a join %I.wcm_pay_structure ps on ps.pay_structure_id = a.pay_structure_id join %I.wcm_pay_structure_version psv on psv.pay_structure_version_id = a.pay_structure_version_id where a.employee_id = $1 and a.assignment_status = ''ACTIVE'' and a.effective_from <= $2 and (a.effective_to is null or a.effective_to >= $2) order by a.effective_from desc, a.created_at desc limit 1', v_schema_name, v_schema_name, v_schema_name)
    into v_assignment using v_employee_id, v_effective_on;
  if v_assignment.employee_pay_structure_assignment_id is null then
    return public.platform_json_response(false,'PAY_STRUCTURE_ASSIGNMENT_NOT_FOUND','No active pay-structure assignment was found for the employee on the requested date.',jsonb_build_object('employee_id', v_employee_id,'effective_on', v_effective_on));
  end if;

  return public.platform_json_response(true,'OK','Employee pay-structure components resolved.',jsonb_build_object('employee_id', v_employee_id,'effective_on', v_effective_on,'employee_pay_structure_assignment_id', v_assignment.employee_pay_structure_assignment_id,'pay_structure_id', v_assignment.pay_structure_id,'pay_structure_version_id', v_assignment.pay_structure_version_id,'structure_code', v_assignment.structure_code,'version_no', v_assignment.version_no,'components', coalesce(v_assignment.version_snapshot->'components', '[]'::jsonb),'override_inputs', coalesce(v_assignment.override_inputs, '{}'::jsonb)));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_get_employee_pay_structure_components.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_payroll_core_write_input_entry(
  p_schema_name text,
  p_employee_id uuid,
  p_payroll_period date,
  p_component_code text,
  p_input_source text,
  p_source_record_id text,
  p_source_batch_id bigint,
  p_numeric_value numeric,
  p_text_value text,
  p_json_value jsonb,
  p_source_metadata jsonb,
  p_input_status text default 'VALIDATED'
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  execute format('insert into %I.wcm_payroll_input_entry (employee_id, payroll_period, component_code, input_source, source_record_id, source_batch_id, numeric_value, text_value, json_value, source_metadata, input_status) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) on conflict (employee_id, payroll_period, component_code, input_source, source_record_id) do update set source_batch_id = excluded.source_batch_id, numeric_value = excluded.numeric_value, text_value = excluded.text_value, json_value = excluded.json_value, source_metadata = excluded.source_metadata, input_status = excluded.input_status, updated_at = timezone(''utc'', now())', p_schema_name)
    using p_employee_id, p_payroll_period, p_component_code, p_input_source, coalesce(p_source_record_id, ''), p_source_batch_id, p_numeric_value, p_text_value, p_json_value, coalesce(p_source_metadata, '{}'::jsonb), p_input_status;
end;
$function$;;
