create or replace view public.platform_rm_rcm_requisition_catalog
with (security_invoker = true) as
select *
from public.platform_rcm_requisition_catalog_rows();

create or replace view public.platform_rm_rcm_candidate_pipeline
with (security_invoker = true) as
select *
from public.platform_rcm_candidate_pipeline_rows();

create or replace view public.platform_rm_rcm_conversion_queue
with (security_invoker = true) as
select *
from public.platform_rcm_conversion_queue_rows();

revoke all on public.rcm_requisition from public, anon, authenticated;
revoke all on public.rcm_candidate from public, anon, authenticated;
revoke all on public.rcm_job_application from public, anon, authenticated;
revoke all on public.rcm_application_stage_event from public, anon, authenticated;
revoke all on public.rcm_conversion_case from public, anon, authenticated;
revoke all on public.rcm_conversion_event_log from public, anon, authenticated;
revoke all on public.platform_rm_rcm_requisition_catalog from public, anon, authenticated;
revoke all on public.platform_rm_rcm_candidate_pipeline from public, anon, authenticated;
revoke all on public.platform_rm_rcm_conversion_queue from public, anon, authenticated;
revoke all on function public.platform_rcm_module_template_version() from public, anon, authenticated;
revoke all on function public.platform_rcm_try_date(text) from public, anon, authenticated;
revoke all on function public.platform_rcm_try_integer(text) from public, anon, authenticated;
revoke all on function public.platform_rcm_resolve_context(jsonb) from public, anon, authenticated;
revoke all on function public.platform_rcm_log_conversion_event_internal(text, uuid, text, jsonb, uuid) from public, anon, authenticated;
revoke all on function public.platform_apply_recruitment_and_conversion_to_tenant(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_rcm_requisition(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_rcm_candidate(jsonb) from public, anon, authenticated;
revoke all on function public.platform_register_rcm_job_application(jsonb) from public, anon, authenticated;
revoke all on function public.platform_transition_rcm_application_stage(jsonb) from public, anon, authenticated;
revoke all on function public.platform_prepare_rcm_conversion_contract(jsonb) from public, anon, authenticated;
revoke all on function public.platform_emit_rcm_conversion_billable_event(jsonb) from public, anon, authenticated;
revoke all on function public.platform_execute_rcm_conversion(jsonb) from public, anon, authenticated;
revoke all on function public.platform_rcm_requisition_catalog_rows() from public, anon, authenticated;
revoke all on function public.platform_rcm_candidate_pipeline_rows() from public, anon, authenticated;
revoke all on function public.platform_rcm_conversion_queue_rows() from public, anon, authenticated;

grant select on public.platform_rm_rcm_requisition_catalog to service_role;
grant select on public.platform_rm_rcm_candidate_pipeline to service_role;
grant select on public.platform_rm_rcm_conversion_queue to service_role;
grant execute on function public.platform_rcm_module_template_version() to service_role;
grant execute on function public.platform_apply_recruitment_and_conversion_to_tenant(jsonb) to service_role;
grant execute on function public.platform_register_rcm_requisition(jsonb) to service_role;
grant execute on function public.platform_register_rcm_candidate(jsonb) to service_role;
grant execute on function public.platform_register_rcm_job_application(jsonb) to service_role;
grant execute on function public.platform_transition_rcm_application_stage(jsonb) to service_role;
grant execute on function public.platform_prepare_rcm_conversion_contract(jsonb) to service_role;
grant execute on function public.platform_emit_rcm_conversion_billable_event(jsonb) to service_role;
grant execute on function public.platform_execute_rcm_conversion(jsonb) to service_role;
grant execute on function public.platform_rcm_requisition_catalog_rows() to service_role;
grant execute on function public.platform_rcm_candidate_pipeline_rows() to service_role;
grant execute on function public.platform_rcm_conversion_queue_rows() to service_role;

do $$
declare
  v_template_version text := public.platform_rcm_module_template_version();
  v_result jsonb;
begin
  v_result := public.platform_register_template_version(jsonb_build_object(
    'template_version', v_template_version,
    'template_scope', 'module',
    'template_status', 'released',
    'foundation_version', 'I06',
    'description', 'RECRUITMENT_AND_CONVERSION tenant-owned requisition, candidate, application, and conversion baseline.',
    'release_notes', jsonb_build_object(
      'slice', 'RECRUITMENT_AND_CONVERSION',
      'module_code', 'RECRUITMENT_AND_CONVERSION',
      'depends_on', jsonb_build_array('WCM_CORE', 'HIERARCHY', 'I03', 'F05'),
      'tenant_owned_tables', jsonb_build_array('rcm_requisition','rcm_candidate','rcm_job_application','rcm_application_stage_event','rcm_conversion_case','rcm_conversion_event_log')
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'RECRUITMENT_AND_CONVERSION template version registration failed: %', v_result::text;
  end if;

  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'RECRUITMENT_AND_CONVERSION','source_schema_name', 'public','source_table_name', 'rcm_requisition','target_table_name', 'rcm_requisition','clone_order', 300,'notes', jsonb_build_object('slice', 'RECRUITMENT_AND_CONVERSION', 'kind', 'tenant_owned_table')));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'RECRUITMENT_AND_CONVERSION requisition template registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'RECRUITMENT_AND_CONVERSION','source_schema_name', 'public','source_table_name', 'rcm_candidate','target_table_name', 'rcm_candidate','clone_order', 310,'notes', jsonb_build_object('slice', 'RECRUITMENT_AND_CONVERSION', 'kind', 'tenant_owned_table')));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'RECRUITMENT_AND_CONVERSION candidate template registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'RECRUITMENT_AND_CONVERSION','source_schema_name', 'public','source_table_name', 'rcm_job_application','target_table_name', 'rcm_job_application','clone_order', 320,'notes', jsonb_build_object('slice', 'RECRUITMENT_AND_CONVERSION', 'kind', 'tenant_owned_table')));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'RECRUITMENT_AND_CONVERSION application template registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'RECRUITMENT_AND_CONVERSION','source_schema_name', 'public','source_table_name', 'rcm_application_stage_event','target_table_name', 'rcm_application_stage_event','clone_order', 330,'notes', jsonb_build_object('slice', 'RECRUITMENT_AND_CONVERSION', 'kind', 'tenant_owned_table')));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'RECRUITMENT_AND_CONVERSION stage-event template registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'RECRUITMENT_AND_CONVERSION','source_schema_name', 'public','source_table_name', 'rcm_conversion_case','target_table_name', 'rcm_conversion_case','clone_order', 340,'notes', jsonb_build_object('slice', 'RECRUITMENT_AND_CONVERSION', 'kind', 'tenant_owned_table')));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'RECRUITMENT_AND_CONVERSION conversion-case template registration failed: %', v_result::text; end if;
  v_result := public.platform_register_template_table(jsonb_build_object('template_version', v_template_version,'module_code', 'RECRUITMENT_AND_CONVERSION','source_schema_name', 'public','source_table_name', 'rcm_conversion_event_log','target_table_name', 'rcm_conversion_event_log','clone_order', 350,'notes', jsonb_build_object('slice', 'RECRUITMENT_AND_CONVERSION', 'kind', 'tenant_owned_table')));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'RECRUITMENT_AND_CONVERSION conversion-event template registration failed: %', v_result::text; end if;
end $$;

do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_read_model(jsonb_build_object('read_model_code', 'rcm_requisition_catalog','module_code', 'RECRUITMENT_AND_CONVERSION','read_model_name', 'Recruitment Requisition Catalog','schema_placement', 'public','storage_kind', 'view','ownership_scope', 'platform_shared','object_name', 'platform_rm_rcm_requisition_catalog','refresh_strategy', 'none','refresh_mode', 'none','refresh_owner_code', 'RECRUITMENT_AND_CONVERSION','notes', 'Tenant-context recruitment requisition catalog.'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'Read-model registration failed for rcm_requisition_catalog: %', v_result::text; end if;
  v_result := public.platform_register_read_model(jsonb_build_object('read_model_code', 'rcm_candidate_pipeline','module_code', 'RECRUITMENT_AND_CONVERSION','read_model_name', 'Recruitment Candidate Pipeline','schema_placement', 'public','storage_kind', 'view','ownership_scope', 'platform_shared','object_name', 'platform_rm_rcm_candidate_pipeline','refresh_strategy', 'none','refresh_mode', 'none','refresh_owner_code', 'RECRUITMENT_AND_CONVERSION','notes', 'Tenant-context recruitment candidate pipeline view.'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'Read-model registration failed for rcm_candidate_pipeline: %', v_result::text; end if;
  v_result := public.platform_register_read_model(jsonb_build_object('read_model_code', 'rcm_conversion_queue','module_code', 'RECRUITMENT_AND_CONVERSION','read_model_name', 'Recruitment Conversion Queue','schema_placement', 'public','storage_kind', 'view','ownership_scope', 'platform_shared','object_name', 'platform_rm_rcm_conversion_queue','refresh_strategy', 'none','refresh_mode', 'none','refresh_owner_code', 'RECRUITMENT_AND_CONVERSION','notes', 'Tenant-context recruitment conversion queue view.'));
  if coalesce((v_result->>'success')::boolean, false) is not true then raise exception 'Read-model registration failed for rcm_conversion_queue: %', v_result::text; end if;
end $$;;
