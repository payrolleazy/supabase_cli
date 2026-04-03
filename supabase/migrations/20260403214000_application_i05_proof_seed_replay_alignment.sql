insert into public.platform_storage_bucket_catalog (
  bucket_code,
  bucket_name,
  bucket_purpose,
  bucket_visibility,
  protection_mode,
  file_size_limit_bytes,
  allowed_mime_types,
  retention_days,
  bucket_status,
  metadata,
  created_by
)
values (
  'i05_proof_documents',
  'i05-proof-documents',
  'document',
  'private',
  'edge_stream',
  5242880,
  array['application/pdf', 'image/png']::text[],
  null,
  'active',
  '{"purpose":"persistent_proof_seed"}'::jsonb,
  null
)
on conflict (bucket_code) do update
set
  bucket_name = excluded.bucket_name,
  bucket_purpose = excluded.bucket_purpose,
  bucket_visibility = excluded.bucket_visibility,
  protection_mode = excluded.protection_mode,
  file_size_limit_bytes = excluded.file_size_limit_bytes,
  allowed_mime_types = excluded.allowed_mime_types,
  retention_days = excluded.retention_days,
  bucket_status = excluded.bucket_status,
  metadata = excluded.metadata,
  created_by = excluded.created_by,
  updated_at = timezone('utc', now());

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'i05-proof-documents',
  'i05-proof-documents',
  false,
  5242880,
  array['application/pdf', 'image/png']::text[]
)
on conflict (id) do update
set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

insert into public.platform_document_class (
  document_class_id,
  document_class_code,
  class_label,
  owner_module_code,
  default_bucket_code,
  sensitivity_level,
  default_access_mode,
  default_allowed_role_codes,
  default_protection_mode,
  max_file_size_bytes,
  allowed_mime_types,
  allow_multiple_bindings,
  application_encryption_required,
  class_status,
  metadata,
  created_by
)
values (
  'ee2f0816-8cf9-4c6b-8520-6e19cb000db4',
  'i05_proof_employee_document',
  'I05 Proof Employee Document',
  'i05_proof',
  'i05_proof_documents',
  'sensitive',
  'owner_and_admin',
  array['i05_proof_document_admin']::text[],
  'edge_stream',
  1048576,
  array['application/pdf']::text[],
  true,
  false,
  'active',
  '{"purpose":"persistent_proof_seed"}'::jsonb,
  null
)
on conflict (document_class_code) do update
set
  class_label = excluded.class_label,
  owner_module_code = excluded.owner_module_code,
  default_bucket_code = excluded.default_bucket_code,
  sensitivity_level = excluded.sensitivity_level,
  default_access_mode = excluded.default_access_mode,
  default_allowed_role_codes = excluded.default_allowed_role_codes,
  default_protection_mode = excluded.default_protection_mode,
  max_file_size_bytes = excluded.max_file_size_bytes,
  allowed_mime_types = excluded.allowed_mime_types,
  allow_multiple_bindings = excluded.allow_multiple_bindings,
  application_encryption_required = excluded.application_encryption_required,
  class_status = excluded.class_status,
  metadata = excluded.metadata,
  created_by = excluded.created_by,
  updated_at = timezone('utc', now());
