import { z } from "zod";

import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  jsonResponse,
  logStructured,
  readJsonBody,
} from "../_shared_i02/http.ts";
import {
  asObject,
  asString,
  assertProvisioningPurchaseEligible,
  getManagedPublicUrl,
  getPlanCatalogRow,
  getProvisionState,
  issuePurchaseActivationToken,
  parseUuid,
  requirePlatformSuccess,
  resolvePublicPlanQuote,
  type ProvisionState,
} from "../_shared_i02/platform.ts";
import { createRazorpayPaymentLink } from "../_shared_i02/razorpay.ts";
import {
  callPlatformRpc,
  createServiceRoleClient,
  type JsonMap,
} from "../_shared_i02/supabase.ts";

const MAX_BODY_BYTES = 12 * 1024;

const InitiateCheckoutSchema = z.object({
  action: z.literal("initiate_checkout"),
  provision_request_id: z.string().uuid().optional(),
  request_key: z.string().min(1).max(200).transform((value) => value.trim().toLowerCase()).optional(),
  selected_plan_code: z.string().min(1).max(100).transform((value) => value.trim().toLowerCase()).optional(),
  return_url: z.string().url().optional(),
  cancel_url: z.string().url().optional(),
}).refine((value) => Boolean(value.provision_request_id || value.request_key), {
  message: "provision_request_id or request_key is required",
  path: ["provision_request_id"],
});

const ResolveCheckoutSchema = z.object({
  action: z.literal("resolve_checkout"),
  provision_request_id: z.string().uuid().optional(),
  request_key: z.string().min(1).max(200).transform((value) => value.trim().toLowerCase()).optional(),
  checkout_id: z.string().uuid().optional(),
}).refine((value) => Boolean(value.provision_request_id || value.request_key || value.checkout_id), {
  message: "provision_request_id, request_key, or checkout_id is required",
  path: ["provision_request_id"],
});

type InitiateCheckoutBody = z.infer<typeof InitiateCheckoutSchema>;
type ResolveCheckoutBody = z.infer<typeof ResolveCheckoutSchema>;

function buildReferenceParams(payload: {
  provision_request_id?: string;
  request_key?: string;
  checkout_id?: string;
}): JsonMap {
  const params: JsonMap = {};
  if (payload.provision_request_id) params.provision_request_id = payload.provision_request_id;
  if (payload.request_key) params.request_key = payload.request_key;
  if (payload.checkout_id) params.checkout_id = payload.checkout_id;
  return params;
}

function buildSuccessResponse(
  action: "initiate_checkout" | "resolve_checkout",
  state: ProvisionState,
  managedUrls: { returnUrl?: string; cancelUrl?: string } = {},
  activation?: { tokenId: string; token: string; expiresAt: string } | null,
  metadata: JsonMap = {},
): Response {
  return jsonResponse({
    success: true,
    action,
    provision: {
      provision_request_id: state.provision_request_id,
      request_key: state.request_key,
      company_name: state.company_name,
      selected_plan_code: state.selected_plan_code,
      provisioning_status: state.provisioning_status,
      next_action: state.next_action,
      tenant_id: state.tenant_id,
    },
    checkout: {
      checkout_id: state.latest_checkout_id,
      provider_code: state.latest_checkout_provider_code,
      external_checkout_id: state.latest_external_checkout_id,
      checkout_status: state.latest_checkout_status,
      amount: state.latest_checkout_amount,
      currency_code: state.latest_checkout_currency_code,
      checkout_url: state.latest_checkout_url,
      expires_at: state.latest_checkout_expires_at,
      return_url: managedUrls.returnUrl ?? null,
      cancel_url: managedUrls.cancelUrl ?? null,
    },
    activation: activation
      ? {
        purchase_activation_token: activation.token,
        purchase_activation_token_id: activation.tokenId,
        purchase_activation_expires_at: activation.expiresAt,
        activation_endpoint: "/functions/v1/client-owner-provision",
      }
      : null,
    metadata,
  });
}

async function handleInitiateCheckout(
  payload: InitiateCheckoutBody,
  requestId: string,
): Promise<Response> {
  const serviceClient = createServiceRoleClient();
  const returnUrl = getManagedPublicUrl("PUBLIC_PURCHASE_RETURN_URL", "return_url", payload.return_url ?? null);
  const cancelUrl = getManagedPublicUrl("PUBLIC_PURCHASE_CANCEL_URL", "cancel_url", payload.cancel_url ?? null);
  const refParams = buildReferenceParams(payload);

  let state = await getProvisionState(serviceClient, refParams);
  if (payload.selected_plan_code && state.selected_plan_code && payload.selected_plan_code !== state.selected_plan_code) {
    throw new EdgeHttpError(
      "selected_plan_code does not match the provision request.",
      409,
      "PLAN_SELECTION_MISMATCH",
      {
        selected_plan_code: payload.selected_plan_code,
        provision_plan_code: state.selected_plan_code,
      },
    );
  }

  assertProvisioningPurchaseEligible(state);

  if (!state.selected_plan_code) {
    throw new EdgeHttpError(
      "Provision request is missing selected_plan_code.",
      409,
      "PLAN_SELECTION_MISSING",
    );
  }

  if (state.provisioning_status === "activation_ready" || state.latest_checkout_status === "paid") {
    const activation = await issuePurchaseActivationToken(serviceClient, state.provision_request_id, requestId);
    state = await getProvisionState(serviceClient, { provision_request_id: state.provision_request_id });
    return buildSuccessResponse(
      "initiate_checkout",
      state,
      { returnUrl, cancelUrl },
      activation,
      { idempotent_replay: true, next_step: "purchase_activation" },
    );
  }

  const plan = await getPlanCatalogRow(serviceClient, state.selected_plan_code);
  const quote = resolvePublicPlanQuote(plan);
  const checkoutDetails = requirePlatformSuccess(
    await callPlatformRpc(serviceClient, "platform_create_or_resume_public_checkout", {
      ...refParams,
      provider_code: quote.provider_code,
      quoted_amount: quote.amount,
      metadata: {
        source: "public-client-purchase",
        request_id: requestId,
        managed_return_url: returnUrl,
        managed_cancel_url: cancelUrl,
      },
    }),
    409,
    "CHECKOUT_CREATE_FAILED",
    "Unable to create the public checkout.",
  );

  const checkoutId = parseUuid(checkoutDetails.checkout_id);
  if (!checkoutId) {
    throw new EdgeHttpError(
      "Checkout contract returned incomplete details.",
      500,
      "CHECKOUT_CREATE_FAILED",
    );
  }

  if (quote.is_free || asString(checkoutDetails.checkout_status)?.toLowerCase() === "paid") {
    const activation = await issuePurchaseActivationToken(serviceClient, state.provision_request_id, requestId);
    state = await getProvisionState(serviceClient, { provision_request_id: state.provision_request_id });
    return buildSuccessResponse(
      "initiate_checkout",
      state,
      { returnUrl, cancelUrl },
      activation,
      {
        idempotent_replay: checkoutDetails.idempotent_replay === true,
        next_step: "purchase_activation",
      },
    );
  }

  if (quote.provider_code !== "razorpay") {
    throw new EdgeHttpError(
      `Unsupported public checkout provider ${quote.provider_code}.`,
      409,
      "UNSUPPORTED_PUBLIC_PROVIDER",
      { provider_code: quote.provider_code },
    );
  }

  const shouldCreateProviderLink = !(
    checkoutDetails.idempotent_replay === true &&
    state.latest_external_checkout_id &&
    state.latest_checkout_url
  );

  if (shouldCreateProviderLink) {
    const paymentLink = await createRazorpayPaymentLink({
      amount: quote.amount,
      currencyCode: quote.currency_code,
      internalCheckoutId: checkoutId,
      provisionRequestId: state.provision_request_id,
      requestKey: state.request_key,
      companyName: state.company_name,
      customerName: state.primary_contact_name,
      customerEmail: state.primary_work_email,
      customerMobile: state.primary_mobile,
      planCode: plan.plan_code,
      planName: plan.plan_name,
      returnUrl,
      cancelUrl,
      expiresAt: state.latest_checkout_expires_at,
    });

    requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_attach_public_checkout", {
        checkout_id: checkoutId,
        external_checkout_id: paymentLink.externalCheckoutId,
        checkout_url: paymentLink.checkoutUrl,
        expires_at: paymentLink.expiresAt,
        metadata: {
          provider_code: "razorpay",
          provider_payload: paymentLink.raw,
          managed_return_url: returnUrl,
          managed_cancel_url: cancelUrl,
        },
      }),
      409,
      "CHECKOUT_ATTACH_FAILED",
      "Unable to attach provider checkout details.",
    );
  }

  state = await getProvisionState(serviceClient, { provision_request_id: state.provision_request_id });
  return buildSuccessResponse(
    "initiate_checkout",
    state,
    { returnUrl, cancelUrl },
    null,
    {
      idempotent_replay: checkoutDetails.idempotent_replay === true,
      next_step: state.next_action || "await_payment",
    },
  );
}

async function handleResolveCheckout(
  payload: ResolveCheckoutBody,
  requestId: string,
): Promise<Response> {
  const serviceClient = createServiceRoleClient();
  const refParams = buildReferenceParams(payload);

  requirePlatformSuccess(
    await callPlatformRpc(serviceClient, "platform_resolve_public_checkout", refParams),
    409,
    "CHECKOUT_RESOLVE_FAILED",
    "Unable to resolve the public checkout.",
  );

  const state = await getProvisionState(serviceClient, refParams);
  const activation = state.provisioning_status === "activation_ready"
    ? await issuePurchaseActivationToken(serviceClient, state.provision_request_id, requestId)
    : null;

  return buildSuccessResponse(
    "resolve_checkout",
    state,
    {},
    activation,
    {
      next_step: activation ? "purchase_activation" : state.next_action,
    },
  );
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
    if (action === "initiate_checkout") {
      return await handleInitiateCheckout(InitiateCheckoutSchema.parse(body), requestId);
    }

    if (action === "resolve_checkout") {
      return await handleResolveCheckout(ResolveCheckoutSchema.parse(body), requestId);
    }

    return jsonResponse({
      success: false,
      error: "Unsupported action.",
      error_code: "ACTION_NOT_SUPPORTED",
    }, 400);
  } catch (error) {
    logStructured("error", "public_client_purchase_failed", {
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
      error: "Unable to process the public checkout.",
      error_code: "INTERNAL_ERROR",
    }, 500);
  }
});

