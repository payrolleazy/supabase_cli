import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  jsonResponse,
  logStructured,
} from "../_shared_i02/http.ts";
import {
  asObject,
  asString,
  issuePurchaseActivationToken,
  parseUuid,
  requirePlatformSuccess,
} from "../_shared_i02/platform.ts";
import {
  buildRazorpayWebhookRecordParams,
  verifyRazorpaySignature,
} from "../_shared_i02/razorpay.ts";
import {
  callPlatformRpc,
  createServiceRoleClient,
} from "../_shared_i02/supabase.ts";

const MAX_BODY_BYTES = 128 * 1024;

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

    const signature = req.headers.get("x-razorpay-signature")?.trim();
    if (!signature) {
      return jsonResponse({
        success: false,
        error: "Missing webhook signature.",
        error_code: "WEBHOOK_SIGNATURE_REQUIRED",
      }, 401);
    }

    const rawBody = await req.text();
    if (rawBody.length > MAX_BODY_BYTES) {
      throw new EdgeHttpError(
        "Webhook payload is too large.",
        413,
        "BODY_TOO_LARGE",
      );
    }

    const isValid = await verifyRazorpaySignature(rawBody, signature);
    if (!isValid) {
      return jsonResponse({
        success: false,
        error: "Invalid webhook signature.",
        error_code: "WEBHOOK_SIGNATURE_INVALID",
      }, 401);
    }

    let parsedBody: unknown = {};
    try {
      parsedBody = rawBody ? JSON.parse(rawBody) : {};
    } catch {
      throw new EdgeHttpError(
        "Webhook payload must be valid JSON.",
        400,
        "INVALID_JSON",
      );
    }

    const payload = asObject(parsedBody);
    const providerEventIdHeader = req.headers.get("x-razorpay-event-id")?.trim() || null;
    const webhookRecord = buildRazorpayWebhookRecordParams(payload, providerEventIdHeader);

    if (!webhookRecord.checkoutId && !webhookRecord.externalCheckoutId) {
      throw new EdgeHttpError(
        "Webhook payload did not include a usable checkout reference.",
        400,
        "CHECKOUT_REFERENCE_REQUIRED",
      );
    }

    const serviceClient = createServiceRoleClient();
    const recordDetails = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_record_public_checkout_event", {
        checkout_id: webhookRecord.checkoutId,
        external_checkout_id: webhookRecord.externalCheckoutId,
        provider_code: "razorpay",
        provider_event_id: webhookRecord.providerEventId,
        event_type: webhookRecord.eventType,
        resolved_status: webhookRecord.resolvedStatus,
        payload: webhookRecord.payload,
      }),
      409,
      "CHECKOUT_EVENT_RECORD_FAILED",
      "Unable to record the checkout provider event.",
    );

    const provisionRequestId = parseUuid(recordDetails.provision_request_id) || webhookRecord.provisionRequestId;
    const shouldIssueActivation =
      recordDetails.idempotent_replay !== true &&
      asString(recordDetails.provisioning_status)?.toLowerCase() === "activation_ready" &&
      Boolean(provisionRequestId);

    const activation = shouldIssueActivation && provisionRequestId
      ? await issuePurchaseActivationToken(serviceClient, provisionRequestId, webhookRecord.providerEventId)
      : null;

    logStructured("info", "public_client_purchase_webhook_processed", {
      request_id: requestId,
      provider_event_id: webhookRecord.providerEventId,
      checkout_id: recordDetails.checkout_id ?? webhookRecord.checkoutId,
      provision_request_id: provisionRequestId,
      duration_ms: Date.now() - startedAt,
    });

    return jsonResponse({
      success: true,
      provider_event_id: webhookRecord.providerEventId,
      checkout_id: recordDetails.checkout_id ?? webhookRecord.checkoutId,
      provision_request_id: provisionRequestId,
      provisioning_status: recordDetails.provisioning_status ?? null,
      next_action: recordDetails.next_action ?? null,
      idempotent_replay: recordDetails.idempotent_replay === true,
      activation: activation
        ? {
          purchase_activation_token: activation.token,
          purchase_activation_token_id: activation.tokenId,
          purchase_activation_expires_at: activation.expiresAt,
        }
        : null,
    });
  } catch (error) {
    logStructured("error", "public_client_purchase_webhook_failed", {
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

    return jsonResponse({
      success: false,
      error: "Unable to process the payment webhook.",
      error_code: "INTERNAL_ERROR",
    }, 500);
  }
});

