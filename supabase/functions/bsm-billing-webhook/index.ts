import { CORS_HEADERS, EdgeHttpError, asObject, createRequestId, jsonResponse, logStructured } from "../_shared/http.ts";
import { buildRazorpayBillingWebhookRecordParams, verifyRazorpaySignature } from "../_shared/razorpay.ts";
import { callPlatformRpc, createServiceRoleClient } from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 128 * 1024;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  const requestId = createRequestId(req);
  const startedAt = Date.now();

  try {
    if (req.method !== "POST") return jsonResponse({ success: false, error: "Method not allowed.", error_code: "METHOD_NOT_ALLOWED" }, 405);

    const signature = req.headers.get("x-razorpay-signature")?.trim();
    if (!signature) return jsonResponse({ success: false, error: "Missing webhook signature.", error_code: "WEBHOOK_SIGNATURE_REQUIRED" }, 401);

    const rawBody = await req.text();
    if (rawBody.length > MAX_BODY_BYTES) throw new EdgeHttpError("Webhook payload is too large.", 413, "BODY_TOO_LARGE");

    const isValid = await verifyRazorpaySignature(rawBody, signature);
    if (!isValid) return jsonResponse({ success: false, error: "Invalid webhook signature.", error_code: "WEBHOOK_SIGNATURE_INVALID" }, 401);

    let parsed: unknown = {};
    try {
      parsed = rawBody ? JSON.parse(rawBody) : {};
    } catch {
      throw new EdgeHttpError("Webhook payload must be valid JSON.", 400, "INVALID_JSON");
    }

    const payload = asObject(parsed);
    const headerEventId = req.headers.get("x-razorpay-event-id")?.trim() || null;
    const webhookRecord = buildRazorpayBillingWebhookRecordParams(payload, headerEventId);
    if (!webhookRecord.paymentOrderId && !webhookRecord.externalOrderId) {
      throw new EdgeHttpError("Webhook payload did not include a usable payment order reference.", 400, "PAYMENT_ORDER_REFERENCE_REQUIRED");
    }

    const client = createServiceRoleClient();
    const result = await callPlatformRpc(client, "platform_record_payment_event", {
      provider_code: "razorpay",
      payment_order_id: webhookRecord.paymentOrderId,
      external_order_id: webhookRecord.externalOrderId,
      external_event_id: webhookRecord.providerEventId,
      external_payment_id: webhookRecord.externalPaymentId,
      event_type: webhookRecord.eventType,
      resolved_status: webhookRecord.resolvedStatus,
      raw_payload: webhookRecord.payload,
    });

    if (result.success !== true) {
      return jsonResponse({ success: false, error: result.message || "Unable to process billing webhook.", error_code: result.code || "BILLING_WEBHOOK_FAILED", details: result.details || {} }, 409);
    }

    logStructured("info", "bsm_billing_webhook_processed", { request_id: requestId, provider_event_id: webhookRecord.providerEventId, payment_order_id: webhookRecord.paymentOrderId, duration_ms: Date.now() - startedAt });
    return jsonResponse({ success: true, request_id: requestId, provider_event_id: webhookRecord.providerEventId, details: result.details || {} });
  } catch (error) {
    logStructured("error", "bsm_billing_webhook_failed", { request_id: requestId, duration_ms: Date.now() - startedAt, error: error instanceof Error ? error.message : String(error) });
    if (error instanceof EdgeHttpError) {
      return jsonResponse({ success: false, error: error.message, error_code: error.code, details: error.details }, error.status, error.headers);
    }
    return jsonResponse({ success: false, error: "Unable to process billing webhook.", error_code: "INTERNAL_ERROR" }, 500);
  }
});
