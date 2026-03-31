create or replace view public.platform_rm_gateway_operation_catalog
with (security_invoker = true)
as
select
  pgo.operation_code,
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
  coalesce(
    array_agg(pgor.role_code order by pgor.role_code)
      filter (where pgor.role_code is not null),
    '{}'::text[]
  ) as allowed_role_codes
from public.platform_gateway_operation pgo
left join public.platform_gateway_operation_role pgor
  on pgor.operation_code = pgo.operation_code
group by
  pgo.operation_code,
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
  pgo.updated_at;;
