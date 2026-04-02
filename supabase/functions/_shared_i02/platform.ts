import { sha256Hex } from "./crypto.ts";
import { EdgeHttpError } from "./http.ts";
import {
  callPlatformRpc,
  type JsonMap,
  type PlatformRpcResult,
  type SupabaseClient,
} from "./supabase.ts";

export type ProvisionState = {
  provision_request_id: string;
  request_key: string;
  company_name: string;
  legal_name: string | null;
  primary_contact_name: string | null;
  primary_work_email: string;
  primary_mobile: string | null;
  selected_plan_code: string | null;
  currency_code: string | null;
  provisioning_status: string;
  next_action: string | null;
  tenant_id: string | null;
  tenant_code: string | null;
  owner_actor_user_id: string | null;
  latest_checkout_id: string | null;
  latest_checkout_provider_code: string | null;
  latest_external_checkout_id: string | null;
  latest_checkout_status: string | null;
  latest_checkout_amount: number | null;
  latest_checkout_currency_code: string | null;
  latest_checkout_url: string | null;
  latest_checkout_expires_at: string | null;
};

export type PlanCatalogRow = {
  id: string;
  plan_code: string;
  plan_name: string;
  status: string;
  billing_cadence: string;
  currency_code: string;
  metadata: JsonMap;
};

export type PlanQuote = {
  amount: number;
  currency_code: string;
  provider_code: string;
  is_free: boolean;
};

export type OwnerBootstrapContext = {
  token_id: string;
  token_purpose: string;
  expires_at: string;
  provision_request_id: string;
  company_name: string;
  primary_work_email: string;
  selected_plan_code: string | null;
  provisioning_status: string;
  tenant_id: string | null;
  owner_actor_user_id: string | null;
};

export type BootstrapTokenState = {
  token_id: string;
  token_purpose: string;
  token_status: string;
  provision_request_id: string;
};

type PricebookEntry = {
  amount: number;
  currency_code?: string;
  provider_code?: string;
};

export function asObject(value: unknown): JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as JsonMap)
    : {};
}

export function asString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

export function asNumber(value: unknown): number | null {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function asBoolean(value: unknown): boolean {
  return value === true || value === "true" || value === 1 || value === "1";
}

export function parseUuid(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(trimmed)
    ? trimmed
    : null;
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

export function getRequestKey(body: JsonMap, fallbackRequestId: string): string {
  const value = asString(body.request_id) || asString(body.request_idempotency_key) || fallbackRequestId;
  if (!value) {
    throw new EdgeHttpError("request_id is required", 400, "INVALID_REQUEST");
  }
  return value.toLowerCase();
}

export function getManagedPublicUrl(envName: string, fieldName: string, bodyValue: string | null): string {
  const configured = Deno.env.get(envName)?.trim();
  if (!configured) {
    throw new EdgeHttpError(`${envName} is not configured`, 500, "PUBLIC_URL_NOT_CONFIGURED", {
      env_name: envName,
    });
  }

  if (bodyValue && bodyValue !== configured) {
    throw new EdgeHttpError(`${fieldName} override is not allowed`, 400, "URL_OVERRIDE_NOT_ALLOWED", {
      field_name: fieldName,
    });
  }

  return configured;
}

function getPricebook(): Record<string, PricebookEntry> {
  const raw = Deno.env.get("PUBLIC_PLAN_PRICEBOOK_JSON")?.trim();
  if (!raw) {
    throw new EdgeHttpError(
      "PUBLIC_PLAN_PRICEBOOK_JSON is not configured",
      500,
      "PUBLIC_PRICEBOOK_UNAVAILABLE",
    );
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new EdgeHttpError(
      "PUBLIC_PLAN_PRICEBOOK_JSON must be valid JSON",
      500,
      "PUBLIC_PRICEBOOK_UNAVAILABLE",
    );
  }

  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new EdgeHttpError(
      "PUBLIC_PLAN_PRICEBOOK_JSON must be an object",
      500,
      "PUBLIC_PRICEBOOK_UNAVAILABLE",
    );
  }

  return parsed as Record<string, PricebookEntry>;
}

export async function getProvisionState(
  client: SupabaseClient,
  params: JsonMap,
): Promise<ProvisionState> {
  const details = requirePlatformSuccess(
    await callPlatformRpc(client, "platform_get_client_provision_state", params),
    404,
    "PROVISION_REQUEST_NOT_FOUND",
    "Provision request was not found.",
  );

  return {
    provision_request_id: asString(details.provision_request_id) || "",
    request_key: asString(details.request_key) || "",
    company_name: asString(details.company_name) || "",
    legal_name: asString(details.legal_name),
    primary_contact_name: asString(details.primary_contact_name),
    primary_work_email: asString(details.primary_work_email) || "",
    primary_mobile: asString(details.primary_mobile),
    selected_plan_code: asString(details.selected_plan_code),
    currency_code: asString(details.currency_code),
    provisioning_status: (asString(details.provisioning_status) || "").toLowerCase(),
    next_action: asString(details.next_action),
    tenant_id: parseUuid(details.tenant_id),
    tenant_code: asString(details.tenant_code),
    owner_actor_user_id: parseUuid(details.owner_actor_user_id),
    latest_checkout_id: parseUuid(details.latest_checkout_id),
    latest_checkout_provider_code: asString(details.latest_checkout_provider_code),
    latest_external_checkout_id: asString(details.latest_external_checkout_id),
    latest_checkout_status: asString(details.latest_checkout_status),
    latest_checkout_amount: asNumber(details.latest_checkout_amount),
    latest_checkout_currency_code: asString(details.latest_checkout_currency_code),
    latest_checkout_url: asString(details.latest_checkout_url),
    latest_checkout_expires_at: asString(details.latest_checkout_expires_at),
  };
}

export function assertProvisioningPurchaseEligible(state: ProvisionState): void {
  const allowed = new Set([
    "awaiting_purchase",
    "checkout_created",
    "payment_pending",
    "payment_failed",
    "payment_cancelled",
    "payment_expired",
    "activation_ready",
  ]);

  if (!allowed.has(state.provisioning_status)) {
    throw new EdgeHttpError(
      `Provisioning status ${state.provisioning_status} is not purchase eligible.`,
      409,
      "PROVISIONING_NOT_PURCHASE_ELIGIBLE",
      { provisioning_status: state.provisioning_status },
    );
  }
}

export async function getPlanCatalogRow(
  client: SupabaseClient,
  selectedPlanCode: string,
): Promise<PlanCatalogRow> {
  const { data, error } = await client
    .from("platform_plan_catalog")
    .select("id, plan_code, plan_name, status, billing_cadence, currency_code, metadata")
    .eq("plan_code", selectedPlanCode)
    .eq("status", "active")
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new EdgeHttpError(error.message, 500, "PLAN_LOOKUP_FAILED");
  }

  if (!data) {
    throw new EdgeHttpError(
      `Plan ${selectedPlanCode} is not active.`,
      404,
      "PLAN_CODE_UNRECOGNIZED",
      { plan_code: selectedPlanCode },
    );
  }

  return {
    id: String(data.id),
    plan_code: String(data.plan_code),
    plan_name: String(data.plan_name),
    status: String(data.status),
    billing_cadence: String(data.billing_cadence),
    currency_code: String(data.currency_code),
    metadata: asObject(data.metadata),
  };
}

export function resolvePublicPlanQuote(plan: PlanCatalogRow): PlanQuote {
  const metadata = asObject(plan.metadata);
  const metadataBaseAmount = asNumber(metadata.base_amount);
  const metadataFreeFlag = asBoolean(metadata.is_free_plan);

  if ((metadataBaseAmount !== null && metadataBaseAmount === 0) || metadataFreeFlag) {
    return {
      amount: 0,
      currency_code: (plan.currency_code || "INR").toUpperCase(),
      provider_code: "internal_free",
      is_free: true,
    };
  }

  const entry = getPricebook()[plan.plan_code];
  if (!entry) {
    throw new EdgeHttpError(
      `Public pricebook entry missing for plan ${plan.plan_code}.`,
      409,
      "PUBLIC_PRICEBOOK_UNAVAILABLE",
      { plan_code: plan.plan_code },
    );
  }

  const amount = Number(entry.amount);
  if (!Number.isFinite(amount) || amount < 0) {
    throw new EdgeHttpError(
      `Resolved public price for plan ${plan.plan_code} is invalid.`,
      409,
      "PLAN_PRICING_UNRESOLVED",
      { plan_code: plan.plan_code },
    );
  }

  return {
    amount: Number(amount.toFixed(2)),
    currency_code: (entry.currency_code || plan.currency_code || "INR").toUpperCase(),
    provider_code: (entry.provider_code || (amount === 0 ? "internal_free" : "razorpay")).toLowerCase(),
    is_free: amount === 0,
  };
}

export function purchaseActivationTokenTtlMinutes(): number {
  const ttlSeconds = Number(Deno.env.get("PUBLIC_PURCHASE_TOKEN_TTL_SECONDS") ?? "900");
  const safeSeconds = Number.isFinite(ttlSeconds) && ttlSeconds > 0 ? Math.trunc(ttlSeconds) : 900;
  return Math.max(1, Math.ceil(safeSeconds / 60));
}

export function credentialSetupRoute(): string {
  return Deno.env.get("CLIENT_OWNER_CREDENTIAL_SETUP_ROUTE")?.trim() || "/signup/activate";
}

export function autoConfirmOwnerEmail(): boolean {
  const raw = (Deno.env.get("CLIENT_OWNER_AUTO_CONFIRM_EMAIL") ?? "true").trim().toLowerCase();
  return raw === "true" || raw === "1" || raw === "yes";
}

export async function issuePurchaseActivationToken(
  client: SupabaseClient,
  provisionRequestId: string,
  requestId: string,
): Promise<{ tokenId: string; token: string; expiresAt: string }> {
  const details = requirePlatformSuccess(
    await callPlatformRpc(client, "platform_issue_owner_bootstrap_token", {
      provision_request_id: provisionRequestId,
      token_purpose: "purchase_activation",
      expires_in_minutes: purchaseActivationTokenTtlMinutes(),
      metadata: {
        issued_by: "i02_public_purchase",
        request_id: requestId,
      },
    }),
    409,
    "ACTIVATION_TOKEN_ISSUE_FAILED",
    "Unable to issue purchase activation token.",
  );

  const tokenId = asString(details.token_id);
  const token = asString(details.token);
  const expiresAt = asString(details.expires_at);
  if (!tokenId || !token || !expiresAt) {
    throw new EdgeHttpError(
      "Activation token contract returned incomplete details.",
      500,
      "ACTIVATION_TOKEN_ISSUE_FAILED",
    );
  }

  return {
    tokenId,
    token,
    expiresAt,
  };
}

export async function getOwnerBootstrapContext(
  client: SupabaseClient,
  rawToken: string,
  tokenPurpose: "purchase_activation" | "credential_setup",
): Promise<OwnerBootstrapContext> {
  const details = requirePlatformSuccess(
    await callPlatformRpc(client, "platform_get_owner_bootstrap_context", {
      token: rawToken,
      token_purpose: tokenPurpose,
    }),
    409,
    "BOOTSTRAP_CONTEXT_UNAVAILABLE",
    "Bootstrap context is not available.",
  );

  const provisionRequestId = parseUuid(details.provision_request_id);
  const tokenId = parseUuid(details.token_id);
  const expiresAt = asString(details.expires_at);
  const companyName = asString(details.company_name);
  const primaryWorkEmail = asString(details.primary_work_email);
  const provisioningStatus = asString(details.provisioning_status);

  if (!provisionRequestId || !tokenId || !expiresAt || !companyName || !primaryWorkEmail || !provisioningStatus) {
    throw new EdgeHttpError(
      "Bootstrap context contract returned incomplete details.",
      500,
      "BOOTSTRAP_CONTEXT_UNAVAILABLE",
    );
  }

  return {
    token_id: tokenId,
    token_purpose: asString(details.token_purpose) || tokenPurpose,
    expires_at: expiresAt,
    provision_request_id: provisionRequestId,
    company_name: companyName,
    primary_work_email: primaryWorkEmail,
    selected_plan_code: asString(details.selected_plan_code),
    provisioning_status: provisioningStatus.toLowerCase(),
    tenant_id: parseUuid(details.tenant_id),
    owner_actor_user_id: parseUuid(details.owner_actor_user_id),
  };
}

export async function lookupBootstrapTokenState(
  client: SupabaseClient,
  rawToken: string,
): Promise<BootstrapTokenState | null> {
  const tokenHash = await sha256Hex(rawToken);
  const { data, error } = await client
    .from("platform_owner_bootstrap_token")
    .select("token_id, token_purpose, token_status, provision_request_id")
    .eq("token_hash", tokenHash)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new EdgeHttpError(error.message, 500, "BOOTSTRAP_TOKEN_LOOKUP_FAILED");
  }

  if (!data) {
    return null;
  }

  const tokenId = parseUuid(data.token_id);
  const provisionRequestId = parseUuid(data.provision_request_id);
  const tokenPurpose = asString(data.token_purpose);
  const tokenStatus = asString(data.token_status);
  if (!tokenId || !provisionRequestId || !tokenPurpose || !tokenStatus) {
    throw new EdgeHttpError(
      "Bootstrap token lookup returned incomplete details.",
      500,
      "BOOTSTRAP_TOKEN_LOOKUP_FAILED",
    );
  }

  return {
    token_id: tokenId,
    token_purpose: tokenPurpose,
    token_status: tokenStatus,
    provision_request_id: provisionRequestId,
  };
}

export async function acceptPurchaseActivation(
  client: SupabaseClient,
  rawToken: string,
): Promise<{
  provisionRequestId: string;
  credentialSetupToken: string;
  credentialSetupTokenId: string;
  credentialSetupExpiresAt: string;
}> {
  const details = requirePlatformSuccess(
    await callPlatformRpc(client, "platform_accept_purchase_activation", {
      token: rawToken,
    }),
    409,
    "PURCHASE_ACTIVATION_FAILED",
    "Unable to activate the completed purchase.",
  );

  const provisionRequestId = parseUuid(details.provision_request_id);
  const credentialSetupToken = asString(details.credential_setup_token);
  const credentialSetupTokenId = parseUuid(details.credential_setup_token_id);
  const credentialSetupExpiresAt = asString(details.credential_setup_expires_at);

  if (!provisionRequestId || !credentialSetupToken || !credentialSetupTokenId || !credentialSetupExpiresAt) {
    throw new EdgeHttpError(
      "Purchase activation returned incomplete credential setup details.",
      500,
      "PURCHASE_ACTIVATION_FAILED",
    );
  }

  return {
    provisionRequestId,
    credentialSetupToken,
    credentialSetupTokenId,
    credentialSetupExpiresAt,
  };
}
