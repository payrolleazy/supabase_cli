import { z } from "zod";

import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  getClientMetadata,
  jsonResponse,
  logStructured,
  readJsonBody,
} from "../_shared_i02/http.ts";
import {
  acceptPurchaseActivation,
  asObject,
  asString,
  credentialSetupRoute,
  getOwnerBootstrapContext,
  getProvisionState,
  getRequestKey,
  type ProvisionState,
  requirePlatformSuccess,
} from "../_shared_i02/platform.ts";
import {
  callPlatformRpc,
  createServiceRoleClient,
  type JsonMap,
} from "../_shared_i02/supabase.ts";

const MAX_BODY_BYTES = 12 * 1024;

const CaptureIntentSchema = z.object({
  action: z.literal("capture_intent"),
  request_id: z.string().min(1).max(200).optional(),
  request_idempotency_key: z.string().min(1).max(200).optional(),
  company_name: z.string().min(2).max(200).transform((value) => value.trim()),
  legal_name: z.string().max(200).transform((value) => value.trim()).optional(),
  primary_contact_name: z.string().min(2).max(200).transform((value) => value.trim()),
  primary_work_email: z.string().email().transform((value) => value.trim().toLowerCase()),
  primary_mobile: z.string().max(30).transform((value) => value.trim()).optional(),
  phone_number: z.string().max(30).transform((value) => value.trim()).optional(),
  selected_plan_code: z.string().min(1).max(100).transform((value) => value.trim().toLowerCase()),
  currency_code: z.string().max(10).transform((value) => value.trim().toUpperCase()).optional(),
  country_code: z.string().max(20).transform((value) => value.trim().toUpperCase()).optional(),
  country_or_region: z.string().max(50).transform((value) => value.trim()).optional(),
  timezone: z.string().max(100).transform((value) => value.trim()).optional(),
  estimated_employee_count: z.coerce.number().int().nonnegative().optional(),
  modules_of_interest: z.array(z.string().min(1).max(100).transform((value) => value.trim().toLowerCase())).max(50).optional(),
});

const ActivateAfterPurchaseSchema = z.object({
  action: z.literal("activate_after_purchase"),
  provision_request_id: z.string().uuid().optional(),
  request_key: z.string().min(1).max(200).transform((value) => value.trim().toLowerCase()).optional(),
  purchase_activation_token: z.string().min(24).max(256),
}).refine((value) => Boolean(value.provision_request_id || value.request_key), {
  message: "provision_request_id or request_key is required",
  path: ["provision_request_id"],
});

type CaptureIntentBody = z.infer<typeof CaptureIntentSchema>;
type ActivateAfterPurchaseBody = z.infer<typeof ActivateAfterPurchaseSchema>;

function buildReferenceParams(payload: { provision_request_id?: string; request_key?: string }): JsonMap {
  const params: JsonMap = {};
  if (payload.provision_request_id) params.provision_request_id = payload.provision_request_id;
  if (payload.request_key) params.request_key = payload.request_key;
  return params;
}

function laterActivationState(state: ProvisionState): boolean {
  return [
    "credential_setup_required",
    "identity_created",
    "tenant_created",
    "owner_role_bound",
    "commercial_seeded",
    "setup_seeded",
    "ready_for_signin",
  ].includes(state.provisioning_status);
}

async function handleCaptureIntent(
  req: Request,
  body: unknown,
  requestId: string,
): Promise<Response> {
  const payload = CaptureIntentSchema.parse(body);
  const requestKey = getRequestKey(asObject(body), requestId);
  const metadata = getClientMetadata(req);
  const serviceClient = createServiceRoleClient();

  const details = requirePlatformSuccess(
    await callPlatformRpc(serviceClient, "platform_capture_client_provision_intent", {
      request_key: requestKey,
      company_name: payload.company_name,
      legal_name: payload.legal_name,
      primary_contact_name: payload.primary_contact_name,
      primary_work_email: payload.primary_work_email,
      primary_mobile: payload.primary_mobile || payload.phone_number,
      selected_plan_code: payload.selected_plan_code,
      currency_code: payload.currency_code,
      country_code: payload.country_code || payload.country_or_region,
      timezone: payload.timezone,
      request_source: "public",
      source_ip: metadata.sourceIp,
      user_agent: metadata.userAgent,
      metadata: {
        capture_channel: "client-owner-provision",
        estimated_employee_count: payload.estimated_employee_count ?? null,
        modules_of_interest: payload.modules_of_interest ?? [],
      },
    }),
    409,
    "PROVISION_INTENT_CAPTURE_FAILED",
    "Unable to capture the client provisioning intent.",
  );

  return jsonResponse({
    success: true,
    action: "capture_intent",
    provision: {
      provision_request_id: details.provision_request_id,
      request_key: details.request_key,
      company_name: payload.company_name,
      primary_work_email: payload.primary_work_email,
      selected_plan_code: payload.selected_plan_code,
      provisioning_status: details.provisioning_status,
      next_action: details.next_action,
    },
    purchase: {
      endpoint: "/functions/v1/public-client-purchase",
      method: "POST",
      action: "initiate_checkout",
    },
    metadata: {
      idempotent_replay: details.idempotent_replay === true,
    },
  }, details.idempotent_replay === true ? 200 : 202);
}

async function handleActivateAfterPurchase(
  payload: ActivateAfterPurchaseBody,
): Promise<Response> {
  const serviceClient = createServiceRoleClient();
  const refParams = buildReferenceParams(payload);
  const state = await getProvisionState(serviceClient, refParams);

  if (state.provisioning_status === "ready_for_signin") {
    return jsonResponse({
      success: true,
      action: "activate_after_purchase",
      provision: {
        provision_request_id: state.provision_request_id,
        provisioning_status: state.provisioning_status,
        next_action: state.next_action,
        tenant_id: state.tenant_id,
      },
      credential_setup: {
        route: credentialSetupRoute(),
        token_available: false,
      },
      metadata: {
        idempotent_replay: true,
      },
    });
  }

  if (laterActivationState(state)) {
    return jsonResponse({
      success: true,
      action: "activate_after_purchase",
      provision: {
        provision_request_id: state.provision_request_id,
        provisioning_status: state.provisioning_status,
        next_action: state.next_action,
        tenant_id: state.tenant_id,
      },
      credential_setup: {
        route: credentialSetupRoute(),
        token_available: false,
      },
      metadata: {
        idempotent_replay: true,
        resume_required: true,
      },
    });
  }

  const bootstrapContext = await getOwnerBootstrapContext(
    serviceClient,
    payload.purchase_activation_token,
    "purchase_activation",
  );

  if (bootstrapContext.provision_request_id !== state.provision_request_id) {
    throw new EdgeHttpError(
      "purchase_activation_token does not match the provision request.",
      409,
      "TOKEN_CONTEXT_MISMATCH",
      {
        token_provision_request_id: bootstrapContext.provision_request_id,
        request_provision_request_id: state.provision_request_id,
      },
    );
  }

  const accepted = await acceptPurchaseActivation(serviceClient, payload.purchase_activation_token);
  const latestState = await getProvisionState(serviceClient, { provision_request_id: accepted.provisionRequestId });

  return jsonResponse({
    success: true,
    action: "activate_after_purchase",
    provision: {
      provision_request_id: latestState.provision_request_id,
      provisioning_status: latestState.provisioning_status,
      next_action: latestState.next_action,
    },
    credential_setup: {
      token: accepted.credentialSetupToken,
      token_id: accepted.credentialSetupTokenId,
      expires_at: accepted.credentialSetupExpiresAt,
      route: credentialSetupRoute(),
      endpoint: "/functions/v1/client-owner-credential-bootstrap",
    },
    metadata: {
      idempotent_replay: false,
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  const requestId = createRequestId(req);
  const startedAt = Date.now();

  try {
    if (req.method !== "POST") {
      return jsonResponse({
        success: false,
        error: "Method not allowed. Use POST.",
        error_code: "METHOD_NOT_ALLOWED",
      }, 405);
    }

    const body = await readJsonBody(req, MAX_BODY_BYTES);
    const payload = asObject(body);
    const action = asString(payload.action);

    if (action === "capture_intent") {
      return await handleCaptureIntent(req, body, requestId);
    }

    if (action === "activate_after_purchase") {
      return await handleActivateAfterPurchase(ActivateAfterPurchaseSchema.parse(body));
    }

    return jsonResponse({
      success: false,
      error: "Unsupported action.",
      error_code: "ACTION_NOT_SUPPORTED",
    }, 400);
  } catch (error) {
    logStructured("error", "client_owner_provision_failed", {
      request_id: requestId,
      duration_ms: Date.now() - startedAt,
      error: error instanceof Error ? error.message : String(error),
    });

    if (error instanceof EdgeHttpError) {
      return jsonResponse({
        success: false,
        error: error.message,
        error_code: error.code,
        details: error.details,
      }, error.status, error.headers);
    }

    if (error instanceof z.ZodError) {
      return jsonResponse({
        success: false,
        error: "Validation failed",
        error_code: "VALIDATION_ERROR",
        details: error.flatten().fieldErrors,
      }, 400);
    }

    return jsonResponse({
      success: false,
      error: "Unable to process the owner provisioning request.",
      error_code: "INTERNAL_ERROR",
    }, 500);
  }
});

