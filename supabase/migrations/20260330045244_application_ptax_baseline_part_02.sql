create or replace function public.platform_ptax_get_employee_gross_wages_internal(
  p_schema_name text,
  p_employee_id uuid,
  p_payroll_period date
)
returns numeric
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_amount numeric;
begin
  execute format(
    'select coalesce(sum(calculated_amount), 0)
       from %I.wcm_component_calculation_result
      where employee_id = $1
        and payroll_period = $2
        and component_kind = ''EARNING''
        and result_status in (''CALCULATED'',''PREVIEW'')',
    p_schema_name
  ) into v_amount using p_employee_id, p_payroll_period;

  if coalesce(v_amount, 0) > 0 then
    return v_amount;
  end if;

  execute format(
    'select coalesce(sum(numeric_value), 0)
       from %I.wcm_payroll_input_entry
      where employee_id = $1
        and payroll_period = $2
        and input_source in (''MANUAL'',''TPS'',''SYSTEM'',''PREVIEW_OVERRIDE'',''FBP'')
        and input_status in (''VALIDATED'',''APPLIED'')
        and numeric_value is not null',
    p_schema_name
  ) into v_amount using p_employee_id, p_payroll_period;

  return coalesce(v_amount, 0);
end;
$function$;

create or replace function public.platform_ptax_get_employee_ptax_wages_internal(
  p_schema_name text,
  p_employee_id uuid,
  p_payroll_period date,
  p_state_code text
)
returns numeric
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_amount numeric;
begin
  execute format(
    'with eligible_components as (
       select distinct component_code
         from %I.wcm_ptax_wage_component_mapping
        where state_code = $1
          and is_ptax_eligible = true
          and effective_from <= $2
          and (effective_to is null or effective_to >= $2)
     )
     select coalesce(sum(r.calculated_amount), 0)
       from %I.wcm_component_calculation_result r
       join eligible_components ec on ec.component_code = r.component_code
      where r.employee_id = $3
        and r.payroll_period = $2
        and r.result_status in (''CALCULATED'',''PREVIEW'')',
    p_schema_name,
    p_schema_name
  ) into v_amount using p_state_code, p_payroll_period, p_employee_id;

  if coalesce(v_amount, 0) > 0 then
    return v_amount;
  end if;

  execute format(
    'with eligible_components as (
       select distinct component_code
         from %I.wcm_ptax_wage_component_mapping
        where state_code = $1
          and is_ptax_eligible = true
          and effective_from <= $2
          and (effective_to is null or effective_to >= $2)
     )
     select coalesce(sum(i.numeric_value), 0)
       from %I.wcm_payroll_input_entry i
       join eligible_components ec on ec.component_code = i.component_code
      where i.employee_id = $3
        and i.payroll_period = $2
        and i.input_status in (''VALIDATED'',''APPLIED'')
        and i.numeric_value is not null',
    p_schema_name,
    p_schema_name
  ) into v_amount using p_state_code, p_payroll_period, p_employee_id;

  return coalesce(v_amount, 0);
end;
$function$;

create or replace function public.platform_ptax_sync_deduction_to_payroll_internal(
  p_schema_name text,
  p_tenant_id uuid,
  p_employee_id uuid,
  p_payroll_period date,
  p_batch_id bigint,
  p_source_record_id text,
  p_monthly_deduction numeric default 0,
  p_arrear_deduction numeric default 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_result jsonb;
begin
  if coalesce(p_monthly_deduction, 0) > 0 then
    v_result := public.platform_upsert_payroll_input_entry(jsonb_build_object(
      'tenant_id', p_tenant_id,
      'employee_id', p_employee_id,
      'payroll_period', p_payroll_period,
      'component_code', 'P_TAX',
      'input_source', 'STATUTORY',
      'source_record_id', p_source_record_id,
      'source_batch_id', p_batch_id,
      'numeric_value', round(p_monthly_deduction, 2),
      'source_metadata', jsonb_build_object('module', 'PTAX', 'sync_kind', 'MONTHLY'),
      'input_status', 'VALIDATED'
    ));
    if coalesce((v_result->>'success')::boolean, false) is not true then
      return v_result;
    end if;
  end if;

  if coalesce(p_arrear_deduction, 0) <> 0 then
    v_result := public.platform_upsert_payroll_input_entry(jsonb_build_object(
      'tenant_id', p_tenant_id,
      'employee_id', p_employee_id,
      'payroll_period', p_payroll_period,
      'component_code', 'P_TAX_ARREAR',
      'input_source', 'STATUTORY',
      'source_record_id', p_source_record_id,
      'source_batch_id', p_batch_id,
      'numeric_value', round(p_arrear_deduction, 2),
      'source_metadata', jsonb_build_object('module', 'PTAX', 'sync_kind', 'ARREAR'),
      'input_status', 'VALIDATED'
    ));
    if coalesce((v_result->>'success')::boolean, false) is not true then
      return v_result;
    end if;
  end if;

  return public.platform_json_response(true,'OK','PTAX synced to payroll inputs.',jsonb_build_object(
    'employee_id', p_employee_id,
    'payroll_period', p_payroll_period,
    'batch_id', p_batch_id,
    'monthly_deduction', coalesce(p_monthly_deduction, 0),
    'arrear_deduction', coalesce(p_arrear_deduction, 0)
  ));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_ptax_sync_deduction_to_payroll_internal.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;

create or replace function public.platform_apply_ptax_to_tenant(p_params jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.platform_try_uuid(p_params->>'tenant_id');
  v_template_version text := public.platform_ptax_module_template_version();
  v_dependency_result jsonb;
  v_apply_result jsonb;
  v_context jsonb;
  v_schema_name text;
begin
  if v_tenant_id is null then
    return public.platform_json_response(false,'TENANT_ID_REQUIRED','tenant_id is required.','{}'::jsonb);
  end if;

  v_dependency_result := public.platform_apply_wcm_core_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_ptax_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;

  v_dependency_result := public.platform_apply_payroll_core_to_tenant(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_ptax_to_tenant'));
  if coalesce((v_dependency_result->>'success')::boolean, false) is not true then return v_dependency_result; end if;

  v_apply_result := public.platform_apply_template_version_to_tenant(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'template_version', v_template_version,
    'source', coalesce(nullif(btrim(p_params->>'source'), ''), 'platform_apply_ptax_to_tenant')
  ));
  if coalesce((v_apply_result->>'success')::boolean, false) is not true then return v_apply_result; end if;

  v_context := public.platform_ptax_resolve_context(jsonb_build_object('tenant_id', v_tenant_id,'source', 'platform_apply_ptax_to_tenant'));
  if coalesce((v_context->>'success')::boolean, false) is not true then return v_context; end if;
  v_schema_name := v_context->'details'->>'tenant_schema';

  if not public.platform_table_exists(v_schema_name, 'wcm_ptax_configuration')
    or not public.platform_table_exists(v_schema_name, 'wcm_ptax_processing_batch')
    or not public.platform_table_exists(v_schema_name, 'wcm_ptax_monthly_ledger')
    or not public.platform_table_exists(v_schema_name, 'wcm_ptax_arrear_case')
  then
    return public.platform_json_response(false,'PTAX_TABLES_MISSING','Expected PTAX tenant tables were missing after template apply.',jsonb_build_object('tenant_schema', v_schema_name));
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_ptax_employee_state_profile'
      and c.conname = 'wcm_ptax_state_profile_employee_fk'
  ) then
    execute format('alter table %I.wcm_ptax_employee_state_profile add constraint wcm_ptax_state_profile_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_ptax_monthly_ledger'
      and c.conname = 'wcm_ptax_monthly_ledger_employee_fk'
  ) then
    execute format('alter table %I.wcm_ptax_monthly_ledger add constraint wcm_ptax_monthly_ledger_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_ptax_monthly_ledger'
      and c.conname = 'wcm_ptax_monthly_ledger_batch_fk'
  ) then
    execute format('alter table %I.wcm_ptax_monthly_ledger add constraint wcm_ptax_monthly_ledger_batch_fk foreign key (batch_id) references %I.wcm_ptax_processing_batch(batch_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_ptax_arrear_case'
      and c.conname = 'wcm_ptax_arrear_case_employee_fk'
  ) then
    execute format('alter table %I.wcm_ptax_arrear_case add constraint wcm_ptax_arrear_case_employee_fk foreign key (employee_id) references %I.wcm_employee(employee_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = v_schema_name
      and t.relname = 'wcm_ptax_arrear_computation'
      and c.conname = 'wcm_ptax_arrear_computation_case_fk'
  ) then
    execute format('alter table %I.wcm_ptax_arrear_computation add constraint wcm_ptax_arrear_computation_case_fk foreign key (arrear_case_id) references %I.wcm_ptax_arrear_case(arrear_case_id) on delete cascade', v_schema_name, v_schema_name);
  end if;

  return public.platform_json_response(true,'OK','PTAX applied to tenant schema.',jsonb_build_object('tenant_id', v_tenant_id,'tenant_schema', v_schema_name,'template_version', v_template_version));
exception when others then
  return public.platform_json_response(false,'UNEXPECTED_ERROR','Unexpected error in platform_apply_ptax_to_tenant.',jsonb_build_object('sqlstate', sqlstate,'sqlerrm', sqlerrm));
end;
$function$;;
