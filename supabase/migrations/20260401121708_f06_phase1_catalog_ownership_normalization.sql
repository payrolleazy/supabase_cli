do $$
declare
  v_row record;
  v_result jsonb;
  v_registered_count integer := 0;
  v_expected_count integer := 87;
  v_uncataloged_count integer;
begin
  for v_row in
    with live_rm as (
      select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname like 'platform_rm_%'
        and c.relkind in ('v','m')
    ), cataloged as (
      select object_name
      from public.platform_read_model_catalog
      where schema_placement = 'public'
        and object_name like 'platform_rm_%'
    )
    select l.relname as object_name,
      case
        when l.relname in ('platform_rm_actor_access_overview','platform_rm_membership_invitation_overview','platform_rm_signup_request_status') then 'I01'
        when l.relname in ('platform_rm_actor_tenant_membership','platform_rm_tenant_registry') then 'platform_f01'
        when l.relname = 'platform_rm_client_provision_state' then 'I02'
        when l.relname = 'platform_rm_schema_provisioning' then 'platform_f02'
        when l.relname = 'platform_rm_gateway_operation_catalog' then 'I03'
        when l.relname in ('platform_rm_extensible_entity_catalog','platform_rm_extensible_attribute_catalog') then 'I04'
        when l.relname in ('platform_rm_storage_bucket_catalog','platform_rm_document_catalog','platform_rm_document_binding_catalog') then 'I05'
        when l.relname in ('platform_rm_exchange_contract_catalog','platform_rm_import_session_overview','platform_rm_import_validation_summary','platform_rm_export_job_overview','platform_rm_export_queue_health') then 'I06'
        when l.relname like 'platform_rm_agm_%' then 'AGM'
        when l.relname like 'platform_rm_ams_bio_%' then 'AMS_BIO'
        when l.relname like 'platform_rm_ams_%' then 'AMS_CORE'
        when l.relname like 'platform_rm_async_%' then 'platform_f04'
        when l.relname like 'platform_rm_eoap_%' then 'EOAP_AND_EMPLOYEE_ONBOARDING'
        when l.relname like 'platform_rm_esic_%' then 'ESIC'
        when l.relname like 'platform_rm_fbp_%' then 'FBP'
        when l.relname like 'platform_rm_hierarchy_%' then 'HIERARCHY'
        when l.relname like 'platform_rm_lms_%' then 'LMS'
        when l.relname like 'platform_rm_lwf_%' then 'LWF'
        when l.relname in ('platform_rm_payroll_area_catalog','platform_rm_pay_structure_catalog','platform_rm_employee_pay_structure_assignment','platform_rm_payroll_batch_catalog','platform_rm_payroll_result_summary','platform_rm_employee_payslip_history','platform_rm_payslip_run_status') then 'PAYROLL_CORE'
        when l.relname like 'platform_rm_pf_%' then 'PF'
        when l.relname like 'platform_rm_ptax_%' then 'PTAX'
        when l.relname like 'platform_rm_rcm_%' then 'RECRUITMENT_AND_CONVERSION'
        when l.relname = 'platform_rm_tenant_commercial_state' then 'platform_f05'
        when l.relname in ('platform_rm_refresh_overview','platform_rm_refresh_status') then 'platform_f06'
        when l.relname like 'platform_rm_tps_%' then 'TPS'
        when l.relname like 'platform_rm_wcm_%' then 'WCM_CORE'
        else null
      end as module_code
    from live_rm l
    left join cataloged c on c.object_name = l.relname
    where c.object_name is null
    order by l.relname
  loop
    if v_row.module_code is null then
      raise exception 'F06 Phase 1 found unmapped read model: %', v_row.object_name;
    end if;

    v_result := public.platform_register_read_model(jsonb_build_object(
      'read_model_code', replace(v_row.object_name, 'platform_rm_', ''),
      'module_code', v_row.module_code,
      'read_model_name', initcap(replace(replace(v_row.object_name, 'platform_rm_', ''), '_', ' ')),
      'schema_placement', 'public',
      'storage_kind', 'view',
      'ownership_scope', 'platform_shared',
      'object_name', v_row.object_name,
      'refresh_strategy', 'none',
      'refresh_mode', 'none',
      'refresh_owner_code', v_row.module_code,
      'notes', 'F06 Phase 1 catalog normalization.',
      'metadata', jsonb_build_object(
        'phase', 'F06_PHASE_1',
        'source', 'catalog_normalization',
        'object_name', v_row.object_name
      )
    ));

    if coalesce((v_result->>'success')::boolean, false) is not true then
      raise exception 'F06 Phase 1 registration failed for %: %', v_row.object_name, v_result::text;
    end if;

    v_registered_count := v_registered_count + 1;
  end loop;

  if v_registered_count <> v_expected_count then
    raise exception 'F06 Phase 1 expected to register % uncataloged read models, registered %.', v_expected_count, v_registered_count;
  end if;

  with live_rm as (
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname like 'platform_rm_%'
      and c.relkind in ('v','m')
  ), cataloged as (
    select object_name
    from public.platform_read_model_catalog
    where schema_placement = 'public'
      and object_name like 'platform_rm_%'
  )
  select count(*)::int
  into v_uncataloged_count
  from live_rm l
  left join cataloged c on c.object_name = l.relname
  where c.object_name is null;

  if v_uncataloged_count <> 0 then
    raise exception 'F06 Phase 1 incomplete: % uncataloged platform_rm_* surfaces remain.', v_uncataloged_count;
  end if;
end
$$;

