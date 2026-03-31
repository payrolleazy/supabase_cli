create index if not exists idx_platform_extensible_attribute_schema_tenant_id
on public.platform_extensible_attribute_schema (tenant_id) where tenant_id is not null;

create index if not exists idx_platform_extensible_join_profile_tenant_id
on public.platform_extensible_join_profile (tenant_id) where tenant_id is not null;

create index if not exists idx_platform_extensible_schema_cache_tenant_id
on public.platform_extensible_schema_cache (tenant_id) where tenant_id is not null;;
