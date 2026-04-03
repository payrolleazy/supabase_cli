revoke all on function public.platform_i05_run_document_maintenance(jsonb) from public, anon, authenticated;
revoke all on function public.platform_i05_run_document_maintenance_scheduler() from public, anon, authenticated;
grant execute on function public.platform_i05_run_document_maintenance(jsonb) to service_role;
grant execute on function public.platform_i05_run_document_maintenance_scheduler() to service_role;

alter view public.platform_rm_storage_bucket_catalog set (security_invoker = true);
alter view public.platform_rm_document_catalog set (security_invoker = true);
alter view public.platform_rm_document_binding_catalog set (security_invoker = true);

insert into public.platform_access_role (
  role_code,
  role_scope,
  role_status,
  description,
  metadata,
  created_at,
  updated_at
)
values (
  'i05_proof_document_admin',
  'tenant',
  'active',
  'I05 proof document administrator role',
  '{"purpose":"persistent_proof_seed"}'::jsonb,
  timezone('utc', now()),
  timezone('utc', now())
)
on conflict (role_code) do update
set
  role_scope = excluded.role_scope,
  role_status = excluded.role_status,
  description = excluded.description,
  metadata = excluded.metadata,
  updated_at = timezone('utc', now());

insert into public.platform_gateway_operation (
  operation_code,
  operation_mode,
  dispatch_kind,
  operation_status,
  route_policy,
  tenant_requirement,
  idempotency_policy,
  rate_limit_policy,
  max_limit_per_request,
  binding_ref,
  dispatch_config,
  static_params,
  request_contract,
  response_contract,
  group_name,
  synopsis,
  description,
  metadata,
  created_at,
  updated_at,
  created_by,
  updated_by
)
values
(
  'i05_proof_action_get_document_access',
  'action',
  'function_action',
  'active',
  'tenant_required',
  'required',
  'required',
  'default',
  null,
  'platform_get_document_access_descriptor',
  '{}'::jsonb,
  '{}'::jsonb,
  '{"allowed_keys":["document_id","actor_user_id"],"required_keys":["document_id"]}'::jsonb,
  '{}'::jsonb,
  'I05 Proof',
  'Resolve document access descriptor',
  null,
  '{}'::jsonb,
  timezone('utc', now()),
  timezone('utc', now()),
  null,
  null
),
(
  'i05_proof_mutate_document_binding',
  'mutate',
  'mutation_adapter',
  'active',
  'tenant_required',
  'required',
  'required',
  'default',
  null,
  'platform_bind_document_record',
  '{}'::jsonb,
  '{}'::jsonb,
  '{"allowed_keys":["document_id","target_entity_code","target_key","relation_purpose","bound_by_actor_user_id","metadata"],"required_keys":["document_id","target_entity_code","target_key"]}'::jsonb,
  '{}'::jsonb,
  'I05 Proof',
  'Register or update document binding',
  null,
  '{}'::jsonb,
  timezone('utc', now()),
  timezone('utc', now()),
  null,
  null
),
(
  'i05_proof_read_bucket_catalog',
  'read',
  'read_surface',
  'active',
  'tenant_required',
  'required',
  'optional',
  'default',
  null,
  'platform_rm_storage_bucket_catalog',
  '{"sort_columns":["bucket_code","bucket_purpose"],"filter_columns":["bucket_code","bucket_purpose","bucket_status"],"select_columns":["bucket_code","bucket_name","bucket_purpose","bucket_visibility","protection_mode","bucket_status","storage_bucket_present"]}'::jsonb,
  '{}'::jsonb,
  '{}'::jsonb,
  '{}'::jsonb,
  'I05 Proof',
  'Read governed storage bucket catalog',
  null,
  '{}'::jsonb,
  timezone('utc', now()),
  timezone('utc', now()),
  null,
  null
),
(
  'i05_proof_read_document_bindings',
  'read',
  'read_surface',
  'active',
  'tenant_required',
  'required',
  'optional',
  'default',
  null,
  'platform_rm_document_binding_catalog',
  '{"sort_columns":["created_at","document_id"],"tenant_column":"tenant_id","filter_columns":["document_id","target_entity_code","target_key","binding_status"],"select_columns":["binding_id","tenant_id","document_id","document_class_code","target_entity_code","target_key","relation_purpose","binding_status","created_at"]}'::jsonb,
  '{}'::jsonb,
  '{}'::jsonb,
  '{}'::jsonb,
  'I05 Proof',
  'Read governed document binding catalog',
  null,
  '{}'::jsonb,
  timezone('utc', now()),
  timezone('utc', now()),
  null,
  null
),
(
  'i05_proof_read_document_catalog',
  'read',
  'read_surface',
  'active',
  'tenant_required',
  'required',
  'optional',
  'default',
  null,
  'platform_rm_document_catalog',
  '{"sort_columns":["created_at","document_class_code"],"tenant_column":"tenant_id","filter_columns":["document_id","document_class_code","owner_actor_user_id","document_status"],"select_columns":["document_id","tenant_id","document_class_code","class_label","bucket_code","bucket_name","owner_actor_user_id","original_file_name","content_type","protection_mode","access_mode","document_status","created_at"]}'::jsonb,
  '{}'::jsonb,
  '{}'::jsonb,
  '{}'::jsonb,
  'I05 Proof',
  'Read governed document catalog',
  null,
  '{}'::jsonb,
  timezone('utc', now()),
  timezone('utc', now()),
  null,
  null
)
on conflict (operation_code) do update
set
  operation_mode = excluded.operation_mode,
  dispatch_kind = excluded.dispatch_kind,
  operation_status = excluded.operation_status,
  route_policy = excluded.route_policy,
  tenant_requirement = excluded.tenant_requirement,
  idempotency_policy = excluded.idempotency_policy,
  rate_limit_policy = excluded.rate_limit_policy,
  max_limit_per_request = excluded.max_limit_per_request,
  binding_ref = excluded.binding_ref,
  dispatch_config = excluded.dispatch_config,
  static_params = excluded.static_params,
  request_contract = excluded.request_contract,
  response_contract = excluded.response_contract,
  group_name = excluded.group_name,
  synopsis = excluded.synopsis,
  description = excluded.description,
  metadata = excluded.metadata,
  updated_at = timezone('utc', now()),
  updated_by = null;

delete from public.platform_gateway_operation_role
where operation_code like 'i05_%';

insert into public.platform_gateway_operation_role (operation_code, role_code, metadata, created_at, created_by)
values
('i05_proof_action_get_document_access', 'i05_proof_document_admin', '{}'::jsonb, timezone('utc', now()), null),
('i05_proof_action_get_document_access', 'tenant_owner_admin', '{}'::jsonb, timezone('utc', now()), null),
('i05_proof_mutate_document_binding', 'i05_proof_document_admin', '{}'::jsonb, timezone('utc', now()), null),
('i05_proof_mutate_document_binding', 'tenant_owner_admin', '{}'::jsonb, timezone('utc', now()), null),
('i05_proof_read_bucket_catalog', 'i05_proof_document_admin', '{}'::jsonb, timezone('utc', now()), null),
('i05_proof_read_bucket_catalog', 'tenant_owner_admin', '{}'::jsonb, timezone('utc', now()), null),
('i05_proof_read_document_bindings', 'i05_proof_document_admin', '{}'::jsonb, timezone('utc', now()), null),
('i05_proof_read_document_bindings', 'tenant_owner_admin', '{}'::jsonb, timezone('utc', now()), null),
('i05_proof_read_document_catalog', 'i05_proof_document_admin', '{}'::jsonb, timezone('utc', now()), null),
('i05_proof_read_document_catalog', 'tenant_owner_admin', '{}'::jsonb, timezone('utc', now()), null)
on conflict (operation_code, role_code) do update
set metadata = excluded.metadata;

insert into public.platform_gateway_operation_role (operation_code, role_code, metadata, created_at, created_by)
select 'i05_proof_action_get_document_access', 'i01_portal_user', '{}'::jsonb, timezone('utc', now()), null
where exists (
  select 1
  from public.platform_access_role
  where role_code = 'i01_portal_user'
)
on conflict (operation_code, role_code) do update
set metadata = excluded.metadata;
