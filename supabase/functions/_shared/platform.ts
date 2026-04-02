import { EdgeHttpError } from "./http.ts";
import type { JsonMap, PlatformRpcResult } from "./supabase.ts";

export type AccessMembership = {
  tenant_id: string;
  tenant_code: string;
  schema_name: string | null;
  membership_status: string;
  routing_status: string;
  is_default_tenant: boolean;
  access_state: string | null;
  client_access_allowed: boolean;
  background_processing_allowed: boolean;
  active_role_codes: string[];
};

export type AccessContext = {
  actor_user_id: string | null;
  profile: JsonMap;
  memberships: AccessMembership[];
};

export type SigninPolicy = {
  policy_code: string;
  entrypoint_code: string;
  requires_password: boolean;
  requires_otp: boolean;
  allowed_role_codes: string[];
  allowed_membership_statuses: string[];
};

function asObject(value: unknown): JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as JsonMap)
    : {};
}

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asBoolean(value: unknown): boolean {
  return value === true || value === "true";
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const normalized = value
    .filter((entry) => typeof entry === "string")
    .map((entry) => (entry as string).trim().toLowerCase())
    .filter(Boolean);
  return Array.from(new Set(normalized));
}

export function requirePlatformSuccess(
  result: PlatformRpcResult,
  status: number,
  fallbackCode: string,
  fallbackMessage: string,
): JsonMap {
  if (result?.success) {
    return asObject(result.details);
  }

  throw new EdgeHttpError(
    result?.message || fallbackMessage,
    status,
    result?.code || fallbackCode,
    asObject(result?.details),
  );
}

export function parseAccessContext(details: JsonMap): AccessContext {
  const memberships = Array.isArray(details.memberships)
    ? details.memberships.map((entry) => {
      const row = asObject(entry);
      return {
        tenant_id: asString(row.tenant_id),
        tenant_code: asString(row.tenant_code),
        schema_name: asString(row.schema_name) || null,
        membership_status: asString(row.membership_status).toLowerCase(),
        routing_status: asString(row.routing_status).toLowerCase(),
        is_default_tenant: asBoolean(row.is_default_tenant),
        access_state: asString(row.access_state) || null,
        client_access_allowed: asBoolean(row.client_access_allowed),
        background_processing_allowed: asBoolean(row.background_processing_allowed),
        active_role_codes: asStringArray(row.active_role_codes),
      };
    })
    : [];

  return {
    actor_user_id: asString(details.actor_user_id) || null,
    profile: asObject(details.profile),
    memberships,
  };
}

export function parseSigninPolicy(details: JsonMap): SigninPolicy {
  return {
    policy_code: asString(details.policy_code).toLowerCase(),
    entrypoint_code: asString(details.entrypoint_code).toLowerCase(),
    requires_password: asBoolean(details.requires_password),
    requires_otp: asBoolean(details.requires_otp),
    allowed_role_codes: asStringArray(details.allowed_role_codes),
    allowed_membership_statuses: asStringArray(details.allowed_membership_statuses),
  };
}

export function selectAllowedMembership(
  accessContext: AccessContext,
  policy: SigninPolicy,
  requestedTenantId?: string | null,
): AccessMembership | null {
  const allowedRoles = new Set(policy.allowed_role_codes);
  const allowedMembershipStatuses = new Set(policy.allowed_membership_statuses);

  const candidates = accessContext.memberships
    .filter((membership) => !requestedTenantId || membership.tenant_id === requestedTenantId)
    .filter((membership) => membership.client_access_allowed)
    .filter((membership) =>
      allowedMembershipStatuses.size === 0 || allowedMembershipStatuses.has(membership.membership_status)
    )
    .filter((membership) =>
      allowedRoles.size === 0 ||
      membership.active_role_codes.some((roleCode) => allowedRoles.has(roleCode))
    )
    .sort((left, right) => {
      if (left.is_default_tenant !== right.is_default_tenant) {
        return left.is_default_tenant ? -1 : 1;
      }
      return left.tenant_code.localeCompare(right.tenant_code);
    });

  return candidates[0] ?? null;
}

export type GatewayEnvelope = {
  success: boolean;
  operation_code: string;
  request_id: string;
  tenant_id: string | null;
  mode: string | null;
  data: unknown;
  error: { code: string; message: string; details: JsonMap } | null;
  meta: JsonMap;
};

export function normalizeGatewayResponse(
  result: PlatformRpcResult,
  fallback: {
    operationCode: string;
    requestId: string;
    routeTenantId: string | null;
  },
): GatewayEnvelope {
  const details = asObject(result?.details);
  const success = result?.success === true;
  const mode = asString(details.mode) || null;
  const tenantId = asString(details.tenant_id) || fallback.routeTenantId;
  const operationCode = asString(details.operation_code) || fallback.operationCode;
  const requestId = asString(details.request_id) || fallback.requestId;

  if (!success) {
    return {
      success: false,
      operation_code: operationCode,
      request_id: requestId,
      tenant_id: tenantId,
      mode,
      data: null,
      error: {
        code: asString(result?.code) || "GATEWAY_REQUEST_FAILED",
        message: asString(result?.message) || "Gateway request failed.",
        details,
      },
      meta: {},
    };
  }

  const { data, ...rest } = details;

  return {
    success: true,
    operation_code: operationCode,
    request_id: requestId,
    tenant_id: tenantId,
    mode,
    data: Object.prototype.hasOwnProperty.call(details, "data") ? data : details,
    error: null,
    meta: rest,
  };
}
