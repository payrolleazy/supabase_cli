create or replace function public.platform_i05_run_document_maintenance(p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_missing_bucket record;
  v_bucket_result jsonb;
  v_expired_intent record;
  v_missing_bucket_count integer := 0;
  v_expired_intent_count integer := 0;
  v_bucket_codes jsonb := '[]'::jsonb;
  v_expired_upload_intent_ids jsonb := '[]'::jsonb;
begin
  if not public.platform_is_internal_caller() then
    return public.platform_json_response(
      false,
      'INTERNAL_CALLER_REQUIRED',
      'I05 document maintenance is restricted to internal callers.',
      '{}'::jsonb
    );
  end if;

  for v_missing_bucket in
    select distinct
      sbc.bucket_code,
      sbc.bucket_name,
      sbc.bucket_purpose,
      sbc.bucket_visibility,
      sbc.protection_mode,
      sbc.file_size_limit_bytes,
      sbc.allowed_mime_types,
      sbc.retention_days,
      sbc.bucket_status,
      sbc.metadata
    from public.platform_storage_bucket_catalog sbc
    join public.platform_document_class dc
      on dc.default_bucket_code = sbc.bucket_code
     and dc.class_status = 'active'
    left join storage.buckets b
      on b.id = sbc.bucket_name
    where sbc.bucket_status = 'active'
      and b.id is null
  loop
    v_bucket_result := public.platform_register_storage_bucket(
      jsonb_build_object(
        'bucket_code', v_missing_bucket.bucket_code,
        'bucket_name', v_missing_bucket.bucket_name,
        'bucket_purpose', v_missing_bucket.bucket_purpose,
        'bucket_visibility', v_missing_bucket.bucket_visibility,
        'protection_mode', v_missing_bucket.protection_mode,
        'file_size_limit_bytes', v_missing_bucket.file_size_limit_bytes,
        'allowed_mime_types', to_jsonb(v_missing_bucket.allowed_mime_types),
        'retention_days', v_missing_bucket.retention_days,
        'bucket_status', v_missing_bucket.bucket_status,
        'metadata', coalesce(v_missing_bucket.metadata, '{}'::jsonb),
        'ensure_storage_bucket', true
      )
    );

    if coalesce((v_bucket_result->>'success')::boolean, false) is not true then
      return v_bucket_result;
    end if;

    v_missing_bucket_count := v_missing_bucket_count + 1;
    v_bucket_codes := v_bucket_codes || jsonb_build_array(v_missing_bucket.bucket_code);
  end loop;

  for v_expired_intent in
    update public.platform_document_upload_intent
       set upload_status = 'expired',
           updated_at = timezone('utc', now())
     where upload_status = 'pending'
       and intent_expires_at < timezone('utc', now())
     returning upload_intent_id, tenant_id, requested_by_actor_user_id
  loop
    v_expired_intent_count := v_expired_intent_count + 1;
    v_expired_upload_intent_ids := v_expired_upload_intent_ids || jsonb_build_array(v_expired_intent.upload_intent_id);

    perform public.platform_document_write_event(jsonb_build_object(
      'event_type', 'document_upload_intent_expired_by_maintenance',
      'tenant_id', v_expired_intent.tenant_id,
      'upload_intent_id', v_expired_intent.upload_intent_id,
      'actor_user_id', v_expired_intent.requested_by_actor_user_id,
      'message', 'Expired pending upload intent was closed by I05 maintenance.',
      'details', jsonb_build_object(
        'maintenance_code', 'i05_document_maintenance'
      )
    ));
  end loop;

  return public.platform_json_response(
    true,
    'OK',
    'I05 document maintenance completed.',
    jsonb_build_object(
      'missing_bucket_count', v_missing_bucket_count,
      'bucket_codes', v_bucket_codes,
      'expired_pending_intent_count', v_expired_intent_count,
      'expired_upload_intent_ids', v_expired_upload_intent_ids
    )
  );
exception
  when others then
    return public.platform_json_response(
      false,
      'UNEXPECTED_ERROR',
      'Unexpected error in platform_i05_run_document_maintenance.',
      jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
    );
end;
$function$;

create or replace function public.platform_i05_run_document_maintenance_scheduler()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  return public.platform_i05_run_document_maintenance(
    jsonb_build_object(
      'trigger', 'pg_cron'
    )
  );
exception
  when others then
    return public.platform_json_response(
      false,
      'UNEXPECTED_ERROR',
      'Unexpected error in platform_i05_run_document_maintenance_scheduler.',
      jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
    );
end;
$function$;

do $$
declare
  v_job record;
begin
  for v_job in
    select jobid
    from cron.job
    where jobname = 'i05-document-maintenance'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;

  perform cron.schedule(
    'i05-document-maintenance',
    '*/30 * * * *',
    'select public.platform_i05_run_document_maintenance_scheduler();'
  );
end;
$$;

select public.platform_i05_run_document_maintenance_scheduler();
