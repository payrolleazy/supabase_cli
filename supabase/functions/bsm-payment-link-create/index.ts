import { assertTenantBillingOperator, resolveAuthorizedTenantId, resolveRequestActorContext } from "../_shared/auth.ts";
import { CORS_HEADERS, EdgeHttpError, asObject, asString, createRequestId, jsonResponse, logStructured, readJsonBody } from "../_shared/http.ts";
import { createRazorpayPaymentLink } from "../_shared/razorpay.ts";
import { callPlatformRpc, createServiceRoleClient } from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 16 * 1024;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  const requestId = createRequestId(req);
  const startedAt = Date.now();

  try {
    if (req.method !== "POST") return jsonResponse({ success: false, error: "Method not allowed.", error_code: "METHOD_NOT_ALLOWED" }, 405);

    const payload = asObject(await readJsonBody(req, MAX_BODY_BYTES));
    const actorContext = await resolveRequestActorContext(req);
    if (actorContext.kind === "actor") {
      const tenantId = await resolveAuthorizedTenantId(payload);
      await assertTenantBillingOperator(tenantId, actorContext.actorUserId);
      payload.tenant_id = tenantId;
    }

    const providerCode = (asString(payload.provider_code) || "razorpay").toLowerCase();
    if (providerCode !== "razorpay") {
      throw new EdgeHttpError(`Unsupported payment provider ${providerCode}.`, 409, "UNSUPPORTED_PROVIDER", { provider_code: providerCode });
    }

    const client = createServiceRoleClient();
    const rpcResult = await callPlatformRpc(client, "platform_initiate_checkout", payload);
    if (rpcResult.success !== true) {
      return jsonResponse({ success: false, error: rpcResult.message || "Payment order creation failed.", error_code: rpcResult.code || "PAYMENT_ORDER_CREATE_FAILED", details: rpcResult.details || {} }, 409);
    }

    const details = asObject(rpcResult.details);
    const paymentOrder = asObject(details.payment_order);
    const providerRequest = asObject(details.provider_request);
    const paymentOrderId = asString(paymentOrder.id);
    const amount = Number(providerRequest.amount);
    const currencyCode = asString(providerRequest.currency_code) || "INR";

    if (!paymentOrderId || !Number.isFinite(amount) || amount <= 0) {
      throw new EdgeHttpError("Payment order contract returned incomplete details.", 500, "PAYMENT_ORDER_CREATE_FAILED");
    }

    const context = asObject(providerRequest.context);
    const paymentLink = await createRazorpayPaymentLink({
      amount,
      currencyCode,
      internalOrderId: paymentOrderId,
      description: asString(payload.description) || `Commercial payment ${paymentOrderId}`,
      callbackUrl: asString(providerRequest.return_url),
      metadata: {
        platform_payment_order_id: paymentOrderId,
        platform_payment_order_external_id: paymentOrder.external_order_id,
        tenant_id: context.tenant_id,
        settlement_id: context.settlement_id,
        invoice_id: context.invoice_id,
        plan_code: context.plan_code,
      },
    });

    const attachResult = await callPlatformRpc(client, "platform_attach_payment_order", {
      payment_order_id: paymentOrderId,
      external_order_id: paymentLink.externalOrderId,
      status: "pending",
      checkout_url: paymentLink.checkoutUrl,
      expires_at: paymentLink.expiresAt,
      provider_payload: paymentLink.raw,
    });
    if (attachResult.success !== true) {
      return jsonResponse({ success: false, error: attachResult.message || "Unable to attach payment order.", error_code: attachResult.code || "PAYMENT_ORDER_ATTACH_FAILED", details: attachResult.details || {} }, 409);
    }

    return jsonResponse({
      success: true,
      request_id: requestId,
      payment_order_id: paymentOrderId,
      external_order_id: paymentLink.externalOrderId,
      checkout_url: paymentLink.checkoutUrl,
      expires_at: paymentLink.expiresAt,
    });
  } catch (error) {
    logStructured("error", "bsm_payment_link_create_failed", { request_id: requestId, duration_ms: Date.now() - startedAt, error: error instanceof Error ? error.message : String(error) });
    if (error instanceof EdgeHttpError) {
      return jsonResponse({ success: false, error: error.message, error_code: error.code, details: error.details }, error.status, error.headers);
    }
    return jsonResponse({ success: false, error: "Unable to create billing payment link.", error_code: "INTERNAL_ERROR" }, 500);
  }
});
