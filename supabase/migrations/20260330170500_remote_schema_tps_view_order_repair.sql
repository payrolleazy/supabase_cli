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
