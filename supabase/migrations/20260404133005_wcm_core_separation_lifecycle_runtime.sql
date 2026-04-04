set check_function_bodies = false;

CREATE TABLE public.platform_wcm_lifecycle_rollback_audit (
    audit_id bigint NOT NULL,
    tenant_id uuid NOT NULL,
    request_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    position_id bigint,
    decision_code text NOT NULL,
    action_code text NOT NULL,
    manual_review_required boolean DEFAULT false NOT NULL,
    actor_user_id uuid,
    reason text,
    audit_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: platform_rm_wcm_lifecycle_rollback_audit; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.platform_rm_wcm_lifecycle_rollback_audit WITH (security_invoker='true') AS
 SELECT audit_id,
    tenant_id,
    request_id,
    employee_id,
    position_id,
    decision_code,
    action_code,
    manual_review_required,
    actor_user_id,
    reason,
    audit_payload,
    created_at
   FROM public.platform_wcm_lifecycle_rollback_audit
  WHERE (tenant_id = public.platform_current_tenant_id());


--
-- Name: platform_wcm_resignation_request; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_wcm_resignation_request (
    request_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    actor_user_id uuid,
    position_id bigint,
    request_status text DEFAULT 'pending_approval'::text NOT NULL,
    resignation_date date NOT NULL,
    tentative_leaving_date date NOT NULL,
    approved_last_working_day date,
    waive_notice_shortfall boolean DEFAULT false NOT NULL,
    separation_reason text,
    comments text,
    lifecycle_runtime_status text DEFAULT 'idle'::text NOT NULL,
    last_event_id uuid,
    last_decision_code text,
    last_action_code text,
    last_runtime_message text,
    request_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    approved_by_actor_user_id uuid,
    approved_at timestamp with time zone,
    withdrawn_by_actor_user_id uuid,
    withdrawn_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT platform_wcm_resignation_request_lifecycle_runtime_status_check CHECK ((lifecycle_runtime_status = ANY (ARRAY['idle'::text, 'queued'::text, 'processing'::text, 'completed'::text, 'failed'::text]))),
    CONSTRAINT platform_wcm_resignation_request_request_status_check CHECK ((request_status = ANY (ARRAY['pending_approval'::text, 'approved_pending_clearance'::text, 'withdrawn'::text, 'rejected'::text, 'completed'::text])))
);


--
-- Name: platform_rm_wcm_resignation_request_catalog; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.platform_rm_wcm_resignation_request_catalog WITH (security_invoker='true') AS
 SELECT request_id,
    tenant_id,
    employee_id,
    position_id,
    request_status,
    resignation_date,
    tentative_leaving_date,
    approved_last_working_day,
    waive_notice_shortfall,
    separation_reason,
    comments,
    lifecycle_runtime_status,
    last_event_id,
    last_decision_code,
    last_action_code,
    last_runtime_message,
    approved_by_actor_user_id,
    approved_at,
    withdrawn_by_actor_user_id,
    withdrawn_at,
    created_at,
    updated_at,
    request_metadata
   FROM public.platform_wcm_resignation_request
  WHERE (tenant_id = public.platform_current_tenant_id());


--
-- Name: platform_wcm_lifecycle_event_queue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_wcm_lifecycle_event_queue (
    event_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    request_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    event_type text NOT NULL,
    event_status text DEFAULT 'queued'::text NOT NULL,
    attempt_count integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 3 NOT NULL,
    next_attempt_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    actor_user_id uuid,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    result_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    error_message text,
    processed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT platform_wcm_lifecycle_event_queue_attempt_count_check CHECK ((attempt_count >= 0)),
    CONSTRAINT platform_wcm_lifecycle_event_queue_event_status_check CHECK ((event_status = ANY (ARRAY['queued'::text, 'processing'::text, 'completed'::text, 'failed'::text, 'retrying'::text]))),
    CONSTRAINT platform_wcm_lifecycle_event_queue_max_attempts_check CHECK ((max_attempts > 0))
);


--
-- Name: platform_wcm_lifecycle_rollback_audit_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.platform_wcm_lifecycle_rollback_audit_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: platform_wcm_lifecycle_rollback_audit_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.platform_wcm_lifecycle_rollback_audit_audit_id_seq OWNED BY public.platform_wcm_lifecycle_rollback_audit.audit_id;


--
-- Name: platform_wcm_lifecycle_rollback_audit audit_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_wcm_lifecycle_rollback_audit ALTER COLUMN audit_id SET DEFAULT nextval('public.platform_wcm_lifecycle_rollback_audit_audit_id_seq'::regclass);


--
-- Name: platform_wcm_lifecycle_event_queue platform_wcm_lifecycle_event_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_wcm_lifecycle_event_queue
    ADD CONSTRAINT platform_wcm_lifecycle_event_queue_pkey PRIMARY KEY (event_id);


--
-- Name: platform_wcm_lifecycle_rollback_audit platform_wcm_lifecycle_rollback_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_wcm_lifecycle_rollback_audit
    ADD CONSTRAINT platform_wcm_lifecycle_rollback_audit_pkey PRIMARY KEY (audit_id);


--
-- Name: platform_wcm_resignation_request platform_wcm_resignation_request_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_wcm_resignation_request
    ADD CONSTRAINT platform_wcm_resignation_request_pkey PRIMARY KEY (request_id);


--
-- Name: ix_platform_wcm_lifecycle_event_queue_request; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_wcm_lifecycle_event_queue_request ON public.platform_wcm_lifecycle_event_queue USING btree (request_id, created_at DESC);


--
-- Name: ix_platform_wcm_lifecycle_event_queue_status_next; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_wcm_lifecycle_event_queue_status_next ON public.platform_wcm_lifecycle_event_queue USING btree (event_status, next_attempt_at);


--
-- Name: ix_platform_wcm_lifecycle_rollback_audit_request; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_wcm_lifecycle_rollback_audit_request ON public.platform_wcm_lifecycle_rollback_audit USING btree (request_id);


--
-- Name: ix_platform_wcm_lifecycle_rollback_audit_tenant_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_wcm_lifecycle_rollback_audit_tenant_created ON public.platform_wcm_lifecycle_rollback_audit USING btree (tenant_id, created_at DESC);


--
-- Name: ix_platform_wcm_resignation_request_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_wcm_resignation_request_employee ON public.platform_wcm_resignation_request USING btree (employee_id);


--
-- Name: ix_platform_wcm_resignation_request_tenant_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_platform_wcm_resignation_request_tenant_created ON public.platform_wcm_resignation_request USING btree (tenant_id, created_at DESC);


--
-- Name: ux_platform_wcm_resignation_request_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_platform_wcm_resignation_request_active ON public.platform_wcm_resignation_request USING btree (tenant_id, employee_id) WHERE (request_status = ANY (ARRAY['pending_approval'::text, 'approved_pending_clearance'::text]));


--
-- Name: platform_wcm_lifecycle_event_queue platform_wcm_lifecycle_event_queue_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_wcm_lifecycle_event_queue
    ADD CONSTRAINT platform_wcm_lifecycle_event_queue_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.platform_wcm_resignation_request(request_id) ON DELETE CASCADE;


--
-- Name: platform_wcm_lifecycle_rollback_audit platform_wcm_lifecycle_rollback_audit_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_wcm_lifecycle_rollback_audit
    ADD CONSTRAINT platform_wcm_lifecycle_rollback_audit_request_id_fkey FOREIGN KEY (request_id) REFERENCES public.platform_wcm_resignation_request(request_id) ON DELETE CASCADE;


--
-- Name: platform_wcm_lifecycle_event_queue; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.platform_wcm_lifecycle_event_queue ENABLE ROW LEVEL SECURITY;

--
-- Name: platform_wcm_lifecycle_rollback_audit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.platform_wcm_lifecycle_rollback_audit ENABLE ROW LEVEL SECURITY;

--
-- Name: platform_wcm_lifecycle_rollback_audit platform_wcm_lifecycle_rollback_audit_service_role_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY platform_wcm_lifecycle_rollback_audit_service_role_select ON public.platform_wcm_lifecycle_rollback_audit FOR SELECT TO service_role USING (true);


--
-- Name: platform_wcm_resignation_request; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.platform_wcm_resignation_request ENABLE ROW LEVEL SECURITY;

--
-- Name: platform_wcm_resignation_request platform_wcm_resignation_request_service_role_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY platform_wcm_resignation_request_service_role_select ON public.platform_wcm_resignation_request FOR SELECT TO service_role USING (true);


--

CREATE OR REPLACE FUNCTION public.platform_apply_wcm_resignation_rollback(p_request_id uuid, p_tenant_id uuid, p_actor_user_id uuid DEFAULT NULL::uuid, p_reason text DEFAULT NULL::text, p_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_request public.platform_wcm_resignation_request%rowtype;
  v_context_result jsonb;
  v_details jsonb;
  v_schema_name text;
  v_decision jsonb := coalesce(p_decision, public.platform_get_wcm_resignation_rollback_decision(p_request_id, p_tenant_id));
  v_position_id bigint;
  v_decision_code text;
  v_action_code text;
  v_manual_review_required boolean;
  v_target_requisition_ids uuid[] := array[]::uuid[];
  v_requisition_update_count integer := 0;
  v_application_update_count integer := 0;
  v_conversion_update_count integer := 0;
  v_workflow_update_count integer := 0;
  v_audit_id bigint;
  v_audit_payload jsonb;
  v_has_rcm_requisition boolean := false;
  v_has_rcm_job_application boolean := false;
  v_has_rcm_conversion_case boolean := false;
  v_has_eoap_workflow boolean := false;
begin
  select *
  into v_request
  from public.platform_wcm_resignation_request
  where request_id = p_request_id
    and tenant_id = p_tenant_id;

  if not found then
    return public.platform_json_response(false, 'REQUEST_NOT_FOUND', 'Resignation request not found.', jsonb_build_object('request_id', p_request_id));
  end if;

  if coalesce((v_decision->>'success')::boolean, false) is not true then
    return v_decision;
  end if;

  v_context_result := public.platform_wcm_internal_resolve_context(p_tenant_id, 'platform_apply_wcm_resignation_rollback');
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  v_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := v_details->>'tenant_schema';
  v_position_id := coalesce(nullif(v_decision->>'position_id', '')::bigint, v_request.position_id);
  v_decision_code := coalesce(v_decision->>'decision_code', 'unknown');
  v_action_code := coalesce(v_decision->>'action_code', 'no_downstream_artifact');
  v_manual_review_required := coalesce((v_decision->>'manual_review_required')::boolean, false);

  select coalesce(array_agg(value::uuid), array[]::uuid[])
  into v_target_requisition_ids
  from jsonb_array_elements_text(coalesce(v_decision->'target_requisition_ids', '[]'::jsonb));

  v_audit_payload := jsonb_strip_nulls(coalesce(v_decision, '{}'::jsonb) || jsonb_build_object(
    'executed_at', timezone('utc', now()),
    'actor_user_id', p_actor_user_id,
    'reason', p_reason
  ));

  v_has_rcm_requisition := public.platform_table_exists(v_schema_name, 'rcm_requisition');
  v_has_rcm_job_application := public.platform_table_exists(v_schema_name, 'rcm_job_application');
  v_has_rcm_conversion_case := public.platform_table_exists(v_schema_name, 'rcm_conversion_case');
  v_has_eoap_workflow := public.platform_table_exists(v_schema_name, 'eoap_workflow');

  if v_action_code = 'cancel_idle_requisition'
     and v_has_rcm_requisition
     and coalesce(array_length(v_target_requisition_ids, 1), 0) > 0 then
    execute format(
      'update %I.rcm_requisition
       set requisition_status = ''cancelled'',
           updated_at = timezone(''utc'', now())
       where requisition_id = any($1)
         and lower(coalesce(requisition_status, '''')) not in (''cancelled'', ''closed'', ''filled'')',
      v_schema_name
    )
    using v_target_requisition_ids;
    get diagnostics v_requisition_update_count = row_count;
  elsif v_action_code = 'pause_requisition_activity_hold' then
    if v_has_rcm_requisition and coalesce(array_length(v_target_requisition_ids, 1), 0) > 0 then
      execute format(
        'update %I.rcm_requisition
         set requisition_status = ''on_hold'',
             updated_at = timezone(''utc'', now())
         where requisition_id = any($1)
           and lower(coalesce(requisition_status, '''')) not in (''cancelled'', ''closed'', ''filled'')',
        v_schema_name
      )
      using v_target_requisition_ids;
      get diagnostics v_requisition_update_count = row_count;
    end if;

    if v_has_rcm_job_application and coalesce(array_length(v_target_requisition_ids, 1), 0) > 0 then
      execute format(
        'update %I.rcm_job_application
         set application_metadata = coalesce(application_metadata, ''{}''::jsonb) || jsonb_build_object(''wcm_lifecycle_rollback'', $2),
             updated_at = timezone(''utc'', now())
         where requisition_id = any($1)',
        v_schema_name
      )
      using v_target_requisition_ids, v_audit_payload;
      get diagnostics v_application_update_count = row_count;
    end if;

    if v_has_rcm_conversion_case and coalesce(array_length(v_target_requisition_ids, 1), 0) > 0 then
      execute format(
        'update %I.rcm_conversion_case
         set conversion_status = case
               when lower(coalesce(conversion_status, '''')) in (''converted'', ''failed'', ''cancelled'') then conversion_status
               else ''failed''
             end,
             conversion_notes = coalesce(conversion_notes, ''{}''::jsonb) || jsonb_build_object(''wcm_lifecycle_rollback'', $2),
             updated_at = timezone(''utc'', now())
         where requisition_id = any($1)',
        v_schema_name
      )
      using v_target_requisition_ids, v_audit_payload;
      get diagnostics v_conversion_update_count = row_count;
    end if;
  elsif v_action_code = 'manual_review_required' then
    if v_has_rcm_requisition and coalesce(array_length(v_target_requisition_ids, 1), 0) > 0 then
      execute format(
        'update %I.rcm_requisition
         set requisition_status = ''on_hold'',
             updated_at = timezone(''utc'', now())
         where requisition_id = any($1)
           and lower(coalesce(requisition_status, '''')) not in (''cancelled'', ''closed'', ''filled'')',
        v_schema_name
      )
      using v_target_requisition_ids;
      get diagnostics v_requisition_update_count = row_count;
    end if;

    if v_has_rcm_job_application and coalesce(array_length(v_target_requisition_ids, 1), 0) > 0 then
      execute format(
        'update %I.rcm_job_application
         set application_metadata = coalesce(application_metadata, ''{}''::jsonb) || jsonb_build_object(''wcm_lifecycle_rollback'', $2),
             updated_at = timezone(''utc'', now())
         where requisition_id = any($1)',
        v_schema_name
      )
      using v_target_requisition_ids, v_audit_payload;
      get diagnostics v_application_update_count = row_count;
    end if;

    if v_has_rcm_conversion_case and coalesce(array_length(v_target_requisition_ids, 1), 0) > 0 then
      execute format(
        'update %I.rcm_conversion_case
         set conversion_notes = coalesce(conversion_notes, ''{}''::jsonb) || jsonb_build_object(''wcm_lifecycle_rollback'', $2),
             updated_at = timezone(''utc'', now())
         where requisition_id = any($1)',
        v_schema_name
      )
      using v_target_requisition_ids, v_audit_payload;
      get diagnostics v_conversion_update_count = row_count;
    end if;

    if v_has_eoap_workflow and v_position_id is not null then
      execute format(
        'update %I.eoap_workflow
         set workflow_metadata = coalesce(workflow_metadata, ''{}''::jsonb) || jsonb_build_object(''wcm_lifecycle_rollback'', $2),
             updated_at = timezone(''utc'', now())
         where target_position_id = $1
           and lower(coalesce(workflow_status, '''')) not in (''completed'', ''cancelled'', ''failed'')',
        v_schema_name
      )
      using v_position_id, v_audit_payload;
      get diagnostics v_workflow_update_count = row_count;
    end if;
  end if;

  v_audit_id := public.platform_write_wcm_lifecycle_rollback_audit(
    p_tenant_id,
    p_request_id,
    v_request.employee_id,
    v_position_id,
    v_decision_code,
    v_action_code,
    v_manual_review_required,
    p_actor_user_id,
    p_reason,
    v_audit_payload || jsonb_build_object(
      'requisition_update_count', v_requisition_update_count,
      'application_update_count', v_application_update_count,
      'conversion_update_count', v_conversion_update_count,
      'workflow_update_count', v_workflow_update_count,
      'downstream_surfaces', jsonb_build_object(
        'rcm_requisition', v_has_rcm_requisition,
        'rcm_job_application', v_has_rcm_job_application,
        'rcm_conversion_case', v_has_rcm_conversion_case,
        'eoap_workflow', v_has_eoap_workflow
      )
    )
  );

  return public.platform_json_response(true, 'OK', 'WCM lifecycle rollback applied.', jsonb_build_object(
    'audit_id', v_audit_id,
    'decision_code', v_decision_code,
    'action_code', v_action_code,
    'manual_review_required', v_manual_review_required,
    'position_id', v_position_id,
    'requisition_update_count', v_requisition_update_count,
    'application_update_count', v_application_update_count,
    'conversion_update_count', v_conversion_update_count,
    'workflow_update_count', v_workflow_update_count
  ));
exception
  when others then
    begin
      v_audit_id := public.platform_write_wcm_lifecycle_rollback_audit(
        p_tenant_id,
        p_request_id,
        coalesce(v_request.employee_id, null),
        v_position_id,
        coalesce(v_decision_code, 'rollback_execution_error'),
        'rollback_execution_error',
        coalesce(v_manual_review_required, false),
        p_actor_user_id,
        p_reason,
        coalesce(v_audit_payload, '{}'::jsonb) || jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm)
      );
    exception
      when others then
        null;
    end;

    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_apply_wcm_resignation_rollback.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm, 'audit_id', v_audit_id));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_enqueue_wcm_lifecycle_event(p_tenant_id uuid, p_request_id uuid, p_employee_id uuid, p_event_type text, p_payload jsonb DEFAULT '{}'::jsonb, p_actor_user_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_event_id uuid;
begin
  if p_tenant_id is null or p_request_id is null or p_employee_id is null then
    raise exception 'tenant_id, request_id, and employee_id are required for WCM lifecycle enqueue';
  end if;

  if nullif(btrim(coalesce(p_event_type, '')), '') is null then
    raise exception 'event_type is required for WCM lifecycle enqueue';
  end if;

  insert into public.platform_wcm_lifecycle_event_queue (
    tenant_id,
    request_id,
    employee_id,
    event_type,
    actor_user_id,
    payload
  ) values (
    p_tenant_id,
    p_request_id,
    p_employee_id,
    p_event_type,
    p_actor_user_id,
    coalesce(p_payload, '{}'::jsonb)
  )
  returning event_id into v_event_id;

  update public.platform_wcm_resignation_request
  set last_event_id = v_event_id,
      lifecycle_runtime_status = 'queued',
      updated_at = timezone('utc', now())
  where request_id = p_request_id;

  return v_event_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_get_wcm_resignation_rollback_decision(p_request_id uuid, p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_request public.platform_wcm_resignation_request%rowtype;
  v_context_result jsonb;
  v_details jsonb;
  v_schema_name text;
  v_position_id bigint;
  v_requisition_count integer := 0;
  v_target_requisition_ids jsonb := '[]'::jsonb;
  v_candidate_activity_count integer := 0;
  v_active_conversion_count integer := 0;
  v_converted_conversion_count integer := 0;
  v_active_onboarding_count integer := 0;
  v_decision_code text;
  v_action_code text;
  v_manual_review_required boolean := false;
  v_has_rcm_requisition boolean := false;
  v_has_rcm_job_application boolean := false;
  v_has_rcm_conversion_case boolean := false;
  v_has_eoap_workflow boolean := false;
begin
  select *
  into v_request
  from public.platform_wcm_resignation_request
  where request_id = p_request_id
    and tenant_id = p_tenant_id;

  if not found then
    return jsonb_build_object(
      'success', false,
      'request_id', p_request_id,
      'tenant_id', p_tenant_id,
      'decision_code', 'request_not_found',
      'action_code', 'no_downstream_artifact'
    );
  end if;

  v_context_result := public.platform_wcm_internal_resolve_context(p_tenant_id, 'platform_get_wcm_resignation_rollback_decision');
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  v_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := v_details->>'tenant_schema';
  v_position_id := v_request.position_id;

  if v_position_id is null then
    execute format('select position_id from %I.wcm_employee_service_state where employee_id = $1', v_schema_name)
      into v_position_id
      using v_request.employee_id;
  end if;

  v_has_rcm_requisition := public.platform_table_exists(v_schema_name, 'rcm_requisition');
  v_has_rcm_job_application := public.platform_table_exists(v_schema_name, 'rcm_job_application');
  v_has_rcm_conversion_case := public.platform_table_exists(v_schema_name, 'rcm_conversion_case');
  v_has_eoap_workflow := public.platform_table_exists(v_schema_name, 'eoap_workflow');

  if v_has_rcm_requisition and v_position_id is not null then
    execute format(
      'select count(*)::integer, coalesce(jsonb_agg(requisition_id), ''[]''::jsonb)
       from %I.rcm_requisition
       where position_id = $1
         and lower(coalesce(requisition_status, '''')) not in (''closed'', ''cancelled'', ''filled'')',
      v_schema_name
    )
    into v_requisition_count, v_target_requisition_ids
    using v_position_id;
  end if;

  if v_has_rcm_job_application and v_requisition_count > 0 then
    execute format(
      'select count(*)::integer
       from %I.rcm_job_application
       where requisition_id in (select value::uuid from jsonb_array_elements_text($1))
         and lower(coalesce(application_status, '''')) not in (''rejected'', ''withdrawn'', ''converted'', ''cancelled'')',
      v_schema_name
    )
    into v_candidate_activity_count
    using v_target_requisition_ids;
  end if;

  if v_has_rcm_conversion_case and v_requisition_count > 0 then
    execute format(
      'select
         count(*) filter (where lower(coalesce(conversion_status, '''')) not in (''converted'', ''failed'', ''cancelled''))::integer,
         count(*) filter (where lower(coalesce(conversion_status, '''')) = ''converted'')::integer
       from %I.rcm_conversion_case
       where requisition_id in (select value::uuid from jsonb_array_elements_text($1))',
      v_schema_name
    )
    into v_active_conversion_count, v_converted_conversion_count
    using v_target_requisition_ids;
  end if;

  if v_has_eoap_workflow and v_position_id is not null then
    execute format(
      'select count(*)::integer
       from %I.eoap_workflow
       where target_position_id = $1
         and lower(coalesce(workflow_status, '''')) not in (''completed'', ''cancelled'', ''failed'')',
      v_schema_name
    )
    into v_active_onboarding_count
    using v_position_id;
  end if;

  if v_position_id is null then
    v_decision_code := 'no_seat_anchor';
    v_action_code := 'no_downstream_artifact';
  elsif v_requisition_count = 0 and v_active_onboarding_count = 0 then
    v_decision_code := 'signal_only_reversal';
    v_action_code := 'no_downstream_artifact';
  elsif v_converted_conversion_count > 0 or v_active_onboarding_count > 0 then
    v_decision_code := 'manual_review_required';
    v_action_code := 'manual_review_required';
    v_manual_review_required := true;
  elsif v_candidate_activity_count > 0 or v_active_conversion_count > 0 then
    v_decision_code := 'downstream_activity_hold';
    v_action_code := 'pause_requisition_activity_hold';
  else
    v_decision_code := 'idle_requisition_cancel';
    v_action_code := 'cancel_idle_requisition';
  end if;

  return jsonb_build_object(
    'success', true,
    'request_id', p_request_id,
    'tenant_id', p_tenant_id,
    'employee_id', v_request.employee_id,
    'request_status', v_request.request_status,
    'position_id', v_position_id,
    'decision_code', v_decision_code,
    'action_code', v_action_code,
    'manual_review_required', v_manual_review_required,
    'target_requisition_count', v_requisition_count,
    'target_requisition_ids', v_target_requisition_ids,
    'candidate_activity_count', v_candidate_activity_count,
    'active_conversion_count', v_active_conversion_count,
    'converted_conversion_count', v_converted_conversion_count,
    'active_onboarding_count', v_active_onboarding_count,
    'downstream_surfaces', jsonb_build_object(
      'rcm_requisition', v_has_rcm_requisition,
      'rcm_job_application', v_has_rcm_job_application,
      'rcm_conversion_case', v_has_rcm_conversion_case,
      'eoap_workflow', v_has_eoap_workflow
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_preview_wcm_resignation_rollback(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_context_result jsonb;
  v_tenant_id uuid;
  v_request_id uuid := public.platform_try_uuid(p_params->>'request_id');
begin
  v_context_result := public.platform_wcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  v_tenant_id := public.platform_try_uuid(v_context_result->'details'->>'tenant_id');

  if v_request_id is null then
    return public.platform_json_response(false, 'REQUEST_ID_REQUIRED', 'request_id is required.', '{}'::jsonb);
  end if;

  return public.platform_get_wcm_resignation_rollback_decision(v_request_id, v_tenant_id);
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_preview_wcm_resignation_rollback.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_process_wcm_pending_events(p_batch_size integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_event record;
  v_result jsonb;
  v_decision jsonb;
  v_processed_count integer := 0;
  v_failed_count integer := 0;
  v_error_message text;
  v_attempt_count integer;
begin
  for v_event in
    select *
    from public.platform_wcm_lifecycle_event_queue
    where event_status in ('queued', 'retrying')
      and next_attempt_at <= timezone('utc', now())
    order by created_at asc
    limit p_batch_size
    for update skip locked
  loop
    v_attempt_count := v_event.attempt_count + 1;

    update public.platform_wcm_lifecycle_event_queue
    set event_status = 'processing',
        attempt_count = v_attempt_count,
        updated_at = timezone('utc', now())
    where event_id = v_event.event_id;

    update public.platform_wcm_resignation_request
    set lifecycle_runtime_status = 'processing',
        updated_at = timezone('utc', now())
    where request_id = v_event.request_id;

    begin
      if v_event.event_type = 'resignation_approval_followup' then
        v_result := public.platform_sync_wcm_resignation_authority(v_event.tenant_id, v_event.employee_id, v_event.actor_user_id);
        if coalesce((v_result->>'success')::boolean, false) is not true then
          raise exception '%', coalesce(v_result->>'message', 'WCM approval follow-up failed');
        end if;
      elsif v_event.event_type = 'resignation_withdrawal_followup' then
        v_decision := public.platform_get_wcm_resignation_rollback_decision(v_event.request_id, v_event.tenant_id);
        if coalesce((v_decision->>'success')::boolean, false) is not true then
          raise exception '%', coalesce(v_decision->>'message', 'WCM rollback decision failed');
        end if;

        v_result := public.platform_apply_wcm_resignation_rollback(
          v_event.request_id,
          v_event.tenant_id,
          v_event.actor_user_id,
          nullif(btrim(coalesce(v_event.payload->>'reason', '')), ''),
          v_decision
        );
        if coalesce((v_result->>'success')::boolean, false) is not true then
          raise exception '%', coalesce(v_result->>'message', 'WCM rollback application failed');
        end if;
      else
        raise exception 'Unsupported WCM lifecycle event type: %', v_event.event_type;
      end if;

      update public.platform_wcm_lifecycle_event_queue
      set event_status = 'completed',
          result_payload = coalesce(v_result, '{}'::jsonb),
          error_message = null,
          processed_at = timezone('utc', now()),
          updated_at = timezone('utc', now())
      where event_id = v_event.event_id;

      update public.platform_wcm_resignation_request
      set lifecycle_runtime_status = 'completed',
          last_runtime_message = coalesce(v_result->>'message', 'WCM lifecycle follow-up completed.'),
          last_decision_code = coalesce(v_result->'details'->>'decision_code', v_decision->>'decision_code', last_decision_code),
          last_action_code = coalesce(v_result->'details'->>'action_code', v_decision->>'action_code', last_action_code),
          updated_at = timezone('utc', now())
      where request_id = v_event.request_id;

      v_processed_count := v_processed_count + 1;
    exception
      when others then
        v_error_message := sqlerrm;

        if v_attempt_count >= coalesce(v_event.max_attempts, 3) then
          update public.platform_wcm_lifecycle_event_queue
          set event_status = 'failed',
              error_message = v_error_message,
              processed_at = timezone('utc', now()),
              updated_at = timezone('utc', now())
          where event_id = v_event.event_id;

          update public.platform_wcm_resignation_request
          set lifecycle_runtime_status = 'failed',
              last_runtime_message = v_error_message,
              updated_at = timezone('utc', now())
          where request_id = v_event.request_id;
        else
          update public.platform_wcm_lifecycle_event_queue
          set event_status = 'retrying',
              error_message = v_error_message,
              next_attempt_at = timezone('utc', now()) + interval '2 minutes',
              updated_at = timezone('utc', now())
          where event_id = v_event.event_id;

          update public.platform_wcm_resignation_request
          set lifecycle_runtime_status = 'queued',
              last_runtime_message = v_error_message,
              updated_at = timezone('utc', now())
          where request_id = v_event.request_id;
        end if;

        v_failed_count := v_failed_count + 1;
    end;
  end loop;

  return jsonb_build_object(
    'success', true,
    'processed', v_processed_count,
    'failed', v_failed_count,
    'timestamp', timezone('utc', now())
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_process_wcm_resignation_approval(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_context_result jsonb;
  v_context_details jsonb;
  v_schema_name text;
  v_tenant_id uuid;
  v_request_id uuid := public.platform_try_uuid(p_params->>'request_id');
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_approved_last_working_day date := public.platform_wcm_try_date(p_params->>'approved_last_working_day');
  v_waive_notice_shortfall boolean := coalesce((p_params->>'waive_notice_shortfall')::boolean, false);
  v_remarks text := nullif(btrim(coalesce(p_params->>'remarks', '')), '');
  v_request public.platform_wcm_resignation_request%rowtype;
  v_joining_date date;
  v_service_state text;
  v_employment_status text;
  v_confirmation_date date;
  v_relief_date date;
  v_position_id bigint;
  v_last_billable boolean;
  v_state_notes jsonb;
  v_service_state_result jsonb;
  v_event_result jsonb;
  v_event_id uuid;
begin
  v_context_result := public.platform_wcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');
  v_tenant_id := public.platform_try_uuid(v_context_details->>'tenant_id');

  if v_request_id is null then
    return public.platform_json_response(false, 'REQUEST_ID_REQUIRED', 'request_id is required.', '{}'::jsonb);
  end if;

  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_CONTEXT_REQUIRED', 'actor_user_id or current actor context is required.', '{}'::jsonb);
  end if;

  if v_approved_last_working_day is null then
    return public.platform_json_response(false, 'APPROVED_LAST_WORKING_DAY_REQUIRED', 'approved_last_working_day is required.', '{}'::jsonb);
  end if;

  select *
  into v_request
  from public.platform_wcm_resignation_request
  where request_id = v_request_id
    and tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'REQUEST_NOT_FOUND', 'Resignation request not found.', jsonb_build_object('request_id', v_request_id));
  end if;

  if v_request.request_status <> 'pending_approval' then
    return public.platform_json_response(false, 'INVALID_REQUEST_STATE', 'Resignation request is not pending approval.', jsonb_build_object('request_status', v_request.request_status));
  end if;

  if v_approved_last_working_day < v_request.resignation_date then
    return public.platform_json_response(false, 'INVALID_LAST_WORKING_DAY', 'approved_last_working_day cannot be earlier than resignation_date.', '{}'::jsonb);
  end if;

  if v_approved_last_working_day > current_date + 365 then
    return public.platform_json_response(false, 'LAST_WORKING_DAY_TOO_FAR', 'approved_last_working_day cannot be more than one year in the future.', '{}'::jsonb);
  end if;

  if not v_waive_notice_shortfall and v_approved_last_working_day < v_request.tentative_leaving_date then
    return public.platform_json_response(false, 'WAIVER_REQUIRED', 'waive_notice_shortfall must be true when approved_last_working_day is earlier than tentative_leaving_date.', jsonb_build_object(
      'tentative_leaving_date', v_request.tentative_leaving_date,
      'approved_last_working_day', v_approved_last_working_day
    ));
  end if;

  execute format(
    'select joining_date, service_state, employment_status, confirmation_date, relief_date, position_id, last_billable, state_notes
     from %I.wcm_employee_service_state
     where employee_id = $1',
    v_schema_name
  )
  into v_joining_date, v_service_state, v_employment_status, v_confirmation_date, v_relief_date, v_position_id, v_last_billable, v_state_notes
  using v_request.employee_id;

  if v_joining_date is null then
    return public.platform_json_response(false, 'EMPLOYEE_SERVICE_STATE_NOT_FOUND', 'Employee service state is required before approval can be processed.', jsonb_build_object('employee_id', v_request.employee_id));
  end if;

  v_service_state_result := public.platform_upsert_wcm_service_state(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'employee_id', v_request.employee_id,
    'joining_date', v_joining_date,
    'service_state', coalesce(v_service_state, 'active'),
    'employment_status', coalesce(v_employment_status, 'active'),
    'confirmation_date', v_confirmation_date,
    'leaving_date', v_approved_last_working_day,
    'relief_date', coalesce(v_relief_date, v_approved_last_working_day),
    'separation_type', 'resignation',
    'full_and_final_status', 'pending',
    'position_id', coalesce(v_request.position_id, v_position_id),
    'last_billable', coalesce(v_last_billable, true),
    'state_notes', coalesce(v_state_notes, '{}'::jsonb) || jsonb_build_object(
      'wcm_resignation_request_id', v_request.request_id,
      'wcm_resignation_status', 'approved_pending_clearance'
    ),
    'source_module', 'WCM_CORE',
    'event_reason', coalesce(v_remarks, v_request.separation_reason)
  ));

  if coalesce((v_service_state_result->>'success')::boolean, false) is not true then
    raise exception 'WCM_SERVICE_STATE_APPROVAL_APPLY_FAILED: %', v_service_state_result::text;
  end if;

  update public.platform_wcm_resignation_request
  set request_status = 'approved_pending_clearance',
      approved_last_working_day = v_approved_last_working_day,
      waive_notice_shortfall = v_waive_notice_shortfall,
      approved_by_actor_user_id = v_actor_user_id,
      approved_at = timezone('utc', now()),
      comments = coalesce(v_remarks, comments),
      request_metadata = coalesce(request_metadata, '{}'::jsonb) || jsonb_build_object(
        'approval_remarks', v_remarks,
        'full_and_final_status', 'pending'
      ),
      updated_at = timezone('utc', now())
  where request_id = v_request.request_id;

  v_event_result := public.platform_log_wcm_lifecycle_event(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'employee_id', v_request.employee_id,
    'event_type', 'resignation_approved',
    'source_module', 'WCM_CORE',
    'event_reason', v_remarks,
    'event_details', jsonb_build_object(
      'request_id', v_request.request_id,
      'approved_last_working_day', v_approved_last_working_day,
      'waive_notice_shortfall', v_waive_notice_shortfall
    )
  ));

  if coalesce((v_event_result->>'success')::boolean, false) is not true then
    raise exception 'WCM_RESIGNATION_APPROVAL_EVENT_LOG_FAILED: %', v_event_result::text;
  end if;

  v_event_id := public.platform_enqueue_wcm_lifecycle_event(
    v_tenant_id,
    v_request.request_id,
    v_request.employee_id,
    'resignation_approval_followup',
    jsonb_build_object(
      'approved_last_working_day', v_approved_last_working_day,
      'waive_notice_shortfall', v_waive_notice_shortfall,
      'remarks', v_remarks
    ),
    v_actor_user_id
  );

  return public.platform_json_response(true, 'ACCEPTED', 'Resignation approval recorded and follow-up queued.', jsonb_build_object(
    'tenant_id', v_tenant_id,
    'request_id', v_request.request_id,
    'employee_id', v_request.employee_id,
    'request_status', 'approved_pending_clearance',
    'event_id', v_event_id,
    'approved_last_working_day', v_approved_last_working_day
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_process_wcm_resignation_approval.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_request_wcm_resignation(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_context_result jsonb;
  v_context_details jsonb;
  v_schema_name text;
  v_tenant_id uuid;
  v_employee_id uuid := public.platform_try_uuid(p_params->>'employee_id');
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_resignation_date date := public.platform_wcm_try_date(p_params->>'resignation_date');
  v_tentative_leaving_date date := public.platform_wcm_try_date(p_params->>'tentative_leaving_date');
  v_separation_reason text := nullif(btrim(coalesce(p_params->>'separation_reason', '')), '');
  v_comments text := nullif(btrim(coalesce(p_params->>'comments', '')), '');
  v_employee_actor_user_id uuid;
  v_position_id bigint;
  v_service_state text;
  v_employment_status text;
  v_joining_date date;
  v_request_id uuid;
  v_authority_sync_result jsonb;
  v_event_result jsonb;
begin
  v_context_result := public.platform_wcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');
  v_tenant_id := public.platform_try_uuid(v_context_details->>'tenant_id');

  if v_employee_id is null then
    return public.platform_json_response(false, 'EMPLOYEE_ID_REQUIRED', 'employee_id is required.', '{}'::jsonb);
  end if;

  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_CONTEXT_REQUIRED', 'actor_user_id or current actor context is required.', '{}'::jsonb);
  end if;

  if v_resignation_date is null then
    return public.platform_json_response(false, 'RESIGNATION_DATE_REQUIRED', 'resignation_date is required.', '{}'::jsonb);
  end if;

  if v_tentative_leaving_date is null then
    v_tentative_leaving_date := v_resignation_date + 30;
  end if;

  if v_tentative_leaving_date < v_resignation_date then
    return public.platform_json_response(false, 'INVALID_TENTATIVE_LEAVING_DATE', 'tentative_leaving_date cannot be earlier than resignation_date.', '{}'::jsonb);
  end if;

  execute format(
    'select e.actor_user_id, s.position_id, s.service_state, s.employment_status, s.joining_date
     from %I.wcm_employee e
     join %I.wcm_employee_service_state s on s.employee_id = e.employee_id
     where e.employee_id = $1',
    v_schema_name,
    v_schema_name
  )
  into v_employee_actor_user_id, v_position_id, v_service_state, v_employment_status, v_joining_date
  using v_employee_id;

  if v_joining_date is null then
    return public.platform_json_response(false, 'EMPLOYEE_SERVICE_STATE_NOT_FOUND', 'Employee service state is required before resignation can be requested.', jsonb_build_object('employee_id', v_employee_id));
  end if;

  if lower(coalesce(v_service_state, '')) = 'separated'
     or lower(coalesce(v_employment_status, '')) in ('separated', 'terminated', 'exit') then
    return public.platform_json_response(false, 'EMPLOYEE_ALREADY_SEPARATED', 'The employee is already in a separated state.', jsonb_build_object('employee_id', v_employee_id));
  end if;

  if exists (
    select 1
    from public.platform_wcm_resignation_request
    where tenant_id = v_tenant_id
      and employee_id = v_employee_id
      and request_status in ('pending_approval', 'approved_pending_clearance')
  ) then
    return public.platform_json_response(false, 'ACTIVE_RESIGNATION_REQUEST_EXISTS', 'An active resignation request already exists for the employee.', jsonb_build_object('employee_id', v_employee_id));
  end if;

  insert into public.platform_wcm_resignation_request (
    tenant_id,
    employee_id,
    actor_user_id,
    position_id,
    request_status,
    resignation_date,
    tentative_leaving_date,
    separation_reason,
    comments,
    request_metadata
  ) values (
    v_tenant_id,
    v_employee_id,
    v_actor_user_id,
    v_position_id,
    'pending_approval',
    v_resignation_date,
    v_tentative_leaving_date,
    v_separation_reason,
    v_comments,
    jsonb_build_object(
      'employee_actor_user_id', v_employee_actor_user_id,
      'joining_date', v_joining_date,
      'service_state', v_service_state,
      'employment_status', v_employment_status,
      'source_module', 'WCM_CORE'
    )
  ) returning request_id into v_request_id;

  v_authority_sync_result := public.platform_sync_wcm_resignation_authority(v_tenant_id, v_employee_id, v_actor_user_id);
  if coalesce((v_authority_sync_result->>'success')::boolean, false) is not true then
    raise exception 'WCM_RESIGNATION_AUTHORITY_SYNC_FAILED: %', v_authority_sync_result::text;
  end if;

  v_event_result := public.platform_log_wcm_lifecycle_event(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'employee_id', v_employee_id,
    'event_type', 'resignation_requested',
    'source_module', 'WCM_CORE',
    'event_reason', v_separation_reason,
    'event_details', jsonb_build_object(
      'request_id', v_request_id,
      'resignation_date', v_resignation_date,
      'tentative_leaving_date', v_tentative_leaving_date,
      'position_id', v_position_id
    )
  ));

  if coalesce((v_event_result->>'success')::boolean, false) is not true then
    raise exception 'WCM_RESIGNATION_EVENT_LOG_FAILED: %', v_event_result::text;
  end if;

  return public.platform_json_response(true, 'OK', 'WCM resignation request recorded.', jsonb_build_object(
    'tenant_id', v_tenant_id,
    'request_id', v_request_id,
    'employee_id', v_employee_id,
    'request_status', 'pending_approval',
    'resignation_date', v_resignation_date,
    'tentative_leaving_date', v_tentative_leaving_date,
    'position_id', v_position_id
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_request_wcm_resignation.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_sync_wcm_resignation_authority(p_tenant_id uuid, p_employee_id uuid, p_actor_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_context_result jsonb;
  v_details jsonb;
  v_schema_name text;
  v_employee_exists boolean := false;
  v_position_id bigint;
begin
  if p_employee_id is null then
    return public.platform_json_response(false, 'EMPLOYEE_ID_REQUIRED', 'employee_id is required.', '{}'::jsonb);
  end if;

  v_context_result := public.platform_wcm_internal_resolve_context(p_tenant_id, 'platform_sync_wcm_resignation_authority');
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  v_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := v_details->>'tenant_schema';

  execute format('select exists (select 1 from %I.wcm_employee where employee_id = $1)', v_schema_name)
    into v_employee_exists
    using p_employee_id;

  if not v_employee_exists then
    return public.platform_json_response(false, 'EMPLOYEE_NOT_FOUND', 'Employee not found for resignation authority sync.', jsonb_build_object('employee_id', p_employee_id));
  end if;

  perform public.platform_hierarchy_sync_wcm_position_state(v_schema_name, p_employee_id);

  execute format('select position_id from %I.wcm_employee_service_state where employee_id = $1', v_schema_name)
    into v_position_id
    using p_employee_id;

  return public.platform_json_response(true, 'OK', 'WCM resignation authority synced.', jsonb_build_object(
    'tenant_id', public.platform_try_uuid(v_details->>'tenant_id'),
    'employee_id', p_employee_id,
    'position_id', v_position_id,
    'actor_user_id', p_actor_user_id
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_sync_wcm_resignation_authority.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_wcm_internal_resolve_context(p_tenant_id uuid, p_source text DEFAULT 'platform_wcm_internal_resolve_context'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
  v_details jsonb;
begin
  if p_tenant_id is null then
    return public.platform_json_response(false, 'TENANT_ID_REQUIRED', 'tenant_id is required.', '{}'::jsonb);
  end if;

  v_result := public.platform_apply_execution_context(jsonb_build_object(
    'execution_mode', 'internal_platform',
    'tenant_id', p_tenant_id,
    'source', coalesce(nullif(btrim(p_source), ''), 'platform_wcm_internal_resolve_context')
  ));

  if coalesce((v_result->>'success')::boolean, false) is not true then
    return v_result;
  end if;

  v_details := coalesce(v_result->'details', '{}'::jsonb);

  if not public.platform_table_exists(v_details->>'tenant_schema', 'wcm_employee')
    or not public.platform_table_exists(v_details->>'tenant_schema', 'wcm_employee_service_state')
    or not public.platform_table_exists(v_details->>'tenant_schema', 'wcm_employee_lifecycle_event')
  then
    return public.platform_json_response(
      false,
      'WCM_CORE_TEMPLATE_NOT_APPLIED',
      'WCM_CORE is not applied to the requested tenant schema.',
      jsonb_build_object(
        'tenant_id', public.platform_try_uuid(v_details->>'tenant_id'),
        'tenant_schema', v_details->>'tenant_schema'
      )
    );
  end if;

  return public.platform_json_response(
    true,
    'OK',
    'WCM internal execution context resolved.',
    jsonb_build_object(
      'tenant_id', public.platform_try_uuid(v_details->>'tenant_id'),
      'tenant_schema', v_details->>'tenant_schema'
    )
  );
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_wcm_internal_resolve_context.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_withdraw_wcm_resignation(p_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_context_result jsonb;
  v_context_details jsonb;
  v_schema_name text;
  v_tenant_id uuid;
  v_request_id uuid := public.platform_try_uuid(p_params->>'request_id');
  v_actor_user_id uuid := coalesce(public.platform_try_uuid(p_params->>'actor_user_id'), public.platform_current_actor_user_id());
  v_reason text := nullif(btrim(coalesce(p_params->>'reason', '')), '');
  v_request public.platform_wcm_resignation_request%rowtype;
  v_joining_date date;
  v_service_state text;
  v_employment_status text;
  v_confirmation_date date;
  v_position_id bigint;
  v_last_billable boolean;
  v_state_notes jsonb;
  v_service_state_result jsonb;
  v_event_result jsonb;
  v_event_id uuid;
begin
  v_context_result := public.platform_wcm_resolve_context(p_params);
  if coalesce((v_context_result->>'success')::boolean, false) is not true then
    return v_context_result;
  end if;

  v_context_details := coalesce(v_context_result->'details', '{}'::jsonb);
  v_schema_name := nullif(v_context_details->>'tenant_schema', '');
  v_tenant_id := public.platform_try_uuid(v_context_details->>'tenant_id');

  if v_request_id is null then
    return public.platform_json_response(false, 'REQUEST_ID_REQUIRED', 'request_id is required.', '{}'::jsonb);
  end if;

  if v_actor_user_id is null then
    return public.platform_json_response(false, 'ACTOR_CONTEXT_REQUIRED', 'actor_user_id or current actor context is required.', '{}'::jsonb);
  end if;

  select *
  into v_request
  from public.platform_wcm_resignation_request
  where request_id = v_request_id
    and tenant_id = v_tenant_id
  for update;

  if not found then
    return public.platform_json_response(false, 'REQUEST_NOT_FOUND', 'Resignation request not found.', jsonb_build_object('request_id', v_request_id));
  end if;

  if v_request.request_status = 'withdrawn' then
    return public.platform_json_response(false, 'REQUEST_ALREADY_WITHDRAWN', 'Resignation request is already withdrawn.', jsonb_build_object('request_id', v_request_id));
  end if;

  if v_request.request_status = 'completed' then
    return public.platform_json_response(false, 'REQUEST_ALREADY_COMPLETED', 'Completed resignation requests cannot be withdrawn.', jsonb_build_object('request_id', v_request_id));
  end if;

  execute format(
    'select joining_date, service_state, employment_status, confirmation_date, position_id, last_billable, state_notes
     from %I.wcm_employee_service_state
     where employee_id = $1',
    v_schema_name
  )
  into v_joining_date, v_service_state, v_employment_status, v_confirmation_date, v_position_id, v_last_billable, v_state_notes
  using v_request.employee_id;

  if v_joining_date is null then
    return public.platform_json_response(false, 'EMPLOYEE_SERVICE_STATE_NOT_FOUND', 'Employee service state is required before withdrawal can be processed.', jsonb_build_object('employee_id', v_request.employee_id));
  end if;

  v_service_state_result := public.platform_upsert_wcm_service_state(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'employee_id', v_request.employee_id,
    'joining_date', v_joining_date,
    'service_state', case when lower(coalesce(v_service_state, '')) = 'separated' then 'active' else coalesce(v_service_state, 'active') end,
    'employment_status', case when lower(coalesce(v_employment_status, '')) in ('separated', 'terminated', 'exit') then 'active' else coalesce(v_employment_status, 'active') end,
    'confirmation_date', v_confirmation_date,
    'leaving_date', null,
    'relief_date', null,
    'separation_type', null,
    'full_and_final_status', null,
    'full_and_final_process_date', null,
    'position_id', coalesce(v_request.position_id, v_position_id),
    'last_billable', coalesce(v_last_billable, false),
    'state_notes', coalesce(v_state_notes, '{}'::jsonb) || jsonb_build_object(
      'wcm_resignation_request_id', v_request.request_id,
      'wcm_resignation_status', 'withdrawn'
    ),
    'source_module', 'WCM_CORE',
    'event_reason', coalesce(v_reason, 'resignation_withdrawn')
  ));

  if coalesce((v_service_state_result->>'success')::boolean, false) is not true then
    raise exception 'WCM_SERVICE_STATE_WITHDRAWAL_APPLY_FAILED: %', v_service_state_result::text;
  end if;

  update public.platform_wcm_resignation_request
  set request_status = 'withdrawn',
      withdrawn_by_actor_user_id = v_actor_user_id,
      withdrawn_at = timezone('utc', now()),
      comments = coalesce(v_reason, comments),
      updated_at = timezone('utc', now())
  where request_id = v_request.request_id;

  v_event_result := public.platform_log_wcm_lifecycle_event(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'employee_id', v_request.employee_id,
    'event_type', 'resignation_withdrawn',
    'source_module', 'WCM_CORE',
    'event_reason', v_reason,
    'event_details', jsonb_build_object(
      'request_id', v_request.request_id,
      'request_status', 'withdrawn'
    )
  ));

  if coalesce((v_event_result->>'success')::boolean, false) is not true then
    raise exception 'WCM_RESIGNATION_WITHDRAWAL_EVENT_LOG_FAILED: %', v_event_result::text;
  end if;

  v_event_id := public.platform_enqueue_wcm_lifecycle_event(
    v_tenant_id,
    v_request.request_id,
    v_request.employee_id,
    'resignation_withdrawal_followup',
    jsonb_build_object('reason', v_reason),
    v_actor_user_id
  );

  return public.platform_json_response(true, 'ACCEPTED', 'Resignation withdrawal recorded and follow-up queued.', jsonb_build_object(
    'tenant_id', v_tenant_id,
    'request_id', v_request.request_id,
    'employee_id', v_request.employee_id,
    'request_status', 'withdrawn',
    'event_id', v_event_id
  ));
exception
  when others then
    return public.platform_json_response(false, 'UNEXPECTED_ERROR', 'Unexpected error in platform_withdraw_wcm_resignation.', jsonb_build_object('sqlstate', sqlstate, 'sqlerrm', sqlerrm));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_write_wcm_lifecycle_rollback_audit(p_tenant_id uuid, p_request_id uuid, p_employee_id uuid, p_position_id bigint, p_decision_code text, p_action_code text, p_manual_review_required boolean, p_actor_user_id uuid, p_reason text, p_audit_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_audit_id bigint;
begin
  insert into public.platform_wcm_lifecycle_rollback_audit (
    tenant_id,
    request_id,
    employee_id,
    position_id,
    decision_code,
    action_code,
    manual_review_required,
    actor_user_id,
    reason,
    audit_payload
  ) values (
    p_tenant_id,
    p_request_id,
    p_employee_id,
    p_position_id,
    coalesce(p_decision_code, 'unknown'),
    coalesce(p_action_code, 'unknown'),
    coalesce(p_manual_review_required, false),
    p_actor_user_id,
    p_reason,
    coalesce(p_audit_payload, '{}'::jsonb)
  )
  returning audit_id into v_audit_id;

  return v_audit_id;
end;
$function$
;

revoke all on public.platform_wcm_resignation_request from public, anon, authenticated;
revoke all on public.platform_wcm_lifecycle_rollback_audit from public, anon, authenticated;
revoke all on public.platform_wcm_lifecycle_event_queue from public, anon, authenticated;
revoke all on public.platform_rm_wcm_resignation_request_catalog from public, anon, authenticated;
revoke all on public.platform_rm_wcm_lifecycle_rollback_audit from public, anon, authenticated;

grant all on public.platform_wcm_resignation_request to service_role;
grant all on public.platform_wcm_lifecycle_rollback_audit to service_role;
grant all on public.platform_wcm_lifecycle_event_queue to service_role;
grant all on public.platform_rm_wcm_resignation_request_catalog to service_role;
grant all on public.platform_rm_wcm_lifecycle_rollback_audit to service_role;

revoke all on function public.platform_wcm_internal_resolve_context(uuid, text) from public, anon, authenticated;
revoke all on function public.platform_write_wcm_lifecycle_rollback_audit(uuid, uuid, uuid, bigint, text, text, boolean, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.platform_enqueue_wcm_lifecycle_event(uuid, uuid, uuid, text, jsonb, uuid) from public, anon, authenticated;
revoke all on function public.platform_sync_wcm_resignation_authority(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.platform_request_wcm_resignation(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_wcm_resignation_approval(jsonb) from public, anon, authenticated;
revoke all on function public.platform_get_wcm_resignation_rollback_decision(uuid, uuid) from public, anon, authenticated;
revoke all on function public.platform_preview_wcm_resignation_rollback(jsonb) from public, anon, authenticated;
revoke all on function public.platform_apply_wcm_resignation_rollback(uuid, uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.platform_withdraw_wcm_resignation(jsonb) from public, anon, authenticated;
revoke all on function public.platform_process_wcm_pending_events(integer) from public, anon, authenticated;

grant execute on function public.platform_wcm_internal_resolve_context(uuid, text) to service_role;
grant execute on function public.platform_write_wcm_lifecycle_rollback_audit(uuid, uuid, uuid, bigint, text, text, boolean, uuid, text, jsonb) to service_role;
grant execute on function public.platform_enqueue_wcm_lifecycle_event(uuid, uuid, uuid, text, jsonb, uuid) to service_role;
grant execute on function public.platform_sync_wcm_resignation_authority(uuid, uuid, uuid) to service_role;
grant execute on function public.platform_request_wcm_resignation(jsonb) to service_role;
grant execute on function public.platform_process_wcm_resignation_approval(jsonb) to service_role;
grant execute on function public.platform_get_wcm_resignation_rollback_decision(uuid, uuid) to service_role;
grant execute on function public.platform_preview_wcm_resignation_rollback(jsonb) to service_role;
grant execute on function public.platform_apply_wcm_resignation_rollback(uuid, uuid, uuid, text, jsonb) to service_role;
grant execute on function public.platform_withdraw_wcm_resignation(jsonb) to service_role;
grant execute on function public.platform_process_wcm_pending_events(integer) to service_role;

do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_read_model(jsonb_build_object(
    'read_model_code', 'wcm_resignation_request_catalog',
    'module_code', 'WCM_CORE',
    'read_model_name', 'Wcm Resignation Request Catalog',
    'schema_placement', 'public',
    'storage_kind', 'view',
    'ownership_scope', 'platform_shared',
    'object_name', 'platform_rm_wcm_resignation_request_catalog',
    'refresh_strategy', 'none',
    'refresh_mode', 'none',
    'refresh_owner_code', 'WCM_CORE',
    'notes', 'WCM workforce separation runtime.',
    'metadata', jsonb_build_object(
      'source', 'wcm_core_separation_lifecycle_runtime',
      'object_name', 'platform_rm_wcm_resignation_request_catalog'
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_resignation_request_catalog registration failed: %', v_result;
  end if;

  v_result := public.platform_register_read_model(jsonb_build_object(
    'read_model_code', 'wcm_lifecycle_rollback_audit',
    'module_code', 'WCM_CORE',
    'read_model_name', 'Wcm Lifecycle Rollback Audit',
    'schema_placement', 'public',
    'storage_kind', 'view',
    'ownership_scope', 'platform_shared',
    'object_name', 'platform_rm_wcm_lifecycle_rollback_audit',
    'refresh_strategy', 'none',
    'refresh_mode', 'none',
    'refresh_owner_code', 'WCM_CORE',
    'notes', 'WCM workforce separation rollback audit runtime.',
    'metadata', jsonb_build_object(
      'source', 'wcm_core_separation_lifecycle_runtime',
      'object_name', 'platform_rm_wcm_lifecycle_rollback_audit'
    )
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_lifecycle_rollback_audit registration failed: %', v_result;
  end if;
end
$$;

do $$
declare
  v_result jsonb;
begin
  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'wcm_action_request_resignation',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'binding_ref', 'platform_request_wcm_resignation',
    'dispatch_config', '{}'::jsonb,
    'static_params', '{}'::jsonb,
    'request_contract', jsonb_build_object(
      'allowed_keys', jsonb_build_array('employee_id', 'resignation_date', 'tentative_leaving_date', 'separation_reason', 'comments')
    ),
    'response_contract', '{}'::jsonb,
    'group_name', 'WCM Core',
    'synopsis', 'Create a resignation request for a WCM employee',
    'metadata', '{}'::jsonb
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_action_request_resignation registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'wcm_action_request_resignation',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_action_request_resignation role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'wcm_action_process_resignation_approval',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'binding_ref', 'platform_process_wcm_resignation_approval',
    'dispatch_config', '{}'::jsonb,
    'static_params', '{}'::jsonb,
    'request_contract', jsonb_build_object(
      'allowed_keys', jsonb_build_array('request_id', 'approved_last_working_day', 'waive_notice_shortfall', 'remarks')
    ),
    'response_contract', '{}'::jsonb,
    'group_name', 'WCM Core',
    'synopsis', 'Approve a resignation request and queue follow-up runtime',
    'metadata', '{}'::jsonb
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_action_process_resignation_approval registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'wcm_action_process_resignation_approval',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_action_process_resignation_approval role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'wcm_action_withdraw_resignation',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'binding_ref', 'platform_withdraw_wcm_resignation',
    'dispatch_config', '{}'::jsonb,
    'static_params', '{}'::jsonb,
    'request_contract', jsonb_build_object(
      'allowed_keys', jsonb_build_array('request_id', 'reason')
    ),
    'response_contract', '{}'::jsonb,
    'group_name', 'WCM Core',
    'synopsis', 'Withdraw a resignation request and queue rollback follow-up',
    'metadata', '{}'::jsonb
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_action_withdraw_resignation registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'wcm_action_withdraw_resignation',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_action_withdraw_resignation role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'wcm_action_preview_resignation_rollback',
    'operation_mode', 'action',
    'dispatch_kind', 'function_action',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'binding_ref', 'platform_preview_wcm_resignation_rollback',
    'dispatch_config', '{}'::jsonb,
    'static_params', '{}'::jsonb,
    'request_contract', jsonb_build_object(
      'allowed_keys', jsonb_build_array('request_id')
    ),
    'response_contract', '{}'::jsonb,
    'group_name', 'WCM Core',
    'synopsis', 'Preview downstream rollback impact for a resignation request',
    'metadata', '{}'::jsonb
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_action_preview_resignation_rollback registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'wcm_action_preview_resignation_rollback',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_action_preview_resignation_rollback role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'wcm_read_resignation_request_catalog',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_wcm_resignation_request_catalog',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'request_id', 'tenant_id', 'employee_id', 'position_id', 'request_status',
        'resignation_date', 'tentative_leaving_date', 'approved_last_working_day',
        'waive_notice_shortfall', 'separation_reason', 'comments',
        'lifecycle_runtime_status', 'last_event_id', 'last_decision_code',
        'last_action_code', 'last_runtime_message', 'approved_by_actor_user_id',
        'approved_at', 'withdrawn_by_actor_user_id', 'withdrawn_at',
        'created_at', 'updated_at', 'request_metadata'
      ),
      'filter_columns', jsonb_build_array(
        'request_id', 'employee_id', 'position_id', 'request_status', 'lifecycle_runtime_status'
      ),
      'sort_columns', jsonb_build_array('created_at', 'updated_at', 'resignation_date'),
      'tenant_column', 'tenant_id'
    ),
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'WCM Core',
    'synopsis', 'Read WCM resignation request catalog',
    'metadata', '{}'::jsonb
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_read_resignation_request_catalog registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'wcm_read_resignation_request_catalog',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_read_resignation_request_catalog role assignment failed: %', v_result;
  end if;

  v_result := public.platform_register_gateway_operation(jsonb_build_object(
    'operation_code', 'wcm_read_lifecycle_rollback_audit',
    'operation_mode', 'read',
    'dispatch_kind', 'read_surface',
    'operation_status', 'active',
    'route_policy', 'tenant_required',
    'tenant_requirement', 'required',
    'idempotency_policy', 'optional',
    'rate_limit_policy', 'default',
    'max_limit_per_request', 250,
    'binding_ref', 'platform_rm_wcm_lifecycle_rollback_audit',
    'dispatch_config', jsonb_build_object(
      'select_columns', jsonb_build_array(
        'audit_id', 'tenant_id', 'request_id', 'employee_id', 'position_id',
        'decision_code', 'action_code', 'manual_review_required', 'actor_user_id',
        'reason', 'audit_payload', 'created_at'
      ),
      'filter_columns', jsonb_build_array(
        'audit_id', 'request_id', 'employee_id', 'position_id', 'decision_code',
        'action_code', 'manual_review_required'
      ),
      'sort_columns', jsonb_build_array('created_at', 'audit_id'),
      'tenant_column', 'tenant_id'
    ),
    'static_params', '{}'::jsonb,
    'request_contract', '{}'::jsonb,
    'response_contract', '{}'::jsonb,
    'group_name', 'WCM Core',
    'synopsis', 'Read WCM lifecycle rollback audit',
    'metadata', '{}'::jsonb
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_read_lifecycle_rollback_audit registration failed: %', v_result;
  end if;

  v_result := public.platform_assign_gateway_operation_role(jsonb_build_object(
    'operation_code', 'wcm_read_lifecycle_rollback_audit',
    'role_code', 'tenant_owner_admin'
  ));
  if coalesce((v_result->>'success')::boolean, false) is not true then
    raise exception 'wcm_read_lifecycle_rollback_audit role assignment failed: %', v_result;
  end if;
end
$$;

do $$
declare
  v_job record;
begin
  for v_job in
    select jobid
    from cron.job
    where jobname = 'wcm-core-lifecycle-heartbeat'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;

  perform cron.schedule(
    'wcm-core-lifecycle-heartbeat',
    '* * * * *',
    'select public.platform_process_wcm_pending_events(25);'
  );
end;
$$;

