drop trigger if exists "trg_platform_access_role_set_updated_at" on "public"."platform_access_role";

drop trigger if exists "trg_platform_actor_profile_set_updated_at" on "public"."platform_actor_profile";

drop trigger if exists "trg_platform_actor_role_grant_set_updated_at" on "public"."platform_actor_role_grant";

drop trigger if exists "trg_platform_actor_tenant_membership_set_updated_at" on "public"."platform_actor_tenant_membership";

drop trigger if exists "trg_platform_async_job_set_updated_at" on "public"."platform_async_job";

drop trigger if exists "trg_platform_async_worker_registry_set_updated_at" on "public"."platform_async_worker_registry";

drop trigger if exists "trg_platform_billing_cycle_set_updated_at" on "public"."platform_billing_cycle";

drop trigger if exists "trg_platform_client_provision_request_set_updated_at" on "public"."platform_client_provision_request";

drop trigger if exists "trg_platform_client_purchase_checkout_set_updated_at" on "public"."platform_client_purchase_checkout";

drop trigger if exists "trg_platform_document_binding_set_updated_at" on "public"."platform_document_binding";

drop trigger if exists "trg_platform_document_class_set_updated_at" on "public"."platform_document_class";

drop trigger if exists "trg_platform_document_record_set_updated_at" on "public"."platform_document_record";

drop trigger if exists "trg_platform_document_upload_intent_set_updated_at" on "public"."platform_document_upload_intent";

drop trigger if exists "trg_platform_exchange_contract_set_updated_at" on "public"."platform_exchange_contract";

drop trigger if exists "trg_platform_export_artifact_set_updated_at" on "public"."platform_export_artifact";

drop trigger if exists "trg_platform_export_job_set_updated_at" on "public"."platform_export_job";

drop trigger if exists "trg_platform_export_policy_set_updated_at" on "public"."platform_export_policy";

drop trigger if exists "trg_platform_extensible_attribute_schema_set_updated_at" on "public"."platform_extensible_attribute_schema";

drop trigger if exists "trg_platform_extensible_entity_registry_set_updated_at" on "public"."platform_extensible_entity_registry";

drop trigger if exists "trg_platform_extensible_join_profile_set_updated_at" on "public"."platform_extensible_join_profile";

drop trigger if exists "trg_platform_extensible_schema_cache_set_updated_at" on "public"."platform_extensible_schema_cache";

drop trigger if exists "trg_platform_gateway_operation_set_updated_at" on "public"."platform_gateway_operation";

drop trigger if exists "trg_platform_import_run_set_updated_at" on "public"."platform_import_run";

drop trigger if exists "trg_platform_import_session_set_updated_at" on "public"."platform_import_session";

drop trigger if exists "trg_platform_import_staging_row_set_updated_at" on "public"."platform_import_staging_row";

drop trigger if exists "trg_platform_import_validation_summary_set_updated_at" on "public"."platform_import_validation_summary";

drop trigger if exists "trg_platform_invoice_set_updated_at" on "public"."platform_invoice";

drop trigger if exists "trg_platform_membership_invitation_set_updated_at" on "public"."platform_membership_invitation";

drop trigger if exists "trg_platform_owner_bootstrap_token_set_updated_at" on "public"."platform_owner_bootstrap_token";

drop trigger if exists "trg_platform_plan_catalog_set_updated_at" on "public"."platform_plan_catalog";

drop trigger if exists "trg_platform_plan_metric_rate_set_updated_at" on "public"."platform_plan_metric_rate";

drop trigger if exists "trg_platform_read_model_catalog_set_updated_at" on "public"."platform_read_model_catalog";

drop trigger if exists "trg_platform_read_model_refresh_run_set_updated_at" on "public"."platform_read_model_refresh_run";

drop trigger if exists "trg_platform_read_model_refresh_state_set_updated_at" on "public"."platform_read_model_refresh_state";

drop trigger if exists "trg_platform_signin_challenge_set_updated_at" on "public"."platform_signin_challenge";

drop trigger if exists "trg_platform_signin_policy_set_updated_at" on "public"."platform_signin_policy";

drop trigger if exists "trg_platform_signup_request_set_updated_at" on "public"."platform_signup_request";

drop trigger if exists "trg_platform_storage_bucket_catalog_set_updated_at" on "public"."platform_storage_bucket_catalog";

drop trigger if exists "trg_platform_template_table_registry_set_updated_at" on "public"."platform_template_table_registry";

drop trigger if exists "trg_platform_template_version_set_updated_at" on "public"."platform_template_version";

drop trigger if exists "trg_platform_tenant_set_updated_at" on "public"."platform_tenant";

drop trigger if exists "trg_platform_tenant_access_state_set_updated_at" on "public"."platform_tenant_access_state";

drop trigger if exists "trg_platform_tenant_commercial_account_set_updated_at" on "public"."platform_tenant_commercial_account";

drop trigger if exists "trg_platform_tenant_provisioning_set_updated_at" on "public"."platform_tenant_provisioning";

drop trigger if exists "trg_platform_tenant_subscription_set_updated_at" on "public"."platform_tenant_subscription";

drop trigger if exists "trg_platform_tenant_template_version_set_updated_at" on "public"."platform_tenant_template_version";

drop trigger if exists "trg_agm_badge_award_set_updated_at" on "tenant_eoaplive133052"."agm_badge_award";

drop trigger if exists "trg_agm_badge_catalog_set_updated_at" on "tenant_eoaplive133052"."agm_badge_catalog";

drop trigger if exists "trg_agm_recognition_event_set_updated_at" on "tenant_eoaplive133052"."agm_recognition_event";

drop trigger if exists "trg_agm_rule_set_set_updated_at" on "tenant_eoaplive133052"."agm_rule_set";

drop trigger if exists "trg_agm_user_preference_set_updated_at" on "tenant_eoaplive133052"."agm_user_preference";

drop trigger if exists "trg_agm_user_score_summary_set_updated_at" on "tenant_eoaplive133052"."agm_user_score_summary";

drop trigger if exists "trg_ams_attendance_configuration_set_updated_at" on "tenant_eoaplive133052"."ams_attendance_configuration";

drop trigger if exists "trg_agm_queue_refresh_on_ams_change" on "tenant_eoaplive133052"."ams_attendance_record";

drop trigger if exists "trg_ams_attendance_record_set_updated_at" on "tenant_eoaplive133052"."ams_attendance_record";

drop trigger if exists "trg_tps_mark_summary_stale_on_ams_change" on "tenant_eoaplive133052"."ams_attendance_record";

drop trigger if exists "trg_ams_bio_connector_set_updated_at" on "tenant_eoaplive133052"."ams_bio_connector";

drop trigger if exists "trg_ams_bio_device_set_updated_at" on "tenant_eoaplive133052"."ams_bio_device";

drop trigger if exists "trg_ams_bio_employee_mapping_set_updated_at" on "tenant_eoaplive133052"."ams_bio_employee_mapping";

drop trigger if exists "trg_ams_bio_field_mapping_profile_set_updated_at" on "tenant_eoaplive133052"."ams_bio_field_mapping_profile";

drop trigger if exists "trg_ams_bio_field_mapping_rule_set_updated_at" on "tenant_eoaplive133052"."ams_bio_field_mapping_rule";

drop trigger if exists "trg_ams_bio_import_run_set_updated_at" on "tenant_eoaplive133052"."ams_bio_import_run";

drop trigger if exists "trg_ams_bio_import_session_set_updated_at" on "tenant_eoaplive133052"."ams_bio_import_session";

drop trigger if exists "trg_ams_bio_import_staging_row_set_updated_at" on "tenant_eoaplive133052"."ams_bio_import_staging_row";

drop trigger if exists "trg_ams_bio_import_validation_summary_set_updated_at" on "tenant_eoaplive133052"."ams_bio_import_validation_summary";

drop trigger if exists "trg_ams_bio_normalized_punch_set_updated_at" on "tenant_eoaplive133052"."ams_bio_normalized_punch";

drop trigger if exists "trg_ams_bio_publish_log_set_updated_at" on "tenant_eoaplive133052"."ams_bio_publish_log";

drop trigger if exists "trg_ams_bio_raw_punch_log_set_updated_at" on "tenant_eoaplive133052"."ams_bio_raw_punch_log";

drop trigger if exists "trg_ams_bio_reconciliation_case_set_updated_at" on "tenant_eoaplive133052"."ams_bio_reconciliation_case";

drop trigger if exists "trg_ams_bio_source_onboarding_state_set_updated_at" on "tenant_eoaplive133052"."ams_bio_source_onboarding_state";

drop trigger if exists "trg_ams_bio_source_profile_set_updated_at" on "tenant_eoaplive133052"."ams_bio_source_profile";

drop trigger if exists "trg_ams_employee_schedule_set_updated_at" on "tenant_eoaplive133052"."ams_employee_schedule";

drop trigger if exists "trg_ams_geofence_set_updated_at" on "tenant_eoaplive133052"."ams_geofence";

drop trigger if exists "trg_ams_holiday_set_updated_at" on "tenant_eoaplive133052"."ams_holiday";

drop trigger if exists "trg_ams_punch_event_set_updated_at" on "tenant_eoaplive133052"."ams_punch_event";

drop trigger if exists "trg_ams_regularization_request_set_updated_at" on "tenant_eoaplive133052"."ams_regularization_request";

drop trigger if exists "trg_ams_shift_set_updated_at" on "tenant_eoaplive133052"."ams_shift";

drop trigger if exists "trg_hierarchy_position_assign_path" on "tenant_eoaplive133052"."hierarchy_position";

drop trigger if exists "trg_hierarchy_position_refresh_descendants" on "tenant_eoaplive133052"."hierarchy_position";

drop trigger if exists "trg_hierarchy_position_set_updated_at" on "tenant_eoaplive133052"."hierarchy_position";

drop trigger if exists "trg_hierarchy_position_group_set_updated_at" on "tenant_eoaplive133052"."hierarchy_position_group";

drop trigger if exists "trg_hierarchy_position_occupancy_set_updated_at" on "tenant_eoaplive133052"."hierarchy_position_occupancy";

drop trigger if exists "trg_lms_leave_policy_set_updated_at" on "tenant_eoaplive133052"."lms_leave_policy";

drop trigger if exists "trg_lms_leave_request_set_updated_at" on "tenant_eoaplive133052"."lms_leave_request";

drop trigger if exists "trg_lms_leave_type_set_updated_at" on "tenant_eoaplive133052"."lms_leave_type";

drop trigger if exists "trg_lms_ledger_consumption_set_updated_at" on "tenant_eoaplive133052"."lms_ledger_consumption";

drop trigger if exists "trg_lms_policy_assignment_set_updated_at" on "tenant_eoaplive133052"."lms_policy_assignment";

drop trigger if exists "trg_lms_tenant_configuration_set_updated_at" on "tenant_eoaplive133052"."lms_tenant_configuration";

drop trigger if exists "trg_rcm_candidate_set_updated_at" on "tenant_eoaplive133052"."rcm_candidate";

drop trigger if exists "trg_rcm_conversion_case_set_updated_at" on "tenant_eoaplive133052"."rcm_conversion_case";

drop trigger if exists "trg_rcm_job_application_set_updated_at" on "tenant_eoaplive133052"."rcm_job_application";

drop trigger if exists "trg_rcm_requisition_set_updated_at" on "tenant_eoaplive133052"."rcm_requisition";

drop trigger if exists "trg_tps_employee_period_summary_set_updated_at" on "tenant_eoaplive133052"."tps_employee_period_summary";

drop trigger if exists "trg_tps_processing_batch_set_updated_at" on "tenant_eoaplive133052"."tps_processing_batch";

drop trigger if exists "trg_wcm_component_set_updated_at" on "tenant_eoaplive133052"."wcm_component";

drop trigger if exists "trg_wcm_component_calculation_result_set_updated_at" on "tenant_eoaplive133052"."wcm_component_calculation_result";

drop trigger if exists "trg_wcm_component_rule_template_set_updated_at" on "tenant_eoaplive133052"."wcm_component_rule_template";

drop trigger if exists "trg_wcm_employee_set_updated_at" on "tenant_eoaplive133052"."wcm_employee";

drop trigger if exists "trg_wcm_employee_pay_structure_assignment_set_updated_at" on "tenant_eoaplive133052"."wcm_employee_pay_structure_assignment";

drop trigger if exists "trg_wcm_employee_service_state_set_updated_at" on "tenant_eoaplive133052"."wcm_employee_service_state";

drop trigger if exists "trg_wcm_pay_structure_set_updated_at" on "tenant_eoaplive133052"."wcm_pay_structure";

drop trigger if exists "trg_wcm_pay_structure_component_set_updated_at" on "tenant_eoaplive133052"."wcm_pay_structure_component";

drop trigger if exists "trg_wcm_pay_structure_version_set_updated_at" on "tenant_eoaplive133052"."wcm_pay_structure_version";

drop trigger if exists "trg_wcm_payroll_area_set_updated_at" on "tenant_eoaplive133052"."wcm_payroll_area";

drop trigger if exists "trg_wcm_payroll_batch_set_updated_at" on "tenant_eoaplive133052"."wcm_payroll_batch";

drop trigger if exists "trg_wcm_payroll_input_entry_set_updated_at" on "tenant_eoaplive133052"."wcm_payroll_input_entry";

drop trigger if exists "trg_wcm_payslip_item_set_updated_at" on "tenant_eoaplive133052"."wcm_payslip_item";

drop trigger if exists "trg_wcm_payslip_run_set_updated_at" on "tenant_eoaplive133052"."wcm_payslip_run";

drop trigger if exists "trg_wcm_preview_simulation_set_updated_at" on "tenant_eoaplive133052"."wcm_preview_simulation";

drop trigger if exists "trg_hierarchy_position_assign_path" on "tenant_sim_f03_tenant_b_572c752afe98461a"."hierarchy_position";

drop trigger if exists "trg_hierarchy_position_refresh_descendants" on "tenant_sim_f03_tenant_b_572c752afe98461a"."hierarchy_position";

drop trigger if exists "trg_hierarchy_position_set_updated_at" on "tenant_sim_f03_tenant_b_572c752afe98461a"."hierarchy_position";

drop trigger if exists "trg_hierarchy_position_group_set_updated_at" on "tenant_sim_f03_tenant_b_572c752afe98461a"."hierarchy_position_group";

drop trigger if exists "trg_hierarchy_position_occupancy_set_updated_at" on "tenant_sim_f03_tenant_b_572c752afe98461a"."hierarchy_position_occupancy";

drop trigger if exists "trg_rcm_candidate_set_updated_at" on "tenant_sim_f03_tenant_b_572c752afe98461a"."rcm_candidate";

drop trigger if exists "trg_rcm_conversion_case_set_updated_at" on "tenant_sim_f03_tenant_b_572c752afe98461a"."rcm_conversion_case";

drop trigger if exists "trg_rcm_job_application_set_updated_at" on "tenant_sim_f03_tenant_b_572c752afe98461a"."rcm_job_application";

drop trigger if exists "trg_rcm_requisition_set_updated_at" on "tenant_sim_f03_tenant_b_572c752afe98461a"."rcm_requisition";

drop trigger if exists "trg_wcm_employee_set_updated_at" on "tenant_sim_f03_tenant_b_572c752afe98461a"."wcm_employee";

drop trigger if exists "trg_wcm_employee_service_state_set_updated_at" on "tenant_sim_f03_tenant_b_572c752afe98461a"."wcm_employee_service_state";

alter table "public"."ams_bio_device" drop constraint "ams_bio_device_connector_id_fkey";

alter table "public"."ams_bio_field_mapping_profile" drop constraint "ams_bio_field_mapping_profile_source_profile_id_fkey";

alter table "public"."ams_bio_field_mapping_rule" drop constraint "ams_bio_field_mapping_rule_mapping_profile_id_fkey";

alter table "public"."ams_bio_import_run" drop constraint "ams_bio_import_run_import_session_id_fkey";

alter table "public"."ams_bio_import_run" drop constraint "ams_bio_import_run_source_profile_id_fkey";

alter table "public"."ams_bio_import_session" drop constraint "ams_bio_import_session_mapping_profile_id_fkey";

alter table "public"."ams_bio_import_session" drop constraint "ams_bio_import_session_source_profile_id_fkey";

alter table "public"."ams_bio_import_staging_row" drop constraint "ams_bio_import_staging_row_import_session_id_fkey";

alter table "public"."ams_bio_import_validation_summary" drop constraint "ams_bio_import_validation_summary_import_session_id_fkey";

alter table "public"."ams_bio_normalized_punch" drop constraint "ams_bio_normalized_punch_raw_punch_log_id_fkey";

alter table "public"."ams_bio_publish_log" drop constraint "ams_bio_publish_log_normalized_punch_id_fkey";

alter table "public"."ams_bio_raw_punch_log" drop constraint "ams_bio_raw_punch_log_connector_id_fkey";

alter table "public"."ams_bio_raw_punch_log" drop constraint "ams_bio_raw_punch_log_device_id_fkey";

alter table "public"."ams_bio_reconciliation_case" drop constraint "ams_bio_reconciliation_case_normalized_punch_id_fkey";

alter table "public"."ams_bio_source_onboarding_state" drop constraint "ams_bio_source_onboarding_state_source_profile_id_fkey";

alter table "public"."platform_actor_role_grant" drop constraint "platform_actor_role_grant_role_code_fkey";

alter table "public"."platform_actor_role_grant" drop constraint "platform_actor_role_grant_tenant_id_fkey";

alter table "public"."platform_actor_tenant_membership" drop constraint "platform_actor_tenant_membership_tenant_id_fkey";

alter table "public"."platform_async_job" drop constraint "platform_async_job_tenant_id_fkey";

alter table "public"."platform_async_job" drop constraint "platform_async_job_worker_code_fkey";

alter table "public"."platform_async_job_attempt" drop constraint "platform_async_job_attempt_job_id_fkey";

alter table "public"."platform_billable_unit_ledger" drop constraint "platform_billable_unit_ledger_billing_cycle_id_fkey";

alter table "public"."platform_billable_unit_ledger" drop constraint "platform_billable_unit_ledger_invoice_id_fkey";

alter table "public"."platform_billable_unit_ledger" drop constraint "platform_billable_unit_ledger_reversal_of_id_fkey";

alter table "public"."platform_billable_unit_ledger" drop constraint "platform_billable_unit_ledger_tenant_id_fkey";

alter table "public"."platform_billing_cycle" drop constraint "platform_billing_cycle_subscription_id_fkey";

alter table "public"."platform_billing_cycle" drop constraint "platform_billing_cycle_tenant_id_fkey";

alter table "public"."platform_client_provision_event" drop constraint "platform_client_provision_event_provision_request_id_fkey";

alter table "public"."platform_client_provision_request" drop constraint "platform_client_provision_request_tenant_id_fkey";

alter table "public"."platform_client_purchase_checkout" drop constraint "platform_client_purchase_checkout_provision_request_id_fkey";

alter table "public"."platform_client_purchase_event" drop constraint "platform_client_purchase_event_checkout_id_fkey";

alter table "public"."platform_client_purchase_event" drop constraint "platform_client_purchase_event_provision_request_id_fkey";

alter table "public"."platform_document_binding" drop constraint "platform_document_binding_document_id_fkey";

alter table "public"."platform_document_binding" drop constraint "platform_document_binding_tenant_id_fkey";

alter table "public"."platform_document_class" drop constraint "platform_document_class_default_bucket_code_fkey";

alter table "public"."platform_document_event_log" drop constraint "platform_document_event_log_document_id_fkey";

alter table "public"."platform_document_event_log" drop constraint "platform_document_event_log_tenant_id_fkey";

alter table "public"."platform_document_event_log" drop constraint "platform_document_event_log_upload_intent_id_fkey";

alter table "public"."platform_document_record" drop constraint "platform_document_record_bucket_code_fkey";

alter table "public"."platform_document_record" drop constraint "platform_document_record_document_class_id_fkey";

alter table "public"."platform_document_record" drop constraint "platform_document_record_superseded_by_document_id_fkey";

alter table "public"."platform_document_record" drop constraint "platform_document_record_tenant_id_fkey";

alter table "public"."platform_document_record" drop constraint "platform_document_record_upload_intent_id_fkey";

alter table "public"."platform_document_upload_intent" drop constraint "platform_document_upload_intent_bucket_code_fkey";

alter table "public"."platform_document_upload_intent" drop constraint "platform_document_upload_intent_document_class_id_fkey";

alter table "public"."platform_document_upload_intent" drop constraint "platform_document_upload_intent_tenant_id_fkey";

alter table "public"."platform_exchange_contract" drop constraint "platform_exchange_contract_artifact_bucket_code_fkey";

alter table "public"."platform_exchange_contract" drop constraint "platform_exchange_contract_artifact_document_class_code_fkey";

alter table "public"."platform_exchange_contract" drop constraint "platform_exchange_contract_entity_id_fkey";

alter table "public"."platform_exchange_contract" drop constraint "platform_exchange_contract_upload_document_class_code_fkey";

alter table "public"."platform_exchange_contract" drop constraint "platform_exchange_contract_worker_code_fkey";

alter table "public"."platform_export_artifact" drop constraint "platform_export_artifact_bucket_code_fkey";

alter table "public"."platform_export_artifact" drop constraint "platform_export_artifact_contract_id_fkey";

alter table "public"."platform_export_artifact" drop constraint "platform_export_artifact_document_id_fkey";

alter table "public"."platform_export_artifact" drop constraint "platform_export_artifact_export_job_id_fkey";

alter table "public"."platform_export_artifact" drop constraint "platform_export_artifact_tenant_id_fkey";

alter table "public"."platform_export_event_log" drop constraint "platform_export_event_log_contract_id_fkey";

alter table "public"."platform_export_event_log" drop constraint "platform_export_event_log_export_job_id_fkey";

alter table "public"."platform_export_event_log" drop constraint "platform_export_event_log_tenant_id_fkey";

alter table "public"."platform_export_job" drop constraint "platform_export_job_artifact_document_id_fkey";

alter table "public"."platform_export_job" drop constraint "platform_export_job_contract_id_fkey";

alter table "public"."platform_export_job" drop constraint "platform_export_job_job_id_fkey";

alter table "public"."platform_export_job" drop constraint "platform_export_job_tenant_id_fkey";

alter table "public"."platform_export_policy" drop constraint "platform_export_policy_contract_id_fkey";

alter table "public"."platform_extensible_attribute_schema" drop constraint "platform_extensible_attribute_schema_entity_id_fkey";

alter table "public"."platform_extensible_attribute_schema" drop constraint "platform_extensible_attribute_schema_tenant_id_fkey";

alter table "public"."platform_extensible_join_profile" drop constraint "platform_extensible_join_profile_entity_id_fkey";

alter table "public"."platform_extensible_join_profile" drop constraint "platform_extensible_join_profile_tenant_id_fkey";

alter table "public"."platform_extensible_schema_cache" drop constraint "platform_extensible_schema_cache_entity_id_fkey";

alter table "public"."platform_extensible_schema_cache" drop constraint "platform_extensible_schema_cache_tenant_id_fkey";

alter table "public"."platform_gateway_idempotency_claim" drop constraint "platform_gateway_idempotency_claim_operation_code_fkey";

alter table "public"."platform_gateway_idempotency_claim" drop constraint "platform_gateway_idempotency_claim_tenant_id_fkey";

alter table "public"."platform_gateway_operation_role" drop constraint "platform_gateway_operation_role_operation_code_fkey";

alter table "public"."platform_gateway_operation_role" drop constraint "platform_gateway_operation_role_role_code_fkey";

alter table "public"."platform_gateway_request_log" drop constraint "platform_gateway_request_log_tenant_id_fkey";

alter table "public"."platform_import_run" drop constraint "platform_import_run_contract_id_fkey";

alter table "public"."platform_import_run" drop constraint "platform_import_run_import_session_id_fkey";

alter table "public"."platform_import_run" drop constraint "platform_import_run_job_id_fkey";

alter table "public"."platform_import_run" drop constraint "platform_import_run_tenant_id_fkey";

alter table "public"."platform_import_session" drop constraint "platform_import_session_contract_id_fkey";

alter table "public"."platform_import_session" drop constraint "platform_import_session_source_document_id_fkey";

alter table "public"."platform_import_session" drop constraint "platform_import_session_tenant_id_fkey";

alter table "public"."platform_import_session" drop constraint "platform_import_session_upload_intent_id_fkey";

alter table "public"."platform_import_staging_row" drop constraint "platform_import_staging_row_import_session_id_fkey";

alter table "public"."platform_import_staging_row" drop constraint "platform_import_staging_row_tenant_id_fkey";

alter table "public"."platform_import_validation_summary" drop constraint "platform_import_validation_summary_import_session_id_fkey";

alter table "public"."platform_import_validation_summary" drop constraint "platform_import_validation_summary_tenant_id_fkey";

alter table "public"."platform_invoice" drop constraint "platform_invoice_billing_cycle_id_fkey";

alter table "public"."platform_invoice" drop constraint "platform_invoice_tenant_id_fkey";

alter table "public"."platform_membership_invitation" drop constraint "platform_membership_invitation_role_code_fkey";

alter table "public"."platform_membership_invitation" drop constraint "platform_membership_invitation_tenant_id_fkey";

alter table "public"."platform_owner_bootstrap_token" drop constraint "platform_owner_bootstrap_token_provision_request_id_fkey";

alter table "public"."platform_payment_receipt" drop constraint "platform_payment_receipt_invoice_id_fkey";

alter table "public"."platform_payment_receipt" drop constraint "platform_payment_receipt_tenant_id_fkey";

alter table "public"."platform_plan_metric_rate" drop constraint "platform_plan_metric_rate_plan_id_fkey";

alter table "public"."platform_read_model_refresh_run" drop constraint "platform_read_model_refresh_run_async_job_id_fkey";

alter table "public"."platform_read_model_refresh_run" drop constraint "platform_read_model_refresh_run_read_model_code_fkey";

alter table "public"."platform_read_model_refresh_run" drop constraint "platform_read_model_refresh_run_tenant_id_fkey";

alter table "public"."platform_read_model_refresh_state" drop constraint "platform_read_model_refresh_state_read_model_code_fkey";

alter table "public"."platform_read_model_refresh_state" drop constraint "platform_read_model_refresh_state_tenant_id_fkey";

alter table "public"."platform_schema_provisioning_run" drop constraint "platform_schema_provisioning_run_tenant_id_fkey";

alter table "public"."platform_signin_challenge" drop constraint "platform_signin_challenge_policy_code_fkey";

alter table "public"."platform_signup_request" drop constraint "platform_signup_request_async_job_id_fkey";

alter table "public"."platform_signup_request" drop constraint "platform_signup_request_invitation_id_fkey";

alter table "public"."platform_template_table_registry" drop constraint "platform_template_table_registry_template_version_fkey";

alter table "public"."platform_tenant_access_state" drop constraint "platform_tenant_access_state_tenant_id_fkey";

alter table "public"."platform_tenant_commercial_account" drop constraint "platform_tenant_commercial_account_tenant_id_fkey";

alter table "public"."platform_tenant_provisioning" drop constraint "platform_tenant_provisioning_tenant_id_fkey";

alter table "public"."platform_tenant_status_history" drop constraint "platform_tenant_status_history_tenant_id_fkey";

alter table "public"."platform_tenant_subscription" drop constraint "platform_tenant_subscription_plan_id_fkey";

alter table "public"."platform_tenant_subscription" drop constraint "platform_tenant_subscription_tenant_id_fkey";

alter table "public"."platform_tenant_template_version" drop constraint "platform_tenant_template_version_run_id_fkey";

alter table "public"."platform_tenant_template_version" drop constraint "platform_tenant_template_version_template_version_fkey";

alter table "public"."platform_tenant_template_version" drop constraint "platform_tenant_template_version_tenant_id_fkey";

alter table "public"."wcm_fbp_claim_document_binding" drop constraint "wcm_fbp_claim_document_binding_document_id_fkey";

alter table "tenant_eoaplive133052"."ams_bio_import_session" drop constraint "ams_bio_import_session_source_document_fk";

alter table "tenant_eoaplive133052"."ams_regularization_request" drop constraint "ams_regularization_request_supporting_document_fk";

alter table "tenant_eoaplive133052"."lms_leave_request" drop constraint "lms_leave_request_supporting_document_fk";

alter table "tenant_eoaplive133052"."wcm_payslip_item" drop constraint "wcm_payslip_item_document_fk";

drop materialized view if exists "public"."platform_rm_refresh_overview";

alter table "public"."hierarchy_position" alter column "hierarchy_path" set data type public.ltree using "hierarchy_path"::public.ltree;

alter table "tenant_eoaplive133052"."hierarchy_position" alter column "hierarchy_path" set data type public.ltree using "hierarchy_path"::public.ltree;

alter table "tenant_sim_f03_tenant_b_572c752afe98461a"."hierarchy_position" alter column "hierarchy_path" set data type public.ltree using "hierarchy_path"::public.ltree;

alter table "public"."ams_bio_device" add constraint "ams_bio_device_connector_id_fkey" FOREIGN KEY (connector_id) REFERENCES public.ams_bio_connector(connector_id) not valid;

alter table "public"."ams_bio_device" validate constraint "ams_bio_device_connector_id_fkey";

alter table "public"."ams_bio_field_mapping_profile" add constraint "ams_bio_field_mapping_profile_source_profile_id_fkey" FOREIGN KEY (source_profile_id) REFERENCES public.ams_bio_source_profile(source_profile_id) not valid;

alter table "public"."ams_bio_field_mapping_profile" validate constraint "ams_bio_field_mapping_profile_source_profile_id_fkey";

alter table "public"."ams_bio_field_mapping_rule" add constraint "ams_bio_field_mapping_rule_mapping_profile_id_fkey" FOREIGN KEY (mapping_profile_id) REFERENCES public.ams_bio_field_mapping_profile(mapping_profile_id) ON DELETE CASCADE not valid;

alter table "public"."ams_bio_field_mapping_rule" validate constraint "ams_bio_field_mapping_rule_mapping_profile_id_fkey";

alter table "public"."ams_bio_import_run" add constraint "ams_bio_import_run_import_session_id_fkey" FOREIGN KEY (import_session_id) REFERENCES public.ams_bio_import_session(import_session_id) not valid;

alter table "public"."ams_bio_import_run" validate constraint "ams_bio_import_run_import_session_id_fkey";

alter table "public"."ams_bio_import_run" add constraint "ams_bio_import_run_source_profile_id_fkey" FOREIGN KEY (source_profile_id) REFERENCES public.ams_bio_source_profile(source_profile_id) not valid;

alter table "public"."ams_bio_import_run" validate constraint "ams_bio_import_run_source_profile_id_fkey";

alter table "public"."ams_bio_import_session" add constraint "ams_bio_import_session_mapping_profile_id_fkey" FOREIGN KEY (mapping_profile_id) REFERENCES public.ams_bio_field_mapping_profile(mapping_profile_id) not valid;

alter table "public"."ams_bio_import_session" validate constraint "ams_bio_import_session_mapping_profile_id_fkey";

alter table "public"."ams_bio_import_session" add constraint "ams_bio_import_session_source_profile_id_fkey" FOREIGN KEY (source_profile_id) REFERENCES public.ams_bio_source_profile(source_profile_id) not valid;

alter table "public"."ams_bio_import_session" validate constraint "ams_bio_import_session_source_profile_id_fkey";

alter table "public"."ams_bio_import_staging_row" add constraint "ams_bio_import_staging_row_import_session_id_fkey" FOREIGN KEY (import_session_id) REFERENCES public.ams_bio_import_session(import_session_id) ON DELETE CASCADE not valid;

alter table "public"."ams_bio_import_staging_row" validate constraint "ams_bio_import_staging_row_import_session_id_fkey";

alter table "public"."ams_bio_import_validation_summary" add constraint "ams_bio_import_validation_summary_import_session_id_fkey" FOREIGN KEY (import_session_id) REFERENCES public.ams_bio_import_session(import_session_id) ON DELETE CASCADE not valid;

alter table "public"."ams_bio_import_validation_summary" validate constraint "ams_bio_import_validation_summary_import_session_id_fkey";

alter table "public"."ams_bio_normalized_punch" add constraint "ams_bio_normalized_punch_raw_punch_log_id_fkey" FOREIGN KEY (raw_punch_log_id) REFERENCES public.ams_bio_raw_punch_log(raw_punch_log_id) ON DELETE CASCADE not valid;

alter table "public"."ams_bio_normalized_punch" validate constraint "ams_bio_normalized_punch_raw_punch_log_id_fkey";

alter table "public"."ams_bio_publish_log" add constraint "ams_bio_publish_log_normalized_punch_id_fkey" FOREIGN KEY (normalized_punch_id) REFERENCES public.ams_bio_normalized_punch(normalized_punch_id) ON DELETE CASCADE not valid;

alter table "public"."ams_bio_publish_log" validate constraint "ams_bio_publish_log_normalized_punch_id_fkey";

alter table "public"."ams_bio_raw_punch_log" add constraint "ams_bio_raw_punch_log_connector_id_fkey" FOREIGN KEY (connector_id) REFERENCES public.ams_bio_connector(connector_id) not valid;

alter table "public"."ams_bio_raw_punch_log" validate constraint "ams_bio_raw_punch_log_connector_id_fkey";

alter table "public"."ams_bio_raw_punch_log" add constraint "ams_bio_raw_punch_log_device_id_fkey" FOREIGN KEY (device_id) REFERENCES public.ams_bio_device(device_id) not valid;

alter table "public"."ams_bio_raw_punch_log" validate constraint "ams_bio_raw_punch_log_device_id_fkey";

alter table "public"."ams_bio_reconciliation_case" add constraint "ams_bio_reconciliation_case_normalized_punch_id_fkey" FOREIGN KEY (normalized_punch_id) REFERENCES public.ams_bio_normalized_punch(normalized_punch_id) ON DELETE SET NULL not valid;

alter table "public"."ams_bio_reconciliation_case" validate constraint "ams_bio_reconciliation_case_normalized_punch_id_fkey";

alter table "public"."ams_bio_source_onboarding_state" add constraint "ams_bio_source_onboarding_state_source_profile_id_fkey" FOREIGN KEY (source_profile_id) REFERENCES public.ams_bio_source_profile(source_profile_id) not valid;

alter table "public"."ams_bio_source_onboarding_state" validate constraint "ams_bio_source_onboarding_state_source_profile_id_fkey";

alter table "public"."platform_actor_role_grant" add constraint "platform_actor_role_grant_role_code_fkey" FOREIGN KEY (role_code) REFERENCES public.platform_access_role(role_code) not valid;

alter table "public"."platform_actor_role_grant" validate constraint "platform_actor_role_grant_role_code_fkey";

alter table "public"."platform_actor_role_grant" add constraint "platform_actor_role_grant_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_actor_role_grant" validate constraint "platform_actor_role_grant_tenant_id_fkey";

alter table "public"."platform_actor_tenant_membership" add constraint "platform_actor_tenant_membership_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_actor_tenant_membership" validate constraint "platform_actor_tenant_membership_tenant_id_fkey";

alter table "public"."platform_async_job" add constraint "platform_async_job_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_async_job" validate constraint "platform_async_job_tenant_id_fkey";

alter table "public"."platform_async_job" add constraint "platform_async_job_worker_code_fkey" FOREIGN KEY (worker_code) REFERENCES public.platform_async_worker_registry(worker_code) not valid;

alter table "public"."platform_async_job" validate constraint "platform_async_job_worker_code_fkey";

alter table "public"."platform_async_job_attempt" add constraint "platform_async_job_attempt_job_id_fkey" FOREIGN KEY (job_id) REFERENCES public.platform_async_job(job_id) ON DELETE CASCADE not valid;

alter table "public"."platform_async_job_attempt" validate constraint "platform_async_job_attempt_job_id_fkey";

alter table "public"."platform_billable_unit_ledger" add constraint "platform_billable_unit_ledger_billing_cycle_id_fkey" FOREIGN KEY (billing_cycle_id) REFERENCES public.platform_billing_cycle(id) ON DELETE SET NULL not valid;

alter table "public"."platform_billable_unit_ledger" validate constraint "platform_billable_unit_ledger_billing_cycle_id_fkey";

alter table "public"."platform_billable_unit_ledger" add constraint "platform_billable_unit_ledger_invoice_id_fkey" FOREIGN KEY (invoice_id) REFERENCES public.platform_invoice(id) ON DELETE SET NULL not valid;

alter table "public"."platform_billable_unit_ledger" validate constraint "platform_billable_unit_ledger_invoice_id_fkey";

alter table "public"."platform_billable_unit_ledger" add constraint "platform_billable_unit_ledger_reversal_of_id_fkey" FOREIGN KEY (reversal_of_id) REFERENCES public.platform_billable_unit_ledger(id) ON DELETE SET NULL not valid;

alter table "public"."platform_billable_unit_ledger" validate constraint "platform_billable_unit_ledger_reversal_of_id_fkey";

alter table "public"."platform_billable_unit_ledger" add constraint "platform_billable_unit_ledger_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_billable_unit_ledger" validate constraint "platform_billable_unit_ledger_tenant_id_fkey";

alter table "public"."platform_billing_cycle" add constraint "platform_billing_cycle_subscription_id_fkey" FOREIGN KEY (subscription_id) REFERENCES public.platform_tenant_subscription(id) ON DELETE RESTRICT not valid;

alter table "public"."platform_billing_cycle" validate constraint "platform_billing_cycle_subscription_id_fkey";

alter table "public"."platform_billing_cycle" add constraint "platform_billing_cycle_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_billing_cycle" validate constraint "platform_billing_cycle_tenant_id_fkey";

alter table "public"."platform_client_provision_event" add constraint "platform_client_provision_event_provision_request_id_fkey" FOREIGN KEY (provision_request_id) REFERENCES public.platform_client_provision_request(provision_request_id) ON DELETE CASCADE not valid;

alter table "public"."platform_client_provision_event" validate constraint "platform_client_provision_event_provision_request_id_fkey";

alter table "public"."platform_client_provision_request" add constraint "platform_client_provision_request_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE SET NULL not valid;

alter table "public"."platform_client_provision_request" validate constraint "platform_client_provision_request_tenant_id_fkey";

alter table "public"."platform_client_purchase_checkout" add constraint "platform_client_purchase_checkout_provision_request_id_fkey" FOREIGN KEY (provision_request_id) REFERENCES public.platform_client_provision_request(provision_request_id) ON DELETE CASCADE not valid;

alter table "public"."platform_client_purchase_checkout" validate constraint "platform_client_purchase_checkout_provision_request_id_fkey";

alter table "public"."platform_client_purchase_event" add constraint "platform_client_purchase_event_checkout_id_fkey" FOREIGN KEY (checkout_id) REFERENCES public.platform_client_purchase_checkout(checkout_id) ON DELETE CASCADE not valid;

alter table "public"."platform_client_purchase_event" validate constraint "platform_client_purchase_event_checkout_id_fkey";

alter table "public"."platform_client_purchase_event" add constraint "platform_client_purchase_event_provision_request_id_fkey" FOREIGN KEY (provision_request_id) REFERENCES public.platform_client_provision_request(provision_request_id) ON DELETE CASCADE not valid;

alter table "public"."platform_client_purchase_event" validate constraint "platform_client_purchase_event_provision_request_id_fkey";

alter table "public"."platform_document_binding" add constraint "platform_document_binding_document_id_fkey" FOREIGN KEY (document_id) REFERENCES public.platform_document_record(document_id) ON DELETE CASCADE not valid;

alter table "public"."platform_document_binding" validate constraint "platform_document_binding_document_id_fkey";

alter table "public"."platform_document_binding" add constraint "platform_document_binding_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_document_binding" validate constraint "platform_document_binding_tenant_id_fkey";

alter table "public"."platform_document_class" add constraint "platform_document_class_default_bucket_code_fkey" FOREIGN KEY (default_bucket_code) REFERENCES public.platform_storage_bucket_catalog(bucket_code) ON DELETE RESTRICT not valid;

alter table "public"."platform_document_class" validate constraint "platform_document_class_default_bucket_code_fkey";

alter table "public"."platform_document_event_log" add constraint "platform_document_event_log_document_id_fkey" FOREIGN KEY (document_id) REFERENCES public.platform_document_record(document_id) ON DELETE SET NULL not valid;

alter table "public"."platform_document_event_log" validate constraint "platform_document_event_log_document_id_fkey";

alter table "public"."platform_document_event_log" add constraint "platform_document_event_log_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE SET NULL not valid;

alter table "public"."platform_document_event_log" validate constraint "platform_document_event_log_tenant_id_fkey";

alter table "public"."platform_document_event_log" add constraint "platform_document_event_log_upload_intent_id_fkey" FOREIGN KEY (upload_intent_id) REFERENCES public.platform_document_upload_intent(upload_intent_id) ON DELETE SET NULL not valid;

alter table "public"."platform_document_event_log" validate constraint "platform_document_event_log_upload_intent_id_fkey";

alter table "public"."platform_document_record" add constraint "platform_document_record_bucket_code_fkey" FOREIGN KEY (bucket_code) REFERENCES public.platform_storage_bucket_catalog(bucket_code) ON DELETE RESTRICT not valid;

alter table "public"."platform_document_record" validate constraint "platform_document_record_bucket_code_fkey";

alter table "public"."platform_document_record" add constraint "platform_document_record_document_class_id_fkey" FOREIGN KEY (document_class_id) REFERENCES public.platform_document_class(document_class_id) ON DELETE RESTRICT not valid;

alter table "public"."platform_document_record" validate constraint "platform_document_record_document_class_id_fkey";

alter table "public"."platform_document_record" add constraint "platform_document_record_superseded_by_document_id_fkey" FOREIGN KEY (superseded_by_document_id) REFERENCES public.platform_document_record(document_id) ON DELETE SET NULL not valid;

alter table "public"."platform_document_record" validate constraint "platform_document_record_superseded_by_document_id_fkey";

alter table "public"."platform_document_record" add constraint "platform_document_record_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_document_record" validate constraint "platform_document_record_tenant_id_fkey";

alter table "public"."platform_document_record" add constraint "platform_document_record_upload_intent_id_fkey" FOREIGN KEY (upload_intent_id) REFERENCES public.platform_document_upload_intent(upload_intent_id) ON DELETE SET NULL not valid;

alter table "public"."platform_document_record" validate constraint "platform_document_record_upload_intent_id_fkey";

alter table "public"."platform_document_upload_intent" add constraint "platform_document_upload_intent_bucket_code_fkey" FOREIGN KEY (bucket_code) REFERENCES public.platform_storage_bucket_catalog(bucket_code) ON DELETE RESTRICT not valid;

alter table "public"."platform_document_upload_intent" validate constraint "platform_document_upload_intent_bucket_code_fkey";

alter table "public"."platform_document_upload_intent" add constraint "platform_document_upload_intent_document_class_id_fkey" FOREIGN KEY (document_class_id) REFERENCES public.platform_document_class(document_class_id) ON DELETE RESTRICT not valid;

alter table "public"."platform_document_upload_intent" validate constraint "platform_document_upload_intent_document_class_id_fkey";

alter table "public"."platform_document_upload_intent" add constraint "platform_document_upload_intent_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_document_upload_intent" validate constraint "platform_document_upload_intent_tenant_id_fkey";

alter table "public"."platform_exchange_contract" add constraint "platform_exchange_contract_artifact_bucket_code_fkey" FOREIGN KEY (artifact_bucket_code) REFERENCES public.platform_storage_bucket_catalog(bucket_code) ON DELETE RESTRICT not valid;

alter table "public"."platform_exchange_contract" validate constraint "platform_exchange_contract_artifact_bucket_code_fkey";

alter table "public"."platform_exchange_contract" add constraint "platform_exchange_contract_artifact_document_class_code_fkey" FOREIGN KEY (artifact_document_class_code) REFERENCES public.platform_document_class(document_class_code) ON DELETE RESTRICT not valid;

alter table "public"."platform_exchange_contract" validate constraint "platform_exchange_contract_artifact_document_class_code_fkey";

alter table "public"."platform_exchange_contract" add constraint "platform_exchange_contract_entity_id_fkey" FOREIGN KEY (entity_id) REFERENCES public.platform_extensible_entity_registry(entity_id) ON DELETE RESTRICT not valid;

alter table "public"."platform_exchange_contract" validate constraint "platform_exchange_contract_entity_id_fkey";

alter table "public"."platform_exchange_contract" add constraint "platform_exchange_contract_upload_document_class_code_fkey" FOREIGN KEY (upload_document_class_code) REFERENCES public.platform_document_class(document_class_code) ON DELETE RESTRICT not valid;

alter table "public"."platform_exchange_contract" validate constraint "platform_exchange_contract_upload_document_class_code_fkey";

alter table "public"."platform_exchange_contract" add constraint "platform_exchange_contract_worker_code_fkey" FOREIGN KEY (worker_code) REFERENCES public.platform_async_worker_registry(worker_code) ON DELETE RESTRICT not valid;

alter table "public"."platform_exchange_contract" validate constraint "platform_exchange_contract_worker_code_fkey";

alter table "public"."platform_export_artifact" add constraint "platform_export_artifact_bucket_code_fkey" FOREIGN KEY (bucket_code) REFERENCES public.platform_storage_bucket_catalog(bucket_code) ON DELETE RESTRICT not valid;

alter table "public"."platform_export_artifact" validate constraint "platform_export_artifact_bucket_code_fkey";

alter table "public"."platform_export_artifact" add constraint "platform_export_artifact_contract_id_fkey" FOREIGN KEY (contract_id) REFERENCES public.platform_exchange_contract(contract_id) ON DELETE RESTRICT not valid;

alter table "public"."platform_export_artifact" validate constraint "platform_export_artifact_contract_id_fkey";

alter table "public"."platform_export_artifact" add constraint "platform_export_artifact_document_id_fkey" FOREIGN KEY (document_id) REFERENCES public.platform_document_record(document_id) ON DELETE SET NULL not valid;

alter table "public"."platform_export_artifact" validate constraint "platform_export_artifact_document_id_fkey";

alter table "public"."platform_export_artifact" add constraint "platform_export_artifact_export_job_id_fkey" FOREIGN KEY (export_job_id) REFERENCES public.platform_export_job(export_job_id) ON DELETE CASCADE not valid;

alter table "public"."platform_export_artifact" validate constraint "platform_export_artifact_export_job_id_fkey";

alter table "public"."platform_export_artifact" add constraint "platform_export_artifact_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_export_artifact" validate constraint "platform_export_artifact_tenant_id_fkey";

alter table "public"."platform_export_event_log" add constraint "platform_export_event_log_contract_id_fkey" FOREIGN KEY (contract_id) REFERENCES public.platform_exchange_contract(contract_id) ON DELETE SET NULL not valid;

alter table "public"."platform_export_event_log" validate constraint "platform_export_event_log_contract_id_fkey";

alter table "public"."platform_export_event_log" add constraint "platform_export_event_log_export_job_id_fkey" FOREIGN KEY (export_job_id) REFERENCES public.platform_export_job(export_job_id) ON DELETE SET NULL not valid;

alter table "public"."platform_export_event_log" validate constraint "platform_export_event_log_export_job_id_fkey";

alter table "public"."platform_export_event_log" add constraint "platform_export_event_log_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE SET NULL not valid;

alter table "public"."platform_export_event_log" validate constraint "platform_export_event_log_tenant_id_fkey";

alter table "public"."platform_export_job" add constraint "platform_export_job_artifact_document_id_fkey" FOREIGN KEY (artifact_document_id) REFERENCES public.platform_document_record(document_id) ON DELETE SET NULL not valid;

alter table "public"."platform_export_job" validate constraint "platform_export_job_artifact_document_id_fkey";

alter table "public"."platform_export_job" add constraint "platform_export_job_contract_id_fkey" FOREIGN KEY (contract_id) REFERENCES public.platform_exchange_contract(contract_id) ON DELETE RESTRICT not valid;

alter table "public"."platform_export_job" validate constraint "platform_export_job_contract_id_fkey";

alter table "public"."platform_export_job" add constraint "platform_export_job_job_id_fkey" FOREIGN KEY (job_id) REFERENCES public.platform_async_job(job_id) ON DELETE SET NULL not valid;

alter table "public"."platform_export_job" validate constraint "platform_export_job_job_id_fkey";

alter table "public"."platform_export_job" add constraint "platform_export_job_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_export_job" validate constraint "platform_export_job_tenant_id_fkey";

alter table "public"."platform_export_policy" add constraint "platform_export_policy_contract_id_fkey" FOREIGN KEY (contract_id) REFERENCES public.platform_exchange_contract(contract_id) ON DELETE CASCADE not valid;

alter table "public"."platform_export_policy" validate constraint "platform_export_policy_contract_id_fkey";

alter table "public"."platform_extensible_attribute_schema" add constraint "platform_extensible_attribute_schema_entity_id_fkey" FOREIGN KEY (entity_id) REFERENCES public.platform_extensible_entity_registry(entity_id) ON DELETE CASCADE not valid;

alter table "public"."platform_extensible_attribute_schema" validate constraint "platform_extensible_attribute_schema_entity_id_fkey";

alter table "public"."platform_extensible_attribute_schema" add constraint "platform_extensible_attribute_schema_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_extensible_attribute_schema" validate constraint "platform_extensible_attribute_schema_tenant_id_fkey";

alter table "public"."platform_extensible_join_profile" add constraint "platform_extensible_join_profile_entity_id_fkey" FOREIGN KEY (entity_id) REFERENCES public.platform_extensible_entity_registry(entity_id) ON DELETE CASCADE not valid;

alter table "public"."platform_extensible_join_profile" validate constraint "platform_extensible_join_profile_entity_id_fkey";

alter table "public"."platform_extensible_join_profile" add constraint "platform_extensible_join_profile_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_extensible_join_profile" validate constraint "platform_extensible_join_profile_tenant_id_fkey";

alter table "public"."platform_extensible_schema_cache" add constraint "platform_extensible_schema_cache_entity_id_fkey" FOREIGN KEY (entity_id) REFERENCES public.platform_extensible_entity_registry(entity_id) ON DELETE CASCADE not valid;

alter table "public"."platform_extensible_schema_cache" validate constraint "platform_extensible_schema_cache_entity_id_fkey";

alter table "public"."platform_extensible_schema_cache" add constraint "platform_extensible_schema_cache_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_extensible_schema_cache" validate constraint "platform_extensible_schema_cache_tenant_id_fkey";

alter table "public"."platform_gateway_idempotency_claim" add constraint "platform_gateway_idempotency_claim_operation_code_fkey" FOREIGN KEY (operation_code) REFERENCES public.platform_gateway_operation(operation_code) ON DELETE CASCADE not valid;

alter table "public"."platform_gateway_idempotency_claim" validate constraint "platform_gateway_idempotency_claim_operation_code_fkey";

alter table "public"."platform_gateway_idempotency_claim" add constraint "platform_gateway_idempotency_claim_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) not valid;

alter table "public"."platform_gateway_idempotency_claim" validate constraint "platform_gateway_idempotency_claim_tenant_id_fkey";

alter table "public"."platform_gateway_operation_role" add constraint "platform_gateway_operation_role_operation_code_fkey" FOREIGN KEY (operation_code) REFERENCES public.platform_gateway_operation(operation_code) ON DELETE CASCADE not valid;

alter table "public"."platform_gateway_operation_role" validate constraint "platform_gateway_operation_role_operation_code_fkey";

alter table "public"."platform_gateway_operation_role" add constraint "platform_gateway_operation_role_role_code_fkey" FOREIGN KEY (role_code) REFERENCES public.platform_access_role(role_code) not valid;

alter table "public"."platform_gateway_operation_role" validate constraint "platform_gateway_operation_role_role_code_fkey";

alter table "public"."platform_gateway_request_log" add constraint "platform_gateway_request_log_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) not valid;

alter table "public"."platform_gateway_request_log" validate constraint "platform_gateway_request_log_tenant_id_fkey";

alter table "public"."platform_import_run" add constraint "platform_import_run_contract_id_fkey" FOREIGN KEY (contract_id) REFERENCES public.platform_exchange_contract(contract_id) ON DELETE RESTRICT not valid;

alter table "public"."platform_import_run" validate constraint "platform_import_run_contract_id_fkey";

alter table "public"."platform_import_run" add constraint "platform_import_run_import_session_id_fkey" FOREIGN KEY (import_session_id) REFERENCES public.platform_import_session(import_session_id) ON DELETE CASCADE not valid;

alter table "public"."platform_import_run" validate constraint "platform_import_run_import_session_id_fkey";

alter table "public"."platform_import_run" add constraint "platform_import_run_job_id_fkey" FOREIGN KEY (job_id) REFERENCES public.platform_async_job(job_id) ON DELETE SET NULL not valid;

alter table "public"."platform_import_run" validate constraint "platform_import_run_job_id_fkey";

alter table "public"."platform_import_run" add constraint "platform_import_run_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_import_run" validate constraint "platform_import_run_tenant_id_fkey";

alter table "public"."platform_import_session" add constraint "platform_import_session_contract_id_fkey" FOREIGN KEY (contract_id) REFERENCES public.platform_exchange_contract(contract_id) ON DELETE RESTRICT not valid;

alter table "public"."platform_import_session" validate constraint "platform_import_session_contract_id_fkey";

alter table "public"."platform_import_session" add constraint "platform_import_session_source_document_id_fkey" FOREIGN KEY (source_document_id) REFERENCES public.platform_document_record(document_id) ON DELETE SET NULL not valid;

alter table "public"."platform_import_session" validate constraint "platform_import_session_source_document_id_fkey";

alter table "public"."platform_import_session" add constraint "platform_import_session_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_import_session" validate constraint "platform_import_session_tenant_id_fkey";

alter table "public"."platform_import_session" add constraint "platform_import_session_upload_intent_id_fkey" FOREIGN KEY (upload_intent_id) REFERENCES public.platform_document_upload_intent(upload_intent_id) ON DELETE SET NULL not valid;

alter table "public"."platform_import_session" validate constraint "platform_import_session_upload_intent_id_fkey";

alter table "public"."platform_import_staging_row" add constraint "platform_import_staging_row_import_session_id_fkey" FOREIGN KEY (import_session_id) REFERENCES public.platform_import_session(import_session_id) ON DELETE CASCADE not valid;

alter table "public"."platform_import_staging_row" validate constraint "platform_import_staging_row_import_session_id_fkey";

alter table "public"."platform_import_staging_row" add constraint "platform_import_staging_row_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_import_staging_row" validate constraint "platform_import_staging_row_tenant_id_fkey";

alter table "public"."platform_import_validation_summary" add constraint "platform_import_validation_summary_import_session_id_fkey" FOREIGN KEY (import_session_id) REFERENCES public.platform_import_session(import_session_id) ON DELETE CASCADE not valid;

alter table "public"."platform_import_validation_summary" validate constraint "platform_import_validation_summary_import_session_id_fkey";

alter table "public"."platform_import_validation_summary" add constraint "platform_import_validation_summary_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_import_validation_summary" validate constraint "platform_import_validation_summary_tenant_id_fkey";

alter table "public"."platform_invoice" add constraint "platform_invoice_billing_cycle_id_fkey" FOREIGN KEY (billing_cycle_id) REFERENCES public.platform_billing_cycle(id) ON DELETE CASCADE not valid;

alter table "public"."platform_invoice" validate constraint "platform_invoice_billing_cycle_id_fkey";

alter table "public"."platform_invoice" add constraint "platform_invoice_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_invoice" validate constraint "platform_invoice_tenant_id_fkey";

alter table "public"."platform_membership_invitation" add constraint "platform_membership_invitation_role_code_fkey" FOREIGN KEY (role_code) REFERENCES public.platform_access_role(role_code) not valid;

alter table "public"."platform_membership_invitation" validate constraint "platform_membership_invitation_role_code_fkey";

alter table "public"."platform_membership_invitation" add constraint "platform_membership_invitation_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_membership_invitation" validate constraint "platform_membership_invitation_tenant_id_fkey";

alter table "public"."platform_owner_bootstrap_token" add constraint "platform_owner_bootstrap_token_provision_request_id_fkey" FOREIGN KEY (provision_request_id) REFERENCES public.platform_client_provision_request(provision_request_id) ON DELETE CASCADE not valid;

alter table "public"."platform_owner_bootstrap_token" validate constraint "platform_owner_bootstrap_token_provision_request_id_fkey";

alter table "public"."platform_payment_receipt" add constraint "platform_payment_receipt_invoice_id_fkey" FOREIGN KEY (invoice_id) REFERENCES public.platform_invoice(id) ON DELETE SET NULL not valid;

alter table "public"."platform_payment_receipt" validate constraint "platform_payment_receipt_invoice_id_fkey";

alter table "public"."platform_payment_receipt" add constraint "platform_payment_receipt_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_payment_receipt" validate constraint "platform_payment_receipt_tenant_id_fkey";

alter table "public"."platform_plan_metric_rate" add constraint "platform_plan_metric_rate_plan_id_fkey" FOREIGN KEY (plan_id) REFERENCES public.platform_plan_catalog(id) ON DELETE CASCADE not valid;

alter table "public"."platform_plan_metric_rate" validate constraint "platform_plan_metric_rate_plan_id_fkey";

alter table "public"."platform_read_model_refresh_run" add constraint "platform_read_model_refresh_run_async_job_id_fkey" FOREIGN KEY (async_job_id) REFERENCES public.platform_async_job(job_id) ON DELETE SET NULL not valid;

alter table "public"."platform_read_model_refresh_run" validate constraint "platform_read_model_refresh_run_async_job_id_fkey";

alter table "public"."platform_read_model_refresh_run" add constraint "platform_read_model_refresh_run_read_model_code_fkey" FOREIGN KEY (read_model_code) REFERENCES public.platform_read_model_catalog(read_model_code) ON DELETE CASCADE not valid;

alter table "public"."platform_read_model_refresh_run" validate constraint "platform_read_model_refresh_run_read_model_code_fkey";

alter table "public"."platform_read_model_refresh_run" add constraint "platform_read_model_refresh_run_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_read_model_refresh_run" validate constraint "platform_read_model_refresh_run_tenant_id_fkey";

alter table "public"."platform_read_model_refresh_state" add constraint "platform_read_model_refresh_state_read_model_code_fkey" FOREIGN KEY (read_model_code) REFERENCES public.platform_read_model_catalog(read_model_code) ON DELETE CASCADE not valid;

alter table "public"."platform_read_model_refresh_state" validate constraint "platform_read_model_refresh_state_read_model_code_fkey";

alter table "public"."platform_read_model_refresh_state" add constraint "platform_read_model_refresh_state_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_read_model_refresh_state" validate constraint "platform_read_model_refresh_state_tenant_id_fkey";

alter table "public"."platform_schema_provisioning_run" add constraint "platform_schema_provisioning_run_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_schema_provisioning_run" validate constraint "platform_schema_provisioning_run_tenant_id_fkey";

alter table "public"."platform_signin_challenge" add constraint "platform_signin_challenge_policy_code_fkey" FOREIGN KEY (policy_code) REFERENCES public.platform_signin_policy(policy_code) not valid;

alter table "public"."platform_signin_challenge" validate constraint "platform_signin_challenge_policy_code_fkey";

alter table "public"."platform_signup_request" add constraint "platform_signup_request_async_job_id_fkey" FOREIGN KEY (async_job_id) REFERENCES public.platform_async_job(job_id) ON DELETE SET NULL not valid;

alter table "public"."platform_signup_request" validate constraint "platform_signup_request_async_job_id_fkey";

alter table "public"."platform_signup_request" add constraint "platform_signup_request_invitation_id_fkey" FOREIGN KEY (invitation_id) REFERENCES public.platform_membership_invitation(invitation_id) ON DELETE SET NULL not valid;

alter table "public"."platform_signup_request" validate constraint "platform_signup_request_invitation_id_fkey";

alter table "public"."platform_template_table_registry" add constraint "platform_template_table_registry_template_version_fkey" FOREIGN KEY (template_version) REFERENCES public.platform_template_version(template_version) ON DELETE CASCADE not valid;

alter table "public"."platform_template_table_registry" validate constraint "platform_template_table_registry_template_version_fkey";

alter table "public"."platform_tenant_access_state" add constraint "platform_tenant_access_state_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_tenant_access_state" validate constraint "platform_tenant_access_state_tenant_id_fkey";

alter table "public"."platform_tenant_commercial_account" add constraint "platform_tenant_commercial_account_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_tenant_commercial_account" validate constraint "platform_tenant_commercial_account_tenant_id_fkey";

alter table "public"."platform_tenant_provisioning" add constraint "platform_tenant_provisioning_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_tenant_provisioning" validate constraint "platform_tenant_provisioning_tenant_id_fkey";

alter table "public"."platform_tenant_status_history" add constraint "platform_tenant_status_history_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_tenant_status_history" validate constraint "platform_tenant_status_history_tenant_id_fkey";

alter table "public"."platform_tenant_subscription" add constraint "platform_tenant_subscription_plan_id_fkey" FOREIGN KEY (plan_id) REFERENCES public.platform_plan_catalog(id) not valid;

alter table "public"."platform_tenant_subscription" validate constraint "platform_tenant_subscription_plan_id_fkey";

alter table "public"."platform_tenant_subscription" add constraint "platform_tenant_subscription_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_tenant_subscription" validate constraint "platform_tenant_subscription_tenant_id_fkey";

alter table "public"."platform_tenant_template_version" add constraint "platform_tenant_template_version_run_id_fkey" FOREIGN KEY (run_id) REFERENCES public.platform_schema_provisioning_run(run_id) ON DELETE SET NULL not valid;

alter table "public"."platform_tenant_template_version" validate constraint "platform_tenant_template_version_run_id_fkey";

alter table "public"."platform_tenant_template_version" add constraint "platform_tenant_template_version_template_version_fkey" FOREIGN KEY (template_version) REFERENCES public.platform_template_version(template_version) ON DELETE RESTRICT not valid;

alter table "public"."platform_tenant_template_version" validate constraint "platform_tenant_template_version_template_version_fkey";

alter table "public"."platform_tenant_template_version" add constraint "platform_tenant_template_version_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES public.platform_tenant(tenant_id) ON DELETE CASCADE not valid;

alter table "public"."platform_tenant_template_version" validate constraint "platform_tenant_template_version_tenant_id_fkey";

alter table "public"."wcm_fbp_claim_document_binding" add constraint "wcm_fbp_claim_document_binding_document_id_fkey" FOREIGN KEY (document_id) REFERENCES public.platform_document_record(document_id) ON DELETE CASCADE not valid;

alter table "public"."wcm_fbp_claim_document_binding" validate constraint "wcm_fbp_claim_document_binding_document_id_fkey";

alter table "tenant_eoaplive133052"."ams_bio_import_session" add constraint "ams_bio_import_session_source_document_fk" FOREIGN KEY (source_document_id) REFERENCES public.platform_document_record(document_id) ON DELETE SET NULL not valid;

alter table "tenant_eoaplive133052"."ams_bio_import_session" validate constraint "ams_bio_import_session_source_document_fk";

alter table "tenant_eoaplive133052"."ams_regularization_request" add constraint "ams_regularization_request_supporting_document_fk" FOREIGN KEY (supporting_document_id) REFERENCES public.platform_document_record(document_id) ON DELETE SET NULL not valid;

alter table "tenant_eoaplive133052"."ams_regularization_request" validate constraint "ams_regularization_request_supporting_document_fk";

alter table "tenant_eoaplive133052"."lms_leave_request" add constraint "lms_leave_request_supporting_document_fk" FOREIGN KEY (supporting_document_id) REFERENCES public.platform_document_record(document_id) ON DELETE SET NULL not valid;

alter table "tenant_eoaplive133052"."lms_leave_request" validate constraint "lms_leave_request_supporting_document_fk";

alter table "tenant_eoaplive133052"."wcm_payslip_item" add constraint "wcm_payslip_item_document_fk" FOREIGN KEY (generated_document_id) REFERENCES public.platform_document_record(document_id) ON DELETE SET NULL not valid;

alter table "tenant_eoaplive133052"."wcm_payslip_item" validate constraint "wcm_payslip_item_document_fk";

set check_function_bodies = off;

create or replace view "public"."platform_async_dead_letter_view" as  SELECT paj.job_id,
    paj.tenant_id,
    pt.tenant_code,
    paj.tenant_schema,
    paj.module_code,
    paj.worker_code,
    paj.job_type,
    paj.attempt_count,
    paj.max_attempts,
    paj.last_error_code,
    paj.last_error_message,
    paj.dead_lettered_at,
    paj.updated_at
   FROM (public.platform_async_job paj
     JOIN public.platform_tenant pt ON ((pt.tenant_id = paj.tenant_id)))
  WHERE (paj.job_state = 'dead_lettered'::text);


create or replace view "public"."platform_async_queue_health_view" as  SELECT paj.tenant_id,
    pt.tenant_code,
    paj.tenant_schema,
    paj.module_code,
    paj.worker_code,
    count(*) FILTER (WHERE (paj.job_state = 'queued'::text)) AS queued_count,
    count(*) FILTER (WHERE (paj.job_state = ANY (ARRAY['claimed'::text, 'running'::text]))) AS running_count,
    count(*) FILTER (WHERE (paj.job_state = 'retry_wait'::text)) AS retry_wait_count,
    count(*) FILTER (WHERE (paj.job_state = 'dead_lettered'::text)) AS dead_letter_count,
    count(*) FILTER (WHERE ((paj.job_state = ANY (ARRAY['claimed'::text, 'running'::text])) AND (paj.lease_expires_at IS NOT NULL) AND (paj.lease_expires_at < timezone('utc'::text, now())))) AS stale_lease_count,
    min(
        CASE
            WHEN (paj.job_state = 'queued'::text) THEN paj.available_at
            WHEN (paj.job_state = 'retry_wait'::text) THEN COALESCE(paj.next_retry_at, paj.available_at)
            ELSE NULL::timestamp with time zone
        END) AS oldest_due_at,
    max(paj.completed_at) AS last_completed_at
   FROM (public.platform_async_job paj
     JOIN public.platform_tenant pt ON ((pt.tenant_id = paj.tenant_id)))
  GROUP BY paj.tenant_id, pt.tenant_code, paj.tenant_schema, paj.module_code, paj.worker_code;


create or replace view "public"."platform_async_stale_lease_view" as  SELECT paj.job_id,
    paj.tenant_id,
    pt.tenant_code,
    paj.tenant_schema,
    paj.module_code,
    paj.worker_code,
    paj.job_type,
    paj.job_state,
    paj.claimed_at,
    paj.lease_expires_at,
    paj.heartbeat_at,
    paj.attempt_count,
    paj.max_attempts,
    paj.claimed_by_worker,
    paj.last_error_code,
    paj.last_error_message
   FROM (public.platform_async_job paj
     JOIN public.platform_tenant pt ON ((pt.tenant_id = paj.tenant_id)))
  WHERE ((paj.job_state = ANY (ARRAY['claimed'::text, 'running'::text])) AND (paj.lease_expires_at IS NOT NULL) AND (paj.lease_expires_at < timezone('utc'::text, now())));


CREATE OR REPLACE FUNCTION public.platform_get_effective_plan_rate(p_plan_id uuid, p_metric_code text, p_as_of_date date)
 RETURNS public.platform_plan_metric_rate
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_rate public.platform_plan_metric_rate%rowtype;
begin
  select *
  into v_rate
  from public.platform_plan_metric_rate ppmr
  where ppmr.plan_id = p_plan_id
    and ppmr.metric_code = p_metric_code
    and ppmr.effective_from <= p_as_of_date
    and (ppmr.effective_to is null or ppmr.effective_to >= p_as_of_date)
  order by ppmr.effective_from desc, ppmr.created_at desc
  limit 1;

  return v_rate;
end;
$function$
;

create or replace view "public"."platform_rm_agm_admin_observability_overview" as  SELECT active_rule_set_count,
    badge_catalog_count,
    active_badge_award_count,
    active_recognition_count,
    participant_count,
    latest_snapshot_date,
    queued_refresh_count,
    running_refresh_count
   FROM public.platform_agm_admin_observability_overview_rows() platform_agm_admin_observability_overview_rows(active_rule_set_count, badge_catalog_count, active_badge_award_count, active_recognition_count, participant_count, latest_snapshot_date, queued_refresh_count, running_refresh_count);


create or replace view "public"."platform_rm_agm_admin_refresh_status" as  SELECT worker_code,
    queued_count,
    running_count,
    retry_wait_count,
    dead_letter_count,
    stale_lease_count,
    oldest_due_at,
    last_completed_at
   FROM public.platform_agm_admin_refresh_status_rows() platform_agm_admin_refresh_status_rows(worker_code, queued_count, running_count, retry_wait_count, dead_letter_count, stale_lease_count, oldest_due_at, last_completed_at);


create or replace view "public"."platform_rm_agm_admin_rule_set_catalog" as  SELECT rule_set_id,
    rule_set_code,
    rule_set_name,
    status,
    updated_at
   FROM public.platform_agm_admin_rule_set_catalog_rows() platform_agm_admin_rule_set_catalog_rows(rule_set_id, rule_set_code, rule_set_name, status, updated_at);


create or replace view "public"."platform_rm_agm_my_badge_history" as  SELECT award_id,
    employee_id,
    badge_id,
    award_date,
    award_status,
    award_payload,
    acknowledged_at,
    created_at
   FROM public.platform_agm_my_badge_history_rows() platform_agm_my_badge_history_rows(award_id, employee_id, badge_id, award_date, award_status, award_payload, acknowledged_at, created_at);


create or replace view "public"."platform_rm_agm_my_recognition_history" as  SELECT recognition_event_id,
    sender_employee_id,
    recipient_employee_id,
    recognition_type,
    recognition_status,
    message_text,
    points_awarded,
    meta,
    acknowledged_at,
    created_at
   FROM public.platform_agm_my_recognition_history_rows() platform_agm_my_recognition_history_rows(recognition_event_id, sender_employee_id, recipient_employee_id, recognition_type, recognition_status, message_text, points_awarded, meta, acknowledged_at, created_at);


create or replace view "public"."platform_rm_agm_my_score_summary" as  SELECT employee_id,
    window_code,
    window_start,
    window_end,
    total_score,
    streak_count,
    badge_count,
    summary_payload,
    updated_at
   FROM public.platform_agm_my_score_summary_rows() platform_agm_my_score_summary_rows(employee_id, window_code, window_start, window_end, total_score, streak_count, badge_count, summary_payload, updated_at);


create or replace view "public"."platform_rm_agm_tenant_leaderboard" as  SELECT scope_code,
    scope_key,
    window_code,
    snapshot_date,
    rank_position,
    employee_id,
    total_score,
    badge_count,
    rank_payload
   FROM public.platform_agm_tenant_leaderboard_rows() platform_agm_tenant_leaderboard_rows(scope_code, scope_key, window_code, snapshot_date, rank_position, employee_id, total_score, badge_count, rank_payload);


create or replace view "public"."platform_rm_ams_attendance_history" as  SELECT tenant_id,
    attendance_record_id,
    employee_id,
    employee_code,
    employee_name,
    employee_actor_user_id,
    attendance_date,
    shift_id,
    shift_code,
    shift_name,
    scheduled_clock_in,
    scheduled_clock_out,
    clock_in_time,
    clock_out_time,
    duration_minutes,
    overtime_minutes,
    late_minutes,
    early_leaving_minutes,
    status_raw,
    status_final,
    on_leave_request_id,
    leave_session_scope,
    leave_fraction,
    is_holiday,
    holiday_name,
    regularization_request_id,
    is_manually_edited,
    manual_edit_reason,
    mood_score,
    created_at,
    updated_at
   FROM public.platform_ams_attendance_history_rows() platform_ams_attendance_history_rows(tenant_id, attendance_record_id, employee_id, employee_code, employee_name, employee_actor_user_id, attendance_date, shift_id, shift_code, shift_name, scheduled_clock_in, scheduled_clock_out, clock_in_time, clock_out_time, duration_minutes, overtime_minutes, late_minutes, early_leaving_minutes, status_raw, status_final, on_leave_request_id, leave_session_scope, leave_fraction, is_holiday, holiday_name, regularization_request_id, is_manually_edited, manual_edit_reason, mood_score, created_at, updated_at);


create or replace view "public"."platform_rm_ams_bio_admin_overview" as  SELECT source_profile_count,
    live_source_count,
    queued_run_count,
    open_reconciliation_count,
    pending_publish_count,
    today_published_count
   FROM public.platform_ams_bio_admin_overview_rows() platform_ams_bio_admin_overview_rows(source_profile_count, live_source_count, queued_run_count, open_reconciliation_count, pending_publish_count, today_published_count);


create or replace view "public"."platform_rm_ams_bio_import_session_queue" as  SELECT import_session_id,
    session_code,
    source_profile_id,
    mapping_profile_id,
    import_mode,
    session_purpose,
    session_status,
    staged_rows,
    ready_rows,
    committed_rows,
    created_at,
    updated_at
   FROM public.platform_ams_bio_import_session_queue_rows() platform_ams_bio_import_session_queue_rows(import_session_id, session_code, source_profile_id, mapping_profile_id, import_mode, session_purpose, session_status, staged_rows, ready_rows, committed_rows, created_at, updated_at);


create or replace view "public"."platform_rm_ams_bio_reconciliation_dashboard" as  SELECT reconciliation_case_id,
    case_type,
    case_status,
    employee_id,
    attendance_date,
    normalized_punch_id,
    details_json,
    opened_at,
    resolved_at
   FROM public.platform_ams_bio_reconciliation_dashboard_rows() platform_ams_bio_reconciliation_dashboard_rows(reconciliation_case_id, case_type, case_status, employee_id, attendance_date, normalized_punch_id, details_json, opened_at, resolved_at);


create or replace view "public"."platform_rm_ams_bio_source_profile_catalog" as  SELECT source_profile_id,
    source_code,
    source_name,
    source_mode,
    source_status,
    onboarding_status,
    current_step_code,
    live_enabled_at,
    updated_at
   FROM public.platform_ams_bio_source_profile_catalog_rows() platform_ams_bio_source_profile_catalog_rows(source_profile_id, source_code, source_name, source_mode, source_status, onboarding_status, current_step_code, live_enabled_at, updated_at);


create or replace view "public"."platform_rm_ams_pending_approvals" as  SELECT tenant_id,
    manager_actor_user_id,
    manager_employee_id,
    regularization_request_id,
    attendance_record_id,
    employee_id,
    employee_code,
    employee_name,
    request_type,
    request_status,
    requested_clock_in,
    requested_clock_out,
    supporting_document_id,
    created_at
   FROM public.platform_ams_pending_approval_rows() platform_ams_pending_approval_rows(tenant_id, manager_actor_user_id, manager_employee_id, regularization_request_id, attendance_record_id, employee_id, employee_code, employee_name, request_type, request_status, requested_clock_in, requested_clock_out, supporting_document_id, created_at);


create or replace view "public"."platform_rm_ams_shift_catalog" as  SELECT tenant_id,
    shift_id,
    shift_code,
    shift_name,
    start_time,
    end_time,
    break_duration_minutes,
    paid_break_minutes,
    work_days,
    crosses_midnight,
    shift_status,
    shift_metadata,
    created_at,
    updated_at
   FROM public.platform_ams_shift_catalog_rows() platform_ams_shift_catalog_rows(tenant_id, shift_id, shift_code, shift_name, start_time, end_time, break_duration_minutes, paid_break_minutes, work_days, crosses_midnight, shift_status, shift_metadata, created_at, updated_at);


create or replace view "public"."platform_rm_ams_team_day_summary" as  SELECT tenant_id,
    manager_actor_user_id,
    manager_employee_id,
    team_member_employee_id,
    team_member_employee_code,
    team_member_employee_name,
    attendance_record_id,
    attendance_date,
    status_final,
    clock_in_time,
    clock_out_time,
    late_minutes,
    early_leaving_minutes,
    overtime_minutes,
    on_leave_request_id,
    holiday_name,
    is_manually_edited,
    mood_score,
    updated_at
   FROM public.platform_ams_team_day_summary_rows() platform_ams_team_day_summary_rows(tenant_id, manager_actor_user_id, manager_employee_id, team_member_employee_id, team_member_employee_code, team_member_employee_name, attendance_record_id, attendance_date, status_final, clock_in_time, clock_out_time, late_minutes, early_leaving_minutes, overtime_minutes, on_leave_request_id, holiday_name, is_manually_edited, mood_score, updated_at);


create or replace view "public"."platform_rm_async_dead_letter" as  SELECT job_id,
    tenant_id,
    tenant_code,
    tenant_schema,
    module_code,
    worker_code,
    job_type,
    attempt_count,
    max_attempts,
    last_error_code,
    last_error_message,
    dead_lettered_at,
    updated_at
   FROM public.platform_async_dead_letter_view;


create or replace view "public"."platform_rm_async_queue_health" as  SELECT tenant_id,
    tenant_code,
    tenant_schema,
    module_code,
    worker_code,
    queued_count,
    running_count,
    retry_wait_count,
    dead_letter_count,
    stale_lease_count,
    oldest_due_at,
    last_completed_at
   FROM public.platform_async_queue_health_view;


create or replace view "public"."platform_rm_async_stale_lease" as  SELECT job_id,
    tenant_id,
    tenant_code,
    tenant_schema,
    module_code,
    worker_code,
    job_type,
    job_state,
    claimed_at,
    lease_expires_at,
    heartbeat_at,
    attempt_count,
    max_attempts,
    claimed_by_worker,
    last_error_code,
    last_error_message
   FROM public.platform_async_stale_lease_view;


create or replace view "public"."platform_rm_client_provision_state" as  SELECT r.provision_request_id,
    r.request_key,
    r.company_name,
    r.legal_name,
    r.primary_contact_name,
    r.primary_work_email,
    r.primary_mobile,
    r.selected_plan_code,
    r.currency_code,
    r.country_code,
    r.timezone,
    r.request_source,
    r.provisioning_status,
    r.next_action,
    r.tenant_id,
    t.tenant_code,
    t.schema_name,
    r.owner_actor_user_id,
    c.checkout_id AS latest_checkout_id,
    c.provider_code AS latest_checkout_provider_code,
    c.external_checkout_id AS latest_external_checkout_id,
    c.checkout_status AS latest_checkout_status,
    c.quoted_amount AS latest_checkout_amount,
    c.currency_code AS latest_checkout_currency_code,
    c.checkout_url AS latest_checkout_url,
    c.expires_at AS latest_checkout_expires_at,
    pe.event_type AS last_provision_event_type,
    pe.event_status AS last_provision_event_status,
    pe.created_at AS last_provision_event_at,
    ( SELECT count(*) AS count
           FROM public.platform_client_provision_event e2
          WHERE (e2.provision_request_id = r.provision_request_id)) AS provision_event_count,
    ( SELECT count(*) AS count
           FROM public.platform_client_purchase_event p2
          WHERE (p2.provision_request_id = r.provision_request_id)) AS purchase_event_count,
    r.created_at,
    r.updated_at
   FROM (((public.platform_client_provision_request r
     LEFT JOIN public.platform_tenant t ON ((t.tenant_id = r.tenant_id)))
     LEFT JOIN LATERAL ( SELECT c1.checkout_id,
            c1.provision_request_id,
            c1.provider_code,
            c1.external_checkout_id,
            c1.checkout_status,
            c1.plan_code,
            c1.currency_code,
            c1.quoted_amount,
            c1.billing_cadence,
            c1.checkout_url,
            c1.expires_at,
            c1.resolved_at,
            c1.metadata,
            c1.created_at,
            c1.updated_at
           FROM public.platform_client_purchase_checkout c1
          WHERE (c1.provision_request_id = r.provision_request_id)
          ORDER BY c1.created_at DESC, c1.checkout_id DESC
         LIMIT 1) c ON (true))
     LEFT JOIN LATERAL ( SELECT e1.event_id,
            e1.provision_request_id,
            e1.event_type,
            e1.event_status,
            e1.actor_user_id,
            e1.event_source,
            e1.event_message,
            e1.event_details,
            e1.created_at
           FROM public.platform_client_provision_event e1
          WHERE (e1.provision_request_id = r.provision_request_id)
          ORDER BY e1.created_at DESC, e1.event_id DESC
         LIMIT 1) pe ON (true));


create or replace view "public"."platform_rm_document_binding_catalog" as  SELECT pdb.binding_id,
    pdb.tenant_id,
    pdb.document_id,
    pdc.document_class_code,
    pdb.target_entity_code,
    pdb.target_key,
    pdb.relation_purpose,
    pdb.binding_status,
    pdb.bound_by_actor_user_id,
    pdb.metadata,
    pdb.created_at,
    pdb.updated_at
   FROM ((public.platform_document_binding pdb
     JOIN public.platform_document_record pdr ON ((pdr.document_id = pdb.document_id)))
     JOIN public.platform_document_class pdc ON ((pdc.document_class_id = pdr.document_class_id)));


create or replace view "public"."platform_rm_document_catalog" as  SELECT pdr.document_id,
    pdr.tenant_id,
    pdc.document_class_code,
    pdc.class_label,
    pdc.owner_module_code,
    pdr.bucket_code,
    psbc.bucket_name,
    pdr.upload_intent_id,
    pdr.owner_actor_user_id,
    pdr.uploaded_by_actor_user_id,
    pdr.storage_object_name,
    pdr.original_file_name,
    pdr.content_type,
    pdr.file_size_bytes,
    pdr.checksum_sha256,
    pdr.protection_mode,
    pdr.access_mode,
    pdr.allowed_role_codes,
    pdr.document_status,
    pdr.version_no,
    pdr.expires_on,
    pdr.storage_metadata,
    pdr.document_metadata,
    pdr.created_at,
    pdr.updated_at
   FROM ((public.platform_document_record pdr
     JOIN public.platform_document_class pdc ON ((pdc.document_class_id = pdr.document_class_id)))
     JOIN public.platform_storage_bucket_catalog psbc ON ((psbc.bucket_code = pdr.bucket_code)));


create or replace view "public"."platform_rm_employee_pay_structure_assignment" as  SELECT tenant_id,
    employee_pay_structure_assignment_id,
    employee_id,
    employee_code,
    employee_name,
    pay_structure_id,
    structure_code,
    pay_structure_version_id,
    effective_from,
    effective_to,
    assignment_status,
    updated_at
   FROM public.platform_employee_pay_structure_assignment_rows() platform_employee_pay_structure_assignment_rows(tenant_id, employee_pay_structure_assignment_id, employee_id, employee_code, employee_name, pay_structure_id, structure_code, pay_structure_version_id, effective_from, effective_to, assignment_status, updated_at);


create or replace view "public"."platform_rm_employee_payslip_history" as  SELECT tenant_id,
    payslip_run_id,
    payslip_item_id,
    payroll_period,
    employee_id,
    employee_code,
    item_status,
    artifact_status,
    generated_document_id,
    completed_at,
    updated_at
   FROM public.platform_employee_payslip_history_rows() platform_employee_payslip_history_rows(tenant_id, payslip_run_id, payslip_item_id, payroll_period, employee_id, employee_code, item_status, artifact_status, generated_document_id, completed_at, updated_at);


create or replace view "public"."platform_rm_eoap_document_readiness" as  SELECT workflow_id,
    document_requirement_id,
    document_requirement_code,
    document_requirement_name,
    document_class_id,
    latest_document_id,
    latest_submission_status,
    is_required
   FROM public.platform_eoap_document_readiness_rows() platform_eoap_document_readiness_rows(workflow_id, document_requirement_id, document_requirement_code, document_requirement_name, document_class_id, latest_document_id, latest_submission_status, is_required);


create or replace view "public"."platform_rm_eoap_pending_hire_queue" as  SELECT pending_hire_id,
    employee_id,
    employee_code,
    employee_name,
    conversion_case_id,
    target_position_id,
    workflow_id,
    workflow_status,
    readiness_status,
    queued_at,
    activated_at
   FROM public.platform_eoap_pending_hire_rows() platform_eoap_pending_hire_rows(pending_hire_id, employee_id, employee_code, employee_name, conversion_case_id, target_position_id, workflow_id, workflow_status, readiness_status, queued_at, activated_at);


create or replace view "public"."platform_rm_eoap_workflow_progress" as  SELECT workflow_id,
    pending_hire_id,
    employee_id,
    workflow_template_id,
    workflow_status,
    current_step_code,
    total_steps,
    completed_steps,
    remaining_required_steps
   FROM public.platform_eoap_workflow_progress_rows() platform_eoap_workflow_progress_rows(workflow_id, pending_hire_id, employee_id, workflow_template_id, workflow_status, current_step_code, total_steps, completed_steps, remaining_required_steps);


create or replace view "public"."platform_rm_esic_batch_catalog" as  SELECT tenant_id,
    batch_id,
    establishment_id,
    establishment_code,
    payroll_period,
    return_period,
    batch_status,
    worker_job_id,
    updated_at
   FROM public.platform_esic_batch_catalog_rows() platform_esic_batch_catalog_rows(tenant_id, batch_id, establishment_id, establishment_code, payroll_period, return_period, batch_status, worker_job_id, updated_at);


create or replace view "public"."platform_rm_esic_benefit_period_status" as  SELECT tenant_id,
    benefit_period_id,
    employee_id,
    employee_code,
    contribution_period_start,
    contribution_period_end,
    benefit_period_start,
    benefit_period_end,
    total_days_worked,
    total_wages_paid,
    is_eligible,
    updated_at
   FROM public.platform_esic_benefit_period_status_rows() platform_esic_benefit_period_status_rows(tenant_id, benefit_period_id, employee_id, employee_code, contribution_period_start, contribution_period_end, benefit_period_start, benefit_period_end, total_days_worked, total_wages_paid, is_eligible, updated_at);


create or replace view "public"."platform_rm_esic_challan_run_status" as  SELECT tenant_id,
    challan_run_id,
    batch_id,
    payroll_period,
    return_period,
    run_status,
    reconciliation_status,
    total_contribution,
    payment_amount,
    discrepancy_amount,
    updated_at
   FROM public.platform_esic_challan_run_status_rows() platform_esic_challan_run_status_rows(tenant_id, challan_run_id, batch_id, payroll_period, return_period, run_status, reconciliation_status, total_contribution, payment_amount, discrepancy_amount, updated_at);


create or replace view "public"."platform_rm_esic_configuration_catalog" as  SELECT tenant_id,
    configuration_id,
    state_code,
    effective_from,
    effective_to,
    wage_ceiling,
    employee_contribution_rate,
    employer_contribution_rate,
    configuration_status,
    updated_at
   FROM public.platform_esic_configuration_catalog_rows() platform_esic_configuration_catalog_rows(tenant_id, configuration_id, state_code, effective_from, effective_to, wage_ceiling, employee_contribution_rate, employer_contribution_rate, configuration_status, updated_at);


create or replace view "public"."platform_rm_esic_contribution_ledger" as  SELECT tenant_id,
    contribution_ledger_id,
    batch_id,
    employee_id,
    employee_code,
    payroll_period,
    eligible_wages,
    employee_contribution,
    employer_contribution,
    total_contribution,
    sync_status
   FROM public.platform_esic_contribution_ledger_rows() platform_esic_contribution_ledger_rows(tenant_id, contribution_ledger_id, batch_id, employee_id, employee_code, payroll_period, eligible_wages, employee_contribution, employer_contribution, total_contribution, sync_status);


create or replace view "public"."platform_rm_esic_establishment_catalog" as  SELECT tenant_id,
    establishment_id,
    establishment_code,
    establishment_name,
    registration_code,
    state_code,
    establishment_status,
    coverage_start_date,
    updated_at
   FROM public.platform_esic_establishment_catalog_rows() platform_esic_establishment_catalog_rows(tenant_id, establishment_id, establishment_code, establishment_name, registration_code, state_code, establishment_status, coverage_start_date, updated_at);


create or replace view "public"."platform_rm_esic_registration_status" as  SELECT tenant_id,
    registration_id,
    employee_id,
    employee_code,
    establishment_id,
    establishment_code,
    ip_number,
    registration_status,
    registration_date,
    updated_at
   FROM public.platform_esic_registration_status_rows() platform_esic_registration_status_rows(tenant_id, registration_id, employee_id, employee_code, establishment_id, establishment_code, ip_number, registration_status, registration_date, updated_at);


create or replace view "public"."platform_rm_exchange_contract_catalog" as  SELECT pec.contract_id,
    pec.contract_code,
    pec.direction,
    pec.contract_label,
    pec.owner_module_code,
    peer.entity_code,
    peer.entity_label,
    peer.target_relation_schema,
    peer.target_relation_name,
    pec.worker_code,
    pec.source_operation_code,
    pec.target_operation_code,
    pec.join_profile_code,
    pec.template_mode,
    pec.accepted_file_formats,
    pec.allowed_role_codes,
    pec.upload_document_class_code,
    pec.artifact_document_class_code,
    pec.artifact_bucket_code,
    pec.contract_status,
    pec.validation_profile,
    pec.delivery_profile,
    pec.metadata,
    pec.created_at,
    pec.updated_at
   FROM (public.platform_exchange_contract pec
     JOIN public.platform_extensible_entity_registry peer ON ((peer.entity_id = pec.entity_id)));


create or replace view "public"."platform_rm_export_job_overview" as  SELECT pej.export_job_id,
    pej.tenant_id,
    pec.contract_code,
    peer.entity_code,
    pej.requested_by_actor_user_id,
    pej.job_id,
    pej.idempotency_key,
    pej.deduplication_key,
    pej.artifact_document_id,
    pea.export_artifact_id,
    pea.bucket_code,
    pea.storage_object_name,
    pea.file_name,
    pea.content_type,
    pea.file_size_bytes,
    pea.retention_expires_at,
    pea.artifact_status,
    pej.job_status,
    pej.progress_percent,
    pej.result_summary,
    pej.error_details,
    pej.queued_at,
    pej.started_at,
    pej.completed_at,
    pej.expires_at,
    pej.created_at,
    pej.updated_at
   FROM (((public.platform_export_job pej
     JOIN public.platform_exchange_contract pec ON ((pec.contract_id = pej.contract_id)))
     JOIN public.platform_extensible_entity_registry peer ON ((peer.entity_id = pec.entity_id)))
     LEFT JOIN public.platform_export_artifact pea ON ((pea.export_job_id = pej.export_job_id)));


create or replace view "public"."platform_rm_export_queue_health" as  SELECT pec.contract_code,
    pej.job_status,
    count(*) AS job_count,
    min(pej.queued_at) AS oldest_queued_at,
    max(pej.updated_at) AS newest_update_at
   FROM (public.platform_export_job pej
     JOIN public.platform_exchange_contract pec ON ((pec.contract_id = pej.contract_id)))
  GROUP BY pec.contract_code, pej.job_status;


create or replace view "public"."platform_rm_extensible_attribute_catalog" as  SELECT pas.attribute_schema_id,
    peer.entity_code,
    peer.owner_module_code,
    pas.tenant_id,
    pas.attribute_code,
    pas.ui_label,
    pas.data_type,
    pas.is_required,
    pas.default_value,
    pas.validation_rules,
    pas.sort_order,
    pas.attribute_status,
    pas.metadata,
    pas.created_at,
    pas.updated_at
   FROM (public.platform_extensible_attribute_schema pas
     JOIN public.platform_extensible_entity_registry peer ON ((peer.entity_id = pas.entity_id)));


create or replace view "public"."platform_rm_extensible_entity_catalog" as  SELECT peer.entity_id,
    peer.entity_code,
    peer.entity_label,
    peer.owner_module_code,
    peer.target_relation_schema,
    peer.target_relation_name,
    peer.primary_key_column,
    peer.tenant_scope,
    peer.allow_tenant_override,
    peer.join_profile_enabled,
    peer.entity_status,
    count(pas.attribute_schema_id) FILTER (WHERE ((pas.attribute_status = 'active'::text) AND (pas.tenant_id IS NULL))) AS global_attribute_count,
    count(pas.attribute_schema_id) FILTER (WHERE ((pas.attribute_status = 'active'::text) AND (pas.tenant_id IS NOT NULL))) AS tenant_override_attribute_count,
    count(DISTINCT pejp.join_profile_id) FILTER (WHERE (pejp.profile_status = 'active'::text)) AS active_join_profile_count,
    peer.created_at,
    peer.updated_at
   FROM ((public.platform_extensible_entity_registry peer
     LEFT JOIN public.platform_extensible_attribute_schema pas ON ((pas.entity_id = peer.entity_id)))
     LEFT JOIN public.platform_extensible_join_profile pejp ON ((pejp.entity_id = peer.entity_id)))
  GROUP BY peer.entity_id, peer.entity_code, peer.entity_label, peer.owner_module_code, peer.target_relation_schema, peer.target_relation_name, peer.primary_key_column, peer.tenant_scope, peer.allow_tenant_override, peer.join_profile_enabled, peer.entity_status, peer.created_at, peer.updated_at;


create or replace view "public"."platform_rm_fbp_benefit_catalog" as  SELECT tenant_id,
    benefit_id,
    benefit_code,
    benefit_name,
    benefit_category,
    tax_regime_applicability,
    benefit_status,
    updated_at
   FROM public.platform_fbp_benefit_catalog_rows() platform_fbp_benefit_catalog_rows(tenant_id, benefit_id, benefit_code, benefit_name, benefit_category, tax_regime_applicability, benefit_status, updated_at);


create or replace view "public"."platform_rm_fbp_claim_queue" as  SELECT tenant_id,
    claim_id,
    employee_id,
    employee_code,
    claim_code,
    claim_status,
    claimed_amount,
    approved_amount,
    expense_date,
    benefit_code,
    created_at,
    updated_at
   FROM public.platform_fbp_claim_queue_rows() platform_fbp_claim_queue_rows(tenant_id, claim_id, employee_id, employee_code, claim_code, claim_status, claimed_amount, approved_amount, expense_date, benefit_code, created_at, updated_at);


create or replace view "public"."platform_rm_fbp_employee_dashboard" as  SELECT tenant_id,
    employee_id,
    employee_code,
    employee_name,
    financial_year,
    employee_assignment_id,
    policy_code,
    elected_tax_regime,
    total_allocated_amount,
    total_declared_amount,
    total_utilized_amount,
    total_pending_reimbursement_amount,
    total_balance_amount,
    latest_declaration_status,
    updated_at
   FROM public.platform_fbp_employee_dashboard_rows() platform_fbp_employee_dashboard_rows(tenant_id, employee_id, employee_code, employee_name, financial_year, employee_assignment_id, policy_code, elected_tax_regime, total_allocated_amount, total_declared_amount, total_utilized_amount, total_pending_reimbursement_amount, total_balance_amount, latest_declaration_status, updated_at);


create or replace view "public"."platform_rm_fbp_monthly_ledger" as  SELECT tenant_id,
    employee_id,
    employee_code,
    declaration_item_id,
    benefit_code,
    payroll_period,
    monthly_deduction_amount,
    reimbursed_amount,
    ledger_status,
    processed_at
   FROM public.platform_fbp_monthly_ledger_rows() platform_fbp_monthly_ledger_rows(tenant_id, employee_id, employee_code, declaration_item_id, benefit_code, payroll_period, monthly_deduction_amount, reimbursed_amount, ledger_status, processed_at);


create or replace view "public"."platform_rm_fbp_pending_approvals" as  SELECT tenant_id,
    queue_kind,
    reference_id,
    employee_id,
    employee_code,
    employee_name,
    reference_code,
    current_status,
    amount,
    created_at,
    updated_at
   FROM public.platform_fbp_pending_approval_rows() platform_fbp_pending_approval_rows(tenant_id, queue_kind, reference_id, employee_id, employee_code, employee_name, reference_code, current_status, amount, created_at, updated_at);


create or replace view "public"."platform_rm_fbp_policy_catalog" as  SELECT tenant_id,
    policy_id,
    policy_code,
    policy_name,
    policy_tax_regime,
    total_annual_limit,
    benefit_count,
    policy_status,
    updated_at
   FROM public.platform_fbp_policy_catalog_rows() platform_fbp_policy_catalog_rows(tenant_id, policy_id, policy_code, policy_name, policy_tax_regime, total_annual_limit, benefit_count, policy_status, updated_at);


create or replace view "public"."platform_rm_fbp_yearend_settlement_status" as  SELECT tenant_id,
    employee_id,
    employee_code,
    declaration_id,
    financial_year,
    settlement_type,
    unutilized_amount,
    taxable_unutilized_amount,
    processed_in_payroll_period,
    settlement_status,
    processed_at
   FROM public.platform_fbp_yearend_settlement_status_rows() platform_fbp_yearend_settlement_status_rows(tenant_id, employee_id, employee_code, declaration_id, financial_year, settlement_type, unutilized_amount, taxable_unutilized_amount, processed_in_payroll_period, settlement_status, processed_at);


create or replace view "public"."platform_rm_gateway_operation_catalog" as  SELECT pgo.operation_code,
    pgo.operation_mode,
    pgo.dispatch_kind,
    pgo.operation_status,
    pgo.route_policy,
    pgo.tenant_requirement,
    pgo.idempotency_policy,
    pgo.rate_limit_policy,
    pgo.max_limit_per_request,
    pgo.binding_ref,
    pgo.group_name,
    pgo.synopsis,
    pgo.description,
    pgo.dispatch_config,
    pgo.static_params,
    pgo.request_contract,
    pgo.response_contract,
    pgo.metadata,
    pgo.created_at,
    pgo.updated_at,
    COALESCE(array_agg(pgor.role_code ORDER BY pgor.role_code) FILTER (WHERE (pgor.role_code IS NOT NULL)), '{}'::text[]) AS allowed_role_codes
   FROM (public.platform_gateway_operation pgo
     LEFT JOIN public.platform_gateway_operation_role pgor ON ((pgor.operation_code = pgo.operation_code)))
  GROUP BY pgo.operation_code, pgo.operation_mode, pgo.dispatch_kind, pgo.operation_status, pgo.route_policy, pgo.tenant_requirement, pgo.idempotency_policy, pgo.rate_limit_policy, pgo.max_limit_per_request, pgo.binding_ref, pgo.group_name, pgo.synopsis, pgo.description, pgo.dispatch_config, pgo.static_params, pgo.request_contract, pgo.response_contract, pgo.metadata, pgo.created_at, pgo.updated_at;


create or replace view "public"."platform_rm_hierarchy_operational_occupancy" as  SELECT tenant_id,
    position_id,
    position_code,
    position_name,
    reporting_position_id,
    employee_id,
    employee_code,
    actor_user_id,
    employee_name,
    occupancy_id,
    occupancy_role,
    effective_start_date,
    effective_end_date,
    service_state,
    employment_status,
    active_occupancy_count,
    overlap_count,
    is_operational_occupant
   FROM public.platform_hierarchy_operational_occupancy_rows() platform_hierarchy_operational_occupancy_rows(tenant_id, position_id, position_code, position_name, reporting_position_id, employee_id, employee_code, actor_user_id, employee_name, occupancy_id, occupancy_role, effective_start_date, effective_end_date, service_state, employment_status, active_occupancy_count, overlap_count, is_operational_occupant);


create or replace view "public"."platform_rm_hierarchy_position_catalog" as  SELECT tenant_id,
    position_id,
    position_code,
    position_name,
    position_group_id,
    position_group_code,
    position_group_name,
    reporting_position_id,
    hierarchy_path,
    hierarchy_level,
    position_status,
    effective_start_date,
    effective_end_date,
    active_occupancy_count,
    direct_report_count
   FROM public.platform_hierarchy_position_catalog_rows() platform_hierarchy_position_catalog_rows(tenant_id, position_id, position_code, position_name, position_group_id, position_group_code, position_group_name, reporting_position_id, hierarchy_path, hierarchy_level, position_status, effective_start_date, effective_end_date, active_occupancy_count, direct_report_count);


create or replace view "public"."platform_rm_hierarchy_position_group_catalog" as  SELECT tenant_id,
    position_group_id,
    position_group_code,
    position_group_name,
    group_status,
    description,
    total_position_count,
    active_position_count,
    created_at,
    updated_at
   FROM public.platform_hierarchy_position_group_catalog_rows() platform_hierarchy_position_group_catalog_rows(tenant_id, position_group_id, position_group_code, position_group_name, group_status, description, total_position_count, active_position_count, created_at, updated_at);


create or replace view "public"."platform_rm_hierarchy_team_scope" as  SELECT child.tenant_id,
    child.reporting_position_id AS manager_position_id,
    manager.employee_id AS manager_employee_id,
    manager.actor_user_id AS manager_actor_user_id,
    manager.employee_code AS manager_employee_code,
    manager.employee_name AS manager_employee_name,
    child.position_id AS team_member_position_id,
    child.position_code AS team_member_position_code,
    member.employee_id AS team_member_employee_id,
    member.actor_user_id AS team_member_actor_user_id,
    member.employee_code AS team_member_employee_code,
    member.employee_name AS team_member_employee_name
   FROM ((public.platform_rm_hierarchy_position_catalog child
     JOIN public.platform_rm_hierarchy_operational_occupancy member ON (((member.position_id = child.position_id) AND member.is_operational_occupant)))
     LEFT JOIN public.platform_rm_hierarchy_operational_occupancy manager ON (((manager.position_id = child.reporting_position_id) AND manager.is_operational_occupant)))
  WHERE (child.reporting_position_id IS NOT NULL);


create or replace view "public"."platform_rm_import_session_overview" as  SELECT pis.import_session_id,
    pis.tenant_id,
    pec.contract_code,
    peer.entity_code,
    pis.requested_by_actor_user_id,
    pis.upload_intent_id,
    pis.source_document_id,
    pis.idempotency_key,
    pis.source_file_name,
    pis.content_type,
    pis.expected_size_bytes,
    pis.session_status,
    pis.staging_row_count,
    pis.ready_row_count,
    pis.invalid_row_count,
    pis.duplicate_row_count,
    pis.commit_requested_at,
    pis.committed_at,
    pivs.total_rows,
    pivs.committed_rows,
    pivs.failed_rows,
    pis.preview_summary,
    pis.validation_summary,
    pis.expires_at,
    pis.created_at,
    pis.updated_at
   FROM (((public.platform_import_session pis
     JOIN public.platform_exchange_contract pec ON ((pec.contract_id = pis.contract_id)))
     JOIN public.platform_extensible_entity_registry peer ON ((peer.entity_id = pec.entity_id)))
     LEFT JOIN public.platform_import_validation_summary pivs ON ((pivs.import_session_id = pis.import_session_id)));


create or replace view "public"."platform_rm_import_validation_summary" as  SELECT pivs.validation_summary_id,
    pivs.import_session_id,
    pivs.tenant_id,
    pec.contract_code,
    peer.entity_code,
    pivs.total_rows,
    pivs.ready_rows,
    pivs.invalid_rows,
    pivs.duplicate_rows,
    pivs.committed_rows,
    pivs.failed_rows,
    pivs.summary_payload,
    pivs.generated_at,
    pivs.updated_at
   FROM (((public.platform_import_validation_summary pivs
     JOIN public.platform_import_session pis ON ((pis.import_session_id = pivs.import_session_id)))
     JOIN public.platform_exchange_contract pec ON ((pec.contract_id = pis.contract_id)))
     JOIN public.platform_extensible_entity_registry peer ON ((peer.entity_id = pec.entity_id)));


create or replace view "public"."platform_rm_lms_employee_balance_summary" as  SELECT tenant_id,
    employee_id,
    employee_code,
    employee_name,
    position_id,
    leave_type_id,
    leave_type_code,
    leave_type_name,
    current_balance,
    accrued_quantity,
    debited_quantity,
    reversed_quantity,
    lapsed_quantity,
    last_transaction_at
   FROM public.platform_lms_employee_balance_summary_rows() platform_lms_employee_balance_summary_rows(tenant_id, employee_id, employee_code, employee_name, position_id, leave_type_id, leave_type_code, leave_type_name, current_balance, accrued_quantity, debited_quantity, reversed_quantity, lapsed_quantity, last_transaction_at);


create or replace view "public"."platform_rm_lms_leave_history" as  SELECT tenant_id,
    leave_request_id,
    employee_id,
    employee_code,
    employee_name,
    position_id,
    leave_type_id,
    leave_type_code,
    leave_type_name,
    leave_policy_id,
    leave_policy_code,
    request_status,
    request_start_date,
    request_end_date,
    request_session,
    request_days_working,
    request_days_calendar,
    current_approver_position_id,
    current_approver_actor_user_id,
    created_at,
    approved_at,
    cancelled_at
   FROM public.platform_lms_leave_history_rows() platform_lms_leave_history_rows(tenant_id, leave_request_id, employee_id, employee_code, employee_name, position_id, leave_type_id, leave_type_code, leave_type_name, leave_policy_id, leave_policy_code, request_status, request_start_date, request_end_date, request_session, request_days_working, request_days_calendar, current_approver_position_id, current_approver_actor_user_id, created_at, approved_at, cancelled_at);


create or replace view "public"."platform_rm_lms_pending_approvals" as  SELECT tenant_id,
    leave_request_id,
    request_status,
    employee_id,
    employee_code,
    employee_name,
    leave_type_code,
    request_start_date,
    request_end_date,
    request_days_working,
    current_approver_position_id,
    current_approver_actor_user_id,
    created_at
   FROM public.platform_lms_pending_approval_rows() platform_lms_pending_approval_rows(tenant_id, leave_request_id, request_status, employee_id, employee_code, employee_name, leave_type_code, request_start_date, request_end_date, request_days_working, current_approver_position_id, current_approver_actor_user_id, created_at);


create or replace view "public"."platform_rm_lms_policy_catalog" as  SELECT tenant_id,
    leave_type_id,
    leave_type_code,
    leave_type_name,
    leave_policy_id,
    leave_policy_code,
    leave_policy_name,
    policy_status,
    effective_from,
    effective_to,
    requires_approval,
    assignment_count,
    created_at,
    updated_at
   FROM public.platform_lms_policy_catalog_rows() platform_lms_policy_catalog_rows(tenant_id, leave_type_id, leave_type_code, leave_type_name, leave_policy_id, leave_policy_code, leave_policy_name, policy_status, effective_from, effective_to, requires_approval, assignment_count, created_at, updated_at);


create or replace view "public"."platform_rm_lms_team_leave_queue" as  SELECT tenant_id,
    manager_actor_user_id,
    manager_employee_id,
    team_member_employee_id,
    team_member_employee_code,
    team_member_employee_name,
    leave_request_id,
    request_status,
    leave_type_code,
    request_start_date,
    request_end_date,
    request_days_working,
    created_at
   FROM public.platform_lms_team_leave_queue_rows() platform_lms_team_leave_queue_rows(tenant_id, manager_actor_user_id, manager_employee_id, team_member_employee_id, team_member_employee_code, team_member_employee_name, leave_request_id, request_status, leave_type_code, request_start_date, request_end_date, request_days_working, created_at);


create or replace view "public"."platform_rm_lwf_batch_catalog" as  SELECT tenant_id,
    batch_id,
    state_code,
    payroll_period,
    batch_source,
    batch_status,
    requested_count,
    processed_count,
    synced_count,
    error_count,
    updated_at
   FROM public.platform_lwf_batch_catalog_rows() platform_lwf_batch_catalog_rows(tenant_id, batch_id, state_code, payroll_period, batch_source, batch_status, requested_count, processed_count, synced_count, error_count, updated_at);


create or replace view "public"."platform_rm_lwf_compliance_summary" as  SELECT tenant_id,
    summary_id,
    state_code,
    payroll_period,
    total_employees,
    overridden_count,
    synced_count,
    total_eligible_wages,
    total_employee_contribution,
    total_employer_contribution,
    total_liability,
    refreshed_at
   FROM public.platform_lwf_compliance_summary_rows() platform_lwf_compliance_summary_rows(tenant_id, summary_id, state_code, payroll_period, total_employees, overridden_count, synced_count, total_eligible_wages, total_employee_contribution, total_employer_contribution, total_liability, refreshed_at);


create or replace view "public"."platform_rm_lwf_configuration_catalog" as  SELECT tenant_id,
    configuration_id,
    state_code,
    effective_from,
    effective_to,
    deduction_frequency,
    configuration_status,
    configuration_version,
    updated_at
   FROM public.platform_lwf_configuration_catalog_rows() platform_lwf_configuration_catalog_rows(tenant_id, configuration_id, state_code, effective_from, effective_to, deduction_frequency, configuration_status, configuration_version, updated_at);


create or replace view "public"."platform_rm_lwf_contribution_ledger" as  SELECT tenant_id,
    contribution_ledger_id,
    batch_id,
    employee_id,
    employee_code,
    payroll_period,
    state_code,
    eligible_wages,
    final_employee_contribution,
    final_employer_contribution,
    override_status,
    sync_status
   FROM public.platform_lwf_contribution_ledger_rows() platform_lwf_contribution_ledger_rows(tenant_id, contribution_ledger_id, batch_id, employee_id, employee_code, payroll_period, state_code, eligible_wages, final_employee_contribution, final_employer_contribution, override_status, sync_status);


create or replace view "public"."platform_rm_lwf_dead_letter_queue" as  SELECT tenant_id,
    dead_letter_id,
    batch_id,
    employee_id,
    employee_code,
    error_code,
    resolution_status,
    created_at
   FROM public.platform_lwf_dead_letter_queue_rows() platform_lwf_dead_letter_queue_rows(tenant_id, dead_letter_id, batch_id, employee_id, employee_code, error_code, resolution_status, created_at);


create or replace view "public"."platform_rm_membership_invitation_overview" as  SELECT pmi.invitation_id,
    pmi.tenant_id,
    pt.tenant_code,
    pmi.invited_email,
    pmi.invited_mobile,
    pmi.role_code,
    pmi.invitation_status,
    pmi.expires_at,
    pmi.claimed_at,
    pmi.claimed_by_user_id,
    pmi.created_at,
    pmi.updated_at
   FROM (public.platform_membership_invitation pmi
     JOIN public.platform_tenant pt ON ((pt.tenant_id = pmi.tenant_id)));


create or replace view "public"."platform_rm_pay_structure_catalog" as  SELECT tenant_id,
    pay_structure_id,
    payroll_area_id,
    structure_code,
    structure_name,
    structure_status,
    active_version_no,
    component_count,
    effective_from,
    effective_to,
    updated_at
   FROM public.platform_pay_structure_catalog_rows() platform_pay_structure_catalog_rows(tenant_id, pay_structure_id, payroll_area_id, structure_code, structure_name, structure_status, active_version_no, component_count, effective_from, effective_to, updated_at);


create or replace view "public"."platform_rm_payroll_area_catalog" as  SELECT tenant_id,
    payroll_area_id,
    area_code,
    area_name,
    payroll_frequency,
    currency_code,
    country_code,
    area_status,
    area_metadata,
    created_at,
    updated_at
   FROM public.platform_payroll_area_catalog_rows() platform_payroll_area_catalog_rows(tenant_id, payroll_area_id, area_code, area_name, payroll_frequency, currency_code, country_code, area_status, area_metadata, created_at, updated_at);


create or replace view "public"."platform_rm_payroll_batch_catalog" as  SELECT tenant_id,
    payroll_batch_id,
    payroll_period,
    processing_type,
    batch_status,
    total_employees,
    processed_employees,
    failed_employees,
    gross_earnings,
    total_deductions,
    net_pay,
    processed_at,
    finalized_at,
    last_error,
    updated_at
   FROM public.platform_payroll_batch_catalog_rows() platform_payroll_batch_catalog_rows(tenant_id, payroll_batch_id, payroll_period, processing_type, batch_status, total_employees, processed_employees, failed_employees, gross_earnings, total_deductions, net_pay, processed_at, finalized_at, last_error, updated_at);


create or replace view "public"."platform_rm_payroll_result_summary" as  SELECT tenant_id,
    payroll_batch_id,
    payroll_period,
    employee_id,
    employee_code,
    gross_earnings,
    total_deductions,
    employer_contributions,
    net_pay,
    batch_status,
    updated_at
   FROM public.platform_payroll_result_summary_rows() platform_payroll_result_summary_rows(tenant_id, payroll_batch_id, payroll_period, employee_id, employee_code, gross_earnings, total_deductions, employer_contributions, net_pay, batch_status, updated_at);


create or replace view "public"."platform_rm_payslip_run_status" as  SELECT tenant_id,
    payslip_run_id,
    payroll_batch_id,
    payroll_period,
    run_status,
    total_items,
    completed_items,
    failed_items,
    dead_letter_items,
    completed_at,
    updated_at
   FROM public.platform_payslip_run_status_rows() platform_payslip_run_status_rows(tenant_id, payslip_run_id, payroll_batch_id, payroll_period, run_status, total_items, completed_items, failed_items, dead_letter_items, completed_at, updated_at);


create or replace view "public"."platform_rm_pf_anomaly_queue" as  SELECT tenant_id,
    anomaly_id,
    batch_id,
    employee_id,
    employee_code,
    anomaly_code,
    severity,
    anomaly_status,
    anomaly_message,
    created_at
   FROM public.platform_pf_anomaly_queue_rows() platform_pf_anomaly_queue_rows(tenant_id, anomaly_id, batch_id, employee_id, employee_code, anomaly_code, severity, anomaly_status, anomaly_message, created_at);


create or replace view "public"."platform_rm_pf_batch_catalog" as  SELECT tenant_id,
    batch_id,
    establishment_id,
    payroll_period,
    batch_status,
    processed_count,
    anomaly_count,
    skipped_count,
    created_at,
    updated_at
   FROM public.platform_pf_batch_catalog_rows() platform_pf_batch_catalog_rows(tenant_id, batch_id, establishment_id, payroll_period, batch_status, processed_count, anomaly_count, skipped_count, created_at, updated_at);


create or replace view "public"."platform_rm_pf_contribution_ledger" as  SELECT tenant_id,
    contribution_ledger_id,
    batch_id,
    employee_id,
    employee_code,
    payroll_period,
    employee_share,
    employer_share,
    eps_share,
    epf_share,
    sync_status
   FROM public.platform_pf_contribution_ledger_rows() platform_pf_contribution_ledger_rows(tenant_id, contribution_ledger_id, batch_id, employee_id, employee_code, payroll_period, employee_share, employer_share, eps_share, epf_share, sync_status);


create or replace view "public"."platform_rm_pf_ecr_run_status" as  SELECT tenant_id,
    ecr_run_id,
    batch_id,
    establishment_id,
    payroll_period,
    run_status,
    row_count,
    template_document_id,
    generated_document_id,
    updated_at
   FROM public.platform_pf_ecr_run_status_rows() platform_pf_ecr_run_status_rows(tenant_id, ecr_run_id, batch_id, establishment_id, payroll_period, run_status, row_count, template_document_id, generated_document_id, updated_at);


create or replace view "public"."platform_rm_pf_enrollment_status" as  SELECT tenant_id,
    enrollment_id,
    employee_id,
    employee_code,
    establishment_id,
    enrollment_status,
    uan,
    pf_member_id,
    effective_from,
    effective_to
   FROM public.platform_pf_enrollment_status_rows() platform_pf_enrollment_status_rows(tenant_id, enrollment_id, employee_id, employee_code, establishment_id, enrollment_status, uan, pf_member_id, effective_from, effective_to);


create or replace view "public"."platform_rm_pf_establishment_catalog" as  SELECT tenant_id,
    establishment_id,
    establishment_code,
    establishment_name,
    pf_office_code,
    establishment_status,
    active_enrollment_count
   FROM public.platform_pf_establishment_catalog_rows() platform_pf_establishment_catalog_rows(tenant_id, establishment_id, establishment_code, establishment_name, pf_office_code, establishment_status, active_enrollment_count);


create or replace view "public"."platform_rm_ptax_arrear_queue" as  SELECT tenant_id,
    arrear_case_id,
    employee_id,
    employee_code,
    state_code,
    from_period,
    to_period,
    arrear_status,
    target_payroll_period,
    total_delta,
    updated_at
   FROM public.platform_ptax_arrear_queue_rows() platform_ptax_arrear_queue_rows(tenant_id, arrear_case_id, employee_id, employee_code, state_code, from_period, to_period, arrear_status, target_payroll_period, total_delta, updated_at);


create or replace view "public"."platform_rm_ptax_batch_catalog" as  SELECT tenant_id,
    batch_id,
    state_code,
    payroll_period,
    batch_status,
    processed_count,
    synced_count,
    skipped_count,
    error_count,
    updated_at
   FROM public.platform_ptax_batch_catalog_rows() platform_ptax_batch_catalog_rows(tenant_id, batch_id, state_code, payroll_period, batch_status, processed_count, synced_count, skipped_count, error_count, updated_at);


create or replace view "public"."platform_rm_ptax_configuration_catalog" as  SELECT tenant_id,
    configuration_id,
    state_code,
    effective_from,
    effective_to,
    deduction_frequency,
    configuration_status,
    configuration_version,
    updated_at
   FROM public.platform_ptax_configuration_catalog_rows() platform_ptax_configuration_catalog_rows(tenant_id, configuration_id, state_code, effective_from, effective_to, deduction_frequency, configuration_status, configuration_version, updated_at);


create or replace view "public"."platform_rm_ptax_contribution_ledger" as  SELECT tenant_id,
    contribution_ledger_id,
    batch_id,
    employee_id,
    employee_code,
    payroll_period,
    state_code,
    taxable_wages,
    deduction_amount,
    sync_status
   FROM public.platform_ptax_contribution_ledger_rows() platform_ptax_contribution_ledger_rows(tenant_id, contribution_ledger_id, batch_id, employee_id, employee_code, payroll_period, state_code, taxable_wages, deduction_amount, sync_status);


create or replace view "public"."platform_rm_rcm_candidate_pipeline" as  SELECT tenant_id,
    application_id,
    requisition_id,
    requisition_code,
    candidate_id,
    candidate_code,
    candidate_name,
    primary_email,
    current_stage_code,
    application_status,
    target_position_id,
    target_position_code,
    conversion_case_id,
    conversion_status,
    wcm_employee_id,
    employee_code,
    applied_on,
    converted_at,
    updated_at
   FROM public.platform_rcm_candidate_pipeline_rows() platform_rcm_candidate_pipeline_rows(tenant_id, application_id, requisition_id, requisition_code, candidate_id, candidate_code, candidate_name, primary_email, current_stage_code, application_status, target_position_id, target_position_code, conversion_case_id, conversion_status, wcm_employee_id, employee_code, applied_on, converted_at, updated_at);


create or replace view "public"."platform_rm_rcm_conversion_queue" as  SELECT tenant_id,
    conversion_case_id,
    application_id,
    requisition_id,
    requisition_code,
    candidate_id,
    candidate_code,
    candidate_name,
    target_position_id,
    target_position_code,
    conversion_status,
    prepared_at,
    converted_at,
    wcm_employee_id,
    employee_code,
    current_stage_code,
    application_status
   FROM public.platform_rcm_conversion_queue_rows() platform_rcm_conversion_queue_rows(tenant_id, conversion_case_id, application_id, requisition_id, requisition_code, candidate_id, candidate_code, candidate_name, target_position_id, target_position_code, conversion_status, prepared_at, converted_at, wcm_employee_id, employee_code, current_stage_code, application_status);


create or replace view "public"."platform_rm_rcm_requisition_catalog" as  SELECT tenant_id,
    requisition_id,
    requisition_code,
    requisition_title,
    position_id,
    position_code,
    position_name,
    requisition_status,
    openings_count,
    filled_count,
    open_application_count,
    target_start_date,
    priority_code,
    created_at,
    updated_at
   FROM public.platform_rcm_requisition_catalog_rows() platform_rcm_requisition_catalog_rows(tenant_id, requisition_id, requisition_code, requisition_title, position_id, position_code, position_name, requisition_status, openings_count, filled_count, open_application_count, target_start_date, priority_code, created_at, updated_at);


create or replace view "public"."platform_rm_refresh_status" as  SELECT c.read_model_code,
    c.module_code,
    c.read_model_name,
    c.schema_placement,
    c.storage_kind,
    c.ownership_scope,
    c.object_name,
    c.refresh_strategy,
    c.refresh_mode,
    c.refresh_owner_code,
    c.refresh_function_name,
    c.freshness_sla_seconds,
    COALESCE(s.scope_key,
        CASE
            WHEN (c.ownership_scope = 'platform_shared'::text) THEN 'platform_shared'::text
            ELSE 'tenant_uninitialized'::text
        END) AS scope_key,
    s.tenant_id,
    COALESCE(s.refresh_status, 'never_run'::text) AS refresh_status,
    s.active_run_id,
    s.last_requested_at,
    s.last_started_at,
    s.last_completed_at,
    s.last_succeeded_at,
    s.last_failed_at,
    s.last_duration_ms,
    s.last_row_count,
    s.last_error_code,
    s.last_error_message,
        CASE
            WHEN (c.storage_kind = 'view'::text) THEN false
            WHEN (c.freshness_sla_seconds IS NULL) THEN false
            WHEN (s.last_succeeded_at IS NULL) THEN true
            WHEN (timezone('utc'::text, now()) > (s.last_succeeded_at + make_interval(secs => (c.freshness_sla_seconds)::double precision))) THEN true
            ELSE false
        END AS is_stale
   FROM (public.platform_read_model_catalog c
     LEFT JOIN public.platform_read_model_refresh_state s ON ((s.read_model_code = c.read_model_code)));


create or replace view "public"."platform_rm_signup_request_status" as  SELECT psr.signup_request_id,
    psr.request_status,
    psr.email,
    psr.mobile_no,
    psr.decision_reason,
    psr.created_at,
    psr.completed_at,
    psr.invitation_id,
    pmi.tenant_id,
    pt.tenant_code
   FROM ((public.platform_signup_request psr
     LEFT JOIN public.platform_membership_invitation pmi ON ((pmi.invitation_id = psr.invitation_id)))
     LEFT JOIN public.platform_tenant pt ON ((pt.tenant_id = pmi.tenant_id)));


create or replace view "public"."platform_rm_storage_bucket_catalog" as  SELECT psbc.bucket_code,
    psbc.bucket_name,
    psbc.bucket_purpose,
    psbc.bucket_visibility,
    psbc.protection_mode,
    psbc.file_size_limit_bytes,
    psbc.allowed_mime_types,
    psbc.retention_days,
    psbc.bucket_status,
    psbc.metadata,
    psbc.created_at,
    psbc.updated_at,
    (sb.id IS NOT NULL) AS storage_bucket_present,
    sb.public AS storage_public_flag,
    sb.file_size_limit AS storage_file_size_limit,
    sb.allowed_mime_types AS storage_allowed_mime_types
   FROM (public.platform_storage_bucket_catalog psbc
     LEFT JOIN storage.buckets sb ON ((sb.id = psbc.bucket_name)));


create or replace view "public"."platform_rm_tps_batch_catalog" as  SELECT tenant_id,
    batch_id,
    payroll_period,
    batch_status,
    frozen_at,
    processed_at,
    finalized_at,
    total_employees,
    stale_summary_count,
    aggregate_payable_days,
    aggregate_lop_days,
    aggregate_paid_leave_days,
    aggregate_overtime_hours,
    last_error,
    updated_at
   FROM public.platform_tps_batch_catalog_rows() platform_tps_batch_catalog_rows(tenant_id, batch_id, payroll_period, batch_status, frozen_at, processed_at, finalized_at, total_employees, stale_summary_count, aggregate_payable_days, aggregate_lop_days, aggregate_paid_leave_days, aggregate_overtime_hours, last_error, updated_at);


create or replace view "public"."platform_rm_tps_employee_period_summary" as  SELECT tenant_id,
    batch_id,
    payroll_period,
    employee_id,
    employee_code,
    batch_status,
    payable_days,
    lop_days,
    paid_leave_days,
    total_overtime_hours,
    is_stale,
    source_data_hash,
    last_source_change,
    processed_at,
    updated_at
   FROM public.platform_tps_employee_period_summary_rows() platform_tps_employee_period_summary_rows(tenant_id, batch_id, payroll_period, employee_id, employee_code, batch_status, payable_days, lop_days, paid_leave_days, total_overtime_hours, is_stale, source_data_hash, last_source_change, processed_at, updated_at);


create or replace view "public"."platform_rm_tps_period_status_overview" as  SELECT tenant_id,
    payroll_period,
    batch_id,
    batch_status,
    processed_at,
    finalized_at,
    total_employees,
    stale_summaries,
    aggregate_payable_days,
    aggregate_lop_days,
    aggregate_paid_leave_days,
    aggregate_overtime_hours
   FROM public.platform_tps_period_status_overview_rows() platform_tps_period_status_overview_rows(tenant_id, payroll_period, batch_id, batch_status, processed_at, finalized_at, total_employees, stale_summaries, aggregate_payable_days, aggregate_lop_days, aggregate_paid_leave_days, aggregate_overtime_hours);


create or replace view "public"."platform_rm_tps_queue_health_current" as  SELECT tenant_id,
    checked_at,
    queued_count,
    running_count,
    retry_wait_count,
    dead_letter_count,
    stale_lease_count,
    stale_summary_count,
    processing_batches_over_30m,
    severity,
    details
   FROM public.platform_tps_queue_health_current_rows() platform_tps_queue_health_current_rows(tenant_id, checked_at, queued_count, running_count, retry_wait_count, dead_letter_count, stale_lease_count, stale_summary_count, processing_batches_over_30m, severity, details);


create or replace view "public"."platform_rm_wcm_employee_catalog" as  SELECT tenant_id,
    employee_id,
    employee_code,
    first_name,
    middle_name,
    last_name,
    official_email,
    actor_user_id,
    service_state,
    employment_status,
    joining_date,
    confirmation_date,
    leaving_date,
    relief_date,
    separation_type,
    full_and_final_status,
    full_and_final_process_date,
    position_id,
    last_billable,
    current_billable,
    created_at,
    updated_at,
    state_updated_at
   FROM public.platform_wcm_employee_catalog_rows() platform_wcm_employee_catalog_rows(tenant_id, employee_id, employee_code, first_name, middle_name, last_name, official_email, actor_user_id, service_state, employment_status, joining_date, confirmation_date, leaving_date, relief_date, separation_type, full_and_final_status, full_and_final_process_date, position_id, last_billable, current_billable, created_at, updated_at, state_updated_at);


create or replace view "public"."platform_rm_wcm_service_state_overview" as  SELECT tenant_id,
    employee_id,
    employee_code,
    actor_user_id,
    service_state,
    employment_status,
    joining_date,
    confirmation_date,
    leaving_date,
    relief_date,
    separation_type,
    full_and_final_status,
    full_and_final_process_date,
    position_id,
    last_billable,
    current_billable,
    state_updated_at
   FROM public.platform_rm_wcm_employee_catalog;


create or replace view "public"."platform_schema_provisioning_view" as  SELECT pt.tenant_id,
    pt.tenant_code,
    pt.schema_name,
    pt.display_name,
    pt.tenant_kind,
    pp.provisioning_status,
    pp.schema_provisioned,
    pp.foundation_version,
    pp.ready_for_routing,
    pp.latest_completed_step,
    pp.last_error_code,
    pp.last_error_message,
    pp.last_error_at,
    public.platform_schema_exists(pt.schema_name) AS schema_exists,
    COALESCE(( SELECT jsonb_agg(jsonb_build_object('template_version', ptv.template_version, 'schema_name', ptv.schema_name, 'apply_status', ptv.apply_status, 'applied_at', ptv.applied_at) ORDER BY ptv.applied_at, ptv.template_version) AS jsonb_agg
           FROM public.platform_tenant_template_version ptv
          WHERE (ptv.tenant_id = pt.tenant_id)), '[]'::jsonb) AS applied_versions,
    ( SELECT jsonb_build_object('run_id', pspr.run_id, 'operation_kind', pspr.operation_kind, 'template_version', pspr.template_version, 'run_status', pspr.run_status, 'started_at', pspr.started_at, 'finished_at', pspr.finished_at, 'error_code', pspr.error_code, 'error_message', pspr.error_message, 'details', pspr.details) AS jsonb_build_object
           FROM public.platform_schema_provisioning_run pspr
          WHERE (pspr.tenant_id = pt.tenant_id)
          ORDER BY pspr.started_at DESC, pspr.run_id DESC
         LIMIT 1) AS latest_run
   FROM (public.platform_tenant pt
     JOIN public.platform_tenant_provisioning pp ON ((pp.tenant_id = pt.tenant_id)));


create or replace view "public"."platform_tenant_commercial_state_view" as  WITH latest_invoice AS (
         SELECT DISTINCT ON (pi.tenant_id) pi.tenant_id,
            pi.id AS latest_invoice_id,
            pi.invoice_no,
            pi.invoice_status,
            pi.issue_date,
            pi.due_date,
            pi.total_amount,
            pi.paid_amount,
            pi.balance_amount
           FROM public.platform_invoice pi
          ORDER BY pi.tenant_id, pi.issue_date DESC, pi.created_at DESC
        )
 SELECT pt.tenant_id,
    pt.tenant_code,
    pca.commercial_status,
    pca.dues_state,
    pca.overdue_since,
    pca.dormant_access_from,
    pca.background_stop_from,
    pca.last_invoiced_at,
    pca.last_paid_at,
    pca.last_state_synced_at,
    pts.id AS subscription_id,
    pts.subscription_status,
    pts.cycle_anchor_day,
    pts.current_cycle_start,
    pts.current_cycle_end,
    ppc.id AS plan_id,
    ppc.plan_code,
    ppc.plan_name,
    ppc.billing_cadence,
    ppc.currency_code,
    li.latest_invoice_id,
    li.invoice_no AS latest_invoice_no,
    li.invoice_status AS latest_invoice_status,
    li.issue_date AS latest_invoice_issue_date,
    li.due_date AS latest_invoice_due_date,
    li.total_amount AS latest_invoice_total_amount,
    li.paid_amount AS latest_invoice_paid_amount,
    li.balance_amount AS latest_invoice_balance_amount
   FROM ((((public.platform_tenant pt
     LEFT JOIN public.platform_tenant_commercial_account pca ON ((pca.tenant_id = pt.tenant_id)))
     LEFT JOIN public.platform_tenant_subscription pts ON ((pts.tenant_id = pt.tenant_id)))
     LEFT JOIN public.platform_plan_catalog ppc ON ((ppc.id = pts.plan_id)))
     LEFT JOIN latest_invoice li ON ((li.tenant_id = pt.tenant_id)));


create or replace view "public"."platform_tenant_registry_view" as  WITH latest_status AS (
         SELECT DISTINCT ON (h.tenant_id) h.tenant_id,
            h.status_family,
            h.to_status,
            h.transition_reason_code,
            h.changed_at,
            h.source
           FROM public.platform_tenant_status_history h
          ORDER BY h.tenant_id, h.changed_at DESC, h.id DESC
        )
 SELECT pt.tenant_id,
    pt.tenant_code,
    pt.schema_name,
    pt.display_name,
    pt.legal_name,
    pt.default_currency_code,
    pt.default_timezone,
    pt.tenant_kind,
    pt.created_at,
    pt.updated_at,
    pt.created_by,
    pt.metadata,
    ptp.provisioning_status,
    ptp.schema_provisioned,
    ptp.foundation_version,
    ptp.latest_completed_step,
    ptp.last_error_code,
    ptp.last_error_message,
    ptp.last_error_at,
    ptp.ready_for_routing,
    ptp.details AS provisioning_details,
    pas.access_state,
    pas.reason_code,
    pas.reason_details,
    pas.billing_state,
    pas.dormant_started_at,
    pas.background_stop_at,
    pas.restored_at,
    pas.disabled_at,
    pas.terminated_at,
        CASE
            WHEN (ptp.ready_for_routing AND (pas.access_state = 'active'::text)) THEN true
            ELSE false
        END AS client_access_allowed,
        CASE
            WHEN (ptp.ready_for_routing AND (pas.access_state = ANY (ARRAY['active'::text, 'dormant_access_blocked'::text]))) THEN true
            ELSE false
        END AS background_processing_allowed,
    ls.status_family AS latest_transition_family,
    ls.to_status AS latest_transition_status,
    ls.transition_reason_code AS latest_transition_reason_code,
    ls.changed_at AS latest_transition_at,
    ls.source AS latest_transition_source
   FROM (((public.platform_tenant pt
     JOIN public.platform_tenant_provisioning ptp ON ((ptp.tenant_id = pt.tenant_id)))
     JOIN public.platform_tenant_access_state pas ON ((pas.tenant_id = pt.tenant_id)))
     LEFT JOIN latest_status ls ON ((ls.tenant_id = pt.tenant_id)));


create or replace view "public"."platform_actor_tenant_membership_view" as  SELECT patm.tenant_id,
    pt.tenant_code,
    pt.schema_name,
    patm.actor_user_id,
    patm.membership_status,
    patm.routing_status,
    patm.is_default_tenant,
    ptrv.ready_for_routing,
    ptrv.access_state,
    ptrv.client_access_allowed,
    ptrv.background_processing_allowed,
    ptrv.background_stop_at
   FROM ((public.platform_actor_tenant_membership patm
     JOIN public.platform_tenant pt ON ((pt.tenant_id = patm.tenant_id)))
     LEFT JOIN public.platform_tenant_registry_view ptrv ON ((ptrv.tenant_id = patm.tenant_id)));


create or replace view "public"."platform_async_dispatch_readiness_view" as  WITH due_jobs AS (
         SELECT paj.worker_code,
            paj.module_code,
            paj.dispatch_mode,
            paj.tenant_id,
            paj.priority,
                CASE
                    WHEN (paj.job_state = 'queued'::text) THEN paj.available_at
                    ELSE COALESCE(paj.next_retry_at, paj.available_at)
                END AS due_at
           FROM ((public.platform_async_job paj
             JOIN public.platform_tenant_registry_view ptrv ON ((ptrv.tenant_id = paj.tenant_id)))
             JOIN public.platform_async_worker_registry pawr ON ((pawr.worker_code = paj.worker_code)))
          WHERE ((paj.job_state = ANY (ARRAY['queued'::text, 'retry_wait'::text])) AND (ptrv.ready_for_routing = true) AND (ptrv.background_processing_allowed = true) AND (pawr.is_active = true) AND (((paj.job_state = 'queued'::text) AND (paj.available_at <= timezone('utc'::text, now()))) OR ((paj.job_state = 'retry_wait'::text) AND (COALESCE(paj.next_retry_at, paj.available_at) <= timezone('utc'::text, now())))))
        )
 SELECT worker_code,
    module_code,
    dispatch_mode,
    count(*) AS due_job_count,
    min(due_at) AS oldest_due_at,
    min(priority) AS highest_priority
   FROM due_jobs
  GROUP BY worker_code, module_code, dispatch_mode;


create or replace view "public"."platform_rm_actor_access_overview" as  SELECT patmv.actor_user_id,
    pap.primary_email,
    pap.primary_mobile,
    pap.display_name,
    pap.profile_status,
    patmv.tenant_id,
    patmv.tenant_code,
    patmv.schema_name,
    patmv.membership_status,
    patmv.routing_status,
    patmv.is_default_tenant,
    patmv.access_state,
    patmv.client_access_allowed,
    patmv.background_processing_allowed,
    COALESCE(array_agg(parg.role_code ORDER BY parg.role_code) FILTER (WHERE (parg.grant_status = 'active'::text)), '{}'::text[]) AS active_role_codes
   FROM ((public.platform_actor_tenant_membership_view patmv
     LEFT JOIN public.platform_actor_profile pap ON ((pap.actor_user_id = patmv.actor_user_id)))
     LEFT JOIN public.platform_actor_role_grant parg ON (((parg.tenant_id = patmv.tenant_id) AND (parg.actor_user_id = patmv.actor_user_id))))
  GROUP BY patmv.actor_user_id, pap.primary_email, pap.primary_mobile, pap.display_name, pap.profile_status, patmv.tenant_id, patmv.tenant_code, patmv.schema_name, patmv.membership_status, patmv.routing_status, patmv.is_default_tenant, patmv.access_state, patmv.client_access_allowed, patmv.background_processing_allowed;


create or replace view "public"."platform_rm_actor_tenant_membership" as  SELECT tenant_id,
    tenant_code,
    schema_name,
    actor_user_id,
    membership_status,
    routing_status,
    is_default_tenant,
    ready_for_routing,
    access_state,
    client_access_allowed,
    background_processing_allowed,
    background_stop_at
   FROM public.platform_actor_tenant_membership_view;


create or replace view "public"."platform_rm_async_dispatch_readiness" as  SELECT worker_code,
    module_code,
    dispatch_mode,
    due_job_count,
    oldest_due_at,
    highest_priority
   FROM public.platform_async_dispatch_readiness_view;


create or replace view "public"."platform_rm_hierarchy_org_chart" as  SELECT p.tenant_id,
    p.position_id,
    p.position_code,
    p.position_name,
    p.position_group_id,
    p.position_group_code,
    p.position_group_name,
    p.reporting_position_id,
    p.hierarchy_path,
    p.hierarchy_level,
    p.position_status,
    p.active_occupancy_count,
    p.direct_report_count,
    o.employee_id AS operational_employee_id,
    o.employee_code AS operational_employee_code,
    o.actor_user_id AS operational_actor_user_id,
    o.employee_name AS operational_employee_name,
    o.occupancy_role AS operational_occupancy_role,
    o.overlap_count
   FROM (public.platform_rm_hierarchy_position_catalog p
     LEFT JOIN public.platform_rm_hierarchy_operational_occupancy o ON (((o.position_id = p.position_id) AND o.is_operational_occupant)));


create materialized view "public"."platform_rm_refresh_overview" as  SELECT module_code,
    count(DISTINCT read_model_code) AS registered_model_count,
    count(*) FILTER (WHERE (storage_kind = 'view'::text)) AS direct_view_state_rows,
    count(*) FILTER (WHERE (storage_kind <> 'view'::text)) AS refreshable_state_rows,
    count(*) FILTER (WHERE (refresh_status = 'queued'::text)) AS queued_state_rows,
    count(*) FILTER (WHERE (refresh_status = 'running'::text)) AS running_state_rows,
    count(*) FILTER (WHERE (refresh_status = 'failed'::text)) AS failed_state_rows,
    count(*) FILTER (WHERE is_stale) AS stale_state_rows,
    max(last_completed_at) AS last_completed_at
   FROM public.platform_rm_refresh_status
  WHERE (read_model_code <> 'platform_refresh_overview'::text)
  GROUP BY module_code;


create or replace view "public"."platform_rm_schema_provisioning" as  SELECT tenant_id,
    tenant_code,
    schema_name,
    display_name,
    tenant_kind,
    provisioning_status,
    schema_provisioned,
    foundation_version,
    ready_for_routing,
    latest_completed_step,
    last_error_code,
    last_error_message,
    last_error_at,
    schema_exists,
    applied_versions,
    latest_run
   FROM public.platform_schema_provisioning_view;


create or replace view "public"."platform_rm_tenant_commercial_state" as  SELECT tenant_id,
    tenant_code,
    commercial_status,
    dues_state,
    overdue_since,
    dormant_access_from,
    background_stop_from,
    last_invoiced_at,
    last_paid_at,
    last_state_synced_at,
    subscription_id,
    subscription_status,
    cycle_anchor_day,
    current_cycle_start,
    current_cycle_end,
    plan_id,
    plan_code,
    plan_name,
    billing_cadence,
    currency_code,
    latest_invoice_id,
    latest_invoice_no,
    latest_invoice_status,
    latest_invoice_issue_date,
    latest_invoice_due_date,
    latest_invoice_total_amount,
    latest_invoice_paid_amount,
    latest_invoice_balance_amount
   FROM public.platform_tenant_commercial_state_view;


create or replace view "public"."platform_rm_tenant_registry" as  SELECT tenant_id,
    tenant_code,
    schema_name,
    display_name,
    legal_name,
    default_currency_code,
    default_timezone,
    tenant_kind,
    created_at,
    updated_at,
    created_by,
    metadata,
    provisioning_status,
    schema_provisioned,
    foundation_version,
    latest_completed_step,
    last_error_code,
    last_error_message,
    last_error_at,
    ready_for_routing,
    provisioning_details,
    access_state,
    reason_code,
    reason_details,
    billing_state,
    dormant_started_at,
    background_stop_at,
    restored_at,
    disabled_at,
    terminated_at,
    client_access_allowed,
    background_processing_allowed,
    latest_transition_family,
    latest_transition_status,
    latest_transition_reason_code,
    latest_transition_at,
    latest_transition_source
   FROM public.platform_tenant_registry_view;


create or replace view "public"."platform_rm_wcm_billable_state_overview" as  SELECT tenant_id,
    employee_id,
    employee_code,
    service_state,
    employment_status,
    full_and_final_status,
    last_billable,
    current_billable,
    leaving_date,
    relief_date,
    full_and_final_process_date,
    state_updated_at
   FROM public.platform_rm_wcm_service_state_overview;


create or replace view "public"."platform_rm_wcm_headcount_summary" as  SELECT tenant_id,
    count(*) AS employee_count,
    count(*) FILTER (WHERE (service_state = 'active'::text)) AS active_employee_count,
    count(*) FILTER (WHERE current_billable) AS current_billable_count,
    count(*) FILTER (WHERE (service_state = 'inactive'::text)) AS inactive_employee_count,
    count(*) FILTER (WHERE (service_state = 'separated'::text)) AS separated_employee_count
   FROM public.platform_rm_wcm_service_state_overview
  GROUP BY tenant_id;


CREATE TRIGGER trg_platform_access_role_set_updated_at BEFORE UPDATE ON public.platform_access_role FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_actor_profile_set_updated_at BEFORE UPDATE ON public.platform_actor_profile FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_actor_role_grant_set_updated_at BEFORE UPDATE ON public.platform_actor_role_grant FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_actor_tenant_membership_set_updated_at BEFORE UPDATE ON public.platform_actor_tenant_membership FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_async_job_set_updated_at BEFORE UPDATE ON public.platform_async_job FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_async_worker_registry_set_updated_at BEFORE UPDATE ON public.platform_async_worker_registry FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_billing_cycle_set_updated_at BEFORE UPDATE ON public.platform_billing_cycle FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_client_provision_request_set_updated_at BEFORE UPDATE ON public.platform_client_provision_request FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_client_purchase_checkout_set_updated_at BEFORE UPDATE ON public.platform_client_purchase_checkout FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_document_binding_set_updated_at BEFORE UPDATE ON public.platform_document_binding FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_document_class_set_updated_at BEFORE UPDATE ON public.platform_document_class FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_document_record_set_updated_at BEFORE UPDATE ON public.platform_document_record FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_document_upload_intent_set_updated_at BEFORE UPDATE ON public.platform_document_upload_intent FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_exchange_contract_set_updated_at BEFORE UPDATE ON public.platform_exchange_contract FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_export_artifact_set_updated_at BEFORE UPDATE ON public.platform_export_artifact FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_export_job_set_updated_at BEFORE UPDATE ON public.platform_export_job FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_export_policy_set_updated_at BEFORE UPDATE ON public.platform_export_policy FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_extensible_attribute_schema_set_updated_at BEFORE UPDATE ON public.platform_extensible_attribute_schema FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_extensible_entity_registry_set_updated_at BEFORE UPDATE ON public.platform_extensible_entity_registry FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_extensible_join_profile_set_updated_at BEFORE UPDATE ON public.platform_extensible_join_profile FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_extensible_schema_cache_set_updated_at BEFORE UPDATE ON public.platform_extensible_schema_cache FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_gateway_operation_set_updated_at BEFORE UPDATE ON public.platform_gateway_operation FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_import_run_set_updated_at BEFORE UPDATE ON public.platform_import_run FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_import_session_set_updated_at BEFORE UPDATE ON public.platform_import_session FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_import_staging_row_set_updated_at BEFORE UPDATE ON public.platform_import_staging_row FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_import_validation_summary_set_updated_at BEFORE UPDATE ON public.platform_import_validation_summary FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_invoice_set_updated_at BEFORE UPDATE ON public.platform_invoice FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_membership_invitation_set_updated_at BEFORE UPDATE ON public.platform_membership_invitation FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_owner_bootstrap_token_set_updated_at BEFORE UPDATE ON public.platform_owner_bootstrap_token FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_plan_catalog_set_updated_at BEFORE UPDATE ON public.platform_plan_catalog FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_plan_metric_rate_set_updated_at BEFORE UPDATE ON public.platform_plan_metric_rate FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_read_model_catalog_set_updated_at BEFORE UPDATE ON public.platform_read_model_catalog FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_read_model_refresh_run_set_updated_at BEFORE UPDATE ON public.platform_read_model_refresh_run FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_read_model_refresh_state_set_updated_at BEFORE UPDATE ON public.platform_read_model_refresh_state FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_signin_challenge_set_updated_at BEFORE UPDATE ON public.platform_signin_challenge FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_signin_policy_set_updated_at BEFORE UPDATE ON public.platform_signin_policy FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_signup_request_set_updated_at BEFORE UPDATE ON public.platform_signup_request FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_storage_bucket_catalog_set_updated_at BEFORE UPDATE ON public.platform_storage_bucket_catalog FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_template_table_registry_set_updated_at BEFORE UPDATE ON public.platform_template_table_registry FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_template_version_set_updated_at BEFORE UPDATE ON public.platform_template_version FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_tenant_set_updated_at BEFORE UPDATE ON public.platform_tenant FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_tenant_access_state_set_updated_at BEFORE UPDATE ON public.platform_tenant_access_state FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_tenant_commercial_account_set_updated_at BEFORE UPDATE ON public.platform_tenant_commercial_account FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_tenant_provisioning_set_updated_at BEFORE UPDATE ON public.platform_tenant_provisioning FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_tenant_subscription_set_updated_at BEFORE UPDATE ON public.platform_tenant_subscription FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_platform_tenant_template_version_set_updated_at BEFORE UPDATE ON public.platform_tenant_template_version FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_agm_badge_award_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.agm_badge_award FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_agm_badge_catalog_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.agm_badge_catalog FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_agm_recognition_event_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.agm_recognition_event FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_agm_rule_set_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.agm_rule_set FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_agm_user_preference_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.agm_user_preference FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_agm_user_score_summary_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.agm_user_score_summary FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_attendance_configuration_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_attendance_configuration FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_agm_queue_refresh_on_ams_change AFTER INSERT OR DELETE OR UPDATE ON tenant_eoaplive133052.ams_attendance_record FOR EACH ROW EXECUTE FUNCTION public.platform_enqueue_agm_refresh_for_attendance_change();

CREATE TRIGGER trg_ams_attendance_record_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_attendance_record FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_tps_mark_summary_stale_on_ams_change AFTER INSERT OR DELETE OR UPDATE ON tenant_eoaplive133052.ams_attendance_record FOR EACH ROW EXECUTE FUNCTION public.platform_tps_mark_summary_stale_on_attendance_change();

CREATE TRIGGER trg_ams_bio_connector_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_connector FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_device_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_device FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_employee_mapping_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_employee_mapping FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_field_mapping_profile_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_field_mapping_profile FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_field_mapping_rule_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_field_mapping_rule FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_import_run_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_import_run FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_import_session_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_import_session FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_import_staging_row_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_import_staging_row FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_import_validation_summary_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_import_validation_summary FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_normalized_punch_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_normalized_punch FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_publish_log_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_publish_log FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_raw_punch_log_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_raw_punch_log FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_reconciliation_case_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_reconciliation_case FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_source_onboarding_state_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_source_onboarding_state FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_bio_source_profile_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_bio_source_profile FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_employee_schedule_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_employee_schedule FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_geofence_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_geofence FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_holiday_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_holiday FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_punch_event_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_punch_event FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_regularization_request_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_regularization_request FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_ams_shift_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.ams_shift FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_hierarchy_position_assign_path BEFORE INSERT OR UPDATE OF reporting_position_id ON tenant_eoaplive133052.hierarchy_position FOR EACH ROW EXECUTE FUNCTION public.platform_hierarchy_position_assign_path();

CREATE TRIGGER trg_hierarchy_position_refresh_descendants AFTER UPDATE OF reporting_position_id ON tenant_eoaplive133052.hierarchy_position FOR EACH ROW EXECUTE FUNCTION public.platform_hierarchy_position_refresh_descendants();

CREATE TRIGGER trg_hierarchy_position_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.hierarchy_position FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_hierarchy_position_group_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.hierarchy_position_group FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_hierarchy_position_occupancy_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.hierarchy_position_occupancy FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_lms_leave_policy_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.lms_leave_policy FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_lms_leave_request_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.lms_leave_request FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_lms_leave_type_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.lms_leave_type FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_lms_ledger_consumption_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.lms_ledger_consumption FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_lms_policy_assignment_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.lms_policy_assignment FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_lms_tenant_configuration_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.lms_tenant_configuration FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_rcm_candidate_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.rcm_candidate FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_rcm_conversion_case_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.rcm_conversion_case FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_rcm_job_application_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.rcm_job_application FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_rcm_requisition_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.rcm_requisition FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_tps_employee_period_summary_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.tps_employee_period_summary FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_tps_processing_batch_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.tps_processing_batch FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_component_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_component FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_component_calculation_result_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_component_calculation_result FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_component_rule_template_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_component_rule_template FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_employee_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_employee FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_employee_pay_structure_assignment_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_employee_pay_structure_assignment FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_employee_service_state_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_employee_service_state FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_pay_structure_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_pay_structure FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_pay_structure_component_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_pay_structure_component FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_pay_structure_version_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_pay_structure_version FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_payroll_area_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_payroll_area FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_payroll_batch_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_payroll_batch FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_payroll_input_entry_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_payroll_input_entry FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_payslip_item_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_payslip_item FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_payslip_run_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_payslip_run FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_preview_simulation_set_updated_at BEFORE UPDATE ON tenant_eoaplive133052.wcm_preview_simulation FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_hierarchy_position_assign_path BEFORE INSERT OR UPDATE OF reporting_position_id ON tenant_sim_f03_tenant_b_572c752afe98461a.hierarchy_position FOR EACH ROW EXECUTE FUNCTION public.platform_hierarchy_position_assign_path();

CREATE TRIGGER trg_hierarchy_position_refresh_descendants AFTER UPDATE OF reporting_position_id ON tenant_sim_f03_tenant_b_572c752afe98461a.hierarchy_position FOR EACH ROW EXECUTE FUNCTION public.platform_hierarchy_position_refresh_descendants();

CREATE TRIGGER trg_hierarchy_position_set_updated_at BEFORE UPDATE ON tenant_sim_f03_tenant_b_572c752afe98461a.hierarchy_position FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_hierarchy_position_group_set_updated_at BEFORE UPDATE ON tenant_sim_f03_tenant_b_572c752afe98461a.hierarchy_position_group FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_hierarchy_position_occupancy_set_updated_at BEFORE UPDATE ON tenant_sim_f03_tenant_b_572c752afe98461a.hierarchy_position_occupancy FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_rcm_candidate_set_updated_at BEFORE UPDATE ON tenant_sim_f03_tenant_b_572c752afe98461a.rcm_candidate FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_rcm_conversion_case_set_updated_at BEFORE UPDATE ON tenant_sim_f03_tenant_b_572c752afe98461a.rcm_conversion_case FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_rcm_job_application_set_updated_at BEFORE UPDATE ON tenant_sim_f03_tenant_b_572c752afe98461a.rcm_job_application FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_rcm_requisition_set_updated_at BEFORE UPDATE ON tenant_sim_f03_tenant_b_572c752afe98461a.rcm_requisition FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_employee_set_updated_at BEFORE UPDATE ON tenant_sim_f03_tenant_b_572c752afe98461a.wcm_employee FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();

CREATE TRIGGER trg_wcm_employee_service_state_set_updated_at BEFORE UPDATE ON tenant_sim_f03_tenant_b_572c752afe98461a.wcm_employee_service_state FOR EACH ROW EXECUTE FUNCTION public.platform_set_updated_at();


