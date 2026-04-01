import { EdgeHttpError, asString } from "./http.ts";
import { createAuthedClient, createServiceRoleClient } from "./supabase.ts";

const BILLING_OPERATOR_ROLES = ["tenant_owner_admin"] as const;

export type RequestActorContext =
  | { kind: "service_role"; actorUserId: null }
  | { kind: "actor"; actorUserId: string };

function getAuthorizationHeader(req: Request): string {
  const authHeader = req.headers.get("authorization")?.trim();
  if (!authHeader) {
    throw new EdgeHttpError("Missing Authorization header.", 401, "AUTHORIZATION_REQUIRED");
  }
  return authHeader;
}

function getBearerToken(authHeader: string): string {
  return authHeader.replace(/^Bearer\s+/i, "").trim();
}

export async function resolveRequestActorContext(req: Request): Promise<RequestActorContext> {
  const authHeader = getAuthorizationHeader(req);
  const token = getBearerToken(authHeader);
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() || "";
  if (serviceRoleKey && token === serviceRoleKey) {
    return { kind: "service_role", actorUserId: null };
  }

  const authedClient = createAuthedClient(authHeader);
  const { data, error } = await authedClient.auth.getUser();
  if (error || !data.user?.id) {
    throw new EdgeHttpError("User not authenticated.", 401, "AUTHENTICATION_REQUIRED");
  }

  return { kind: "actor", actorUserId: data.user.id };
}

export async function resolveAuthorizedTenantId(payload: Record<string, unknown>): Promise<string> {
  const explicitTenantId = asString(payload.tenant_id);
  if (explicitTenantId) {
    return explicitTenantId;
  }

  const tenantCode = asString(payload.tenant_code);
  if (!tenantCode) {
    throw new EdgeHttpError(
      "tenant_id or tenant_code is required for authenticated payment-link creation.",
      400,
      "TENANT_REFERENCE_REQUIRED",
    );
  }

  const serviceClient = createServiceRoleClient();
  const { data, error } = await serviceClient
    .from("platform_tenant")
    .select("tenant_id")
    .eq("tenant_code", tenantCode)
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new EdgeHttpError("Unable to resolve tenant reference.", 500, "TENANT_RESOLUTION_FAILED");
  }
  if (!data?.tenant_id) {
    throw new EdgeHttpError("Tenant reference was not found.", 404, "TENANT_NOT_FOUND", {
      tenant_code: tenantCode,
    });
  }

  return String(data.tenant_id);
}

export async function assertTenantBillingOperator(tenantId: string, actorUserId: string): Promise<void> {
  const serviceClient = createServiceRoleClient();
  const { data, error } = await serviceClient
    .from("platform_actor_tenant_membership")
    .select("tenant_id")
    .eq("tenant_id", tenantId)
    .eq("actor_user_id", actorUserId)
    .eq("membership_status", "active")
    .eq("routing_status", "enabled")
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new EdgeHttpError("Unable to validate tenant membership.", 500, "ACTOR_AUTHORIZATION_CHECK_FAILED");
  }
  if (!data) {
    throw new EdgeHttpError("Actor is not an active tenant member.", 403, "TENANT_MEMBERSHIP_REQUIRED", {
      tenant_id: tenantId,
    });
  }

  const { data: grantData, error: grantError } = await serviceClient
    .from("platform_actor_role_grant")
    .select("role_code")
    .eq("tenant_id", tenantId)
    .eq("actor_user_id", actorUserId)
    .eq("grant_status", "active")
    .in("role_code", [...BILLING_OPERATOR_ROLES])
    .limit(1)
    .maybeSingle();

  if (grantError) {
    throw new EdgeHttpError("Unable to validate tenant billing operator role.", 500, "ACTOR_AUTHORIZATION_CHECK_FAILED");
  }
  if (!grantData) {
    throw new EdgeHttpError("Actor is not allowed to create billing payment links for this tenant.", 403, "BILLING_OPERATOR_REQUIRED", {
      tenant_id: tenantId,
      allowed_roles: [...BILLING_OPERATOR_ROLES],
    });
  }
}
