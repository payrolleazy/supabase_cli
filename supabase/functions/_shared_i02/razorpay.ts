import { EdgeHttpError } from "./http.ts";

type JsonMap = Record<string, unknown>;

type PaymentLinkArgs = {
  amount: number;
  currencyCode: string;
  internalCheckoutId: string;
  provisionRequestId: string;
  requestKey: string;
  companyName: string;
  customerName: string | null;
  customerEmail: string;
  customerMobile: string | null;
  planCode: string;
  planName: string;
  returnUrl: string;
  cancelUrl: string;
  expiresAt?: string | null;
};

export type PaymentLinkResult = {
  externalCheckoutId: string;
  checkoutUrl: string;
  expiresAt: string | null;
  raw: JsonMap;
};

export type WebhookRecordParams = {
  checkoutId: string | null;
  externalCheckoutId: string | null;
  providerEventId: string;
  eventType: string;
  resolvedStatus: string;
  payload: JsonMap;
  provisionRequestId: string | null;
};

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) {
    throw new EdgeHttpError(`Missing required environment variable: ${name}`, 500, "PAYMENT_PROVIDER_NOT_CONFIGURED", {
      env_name: name,
    });
  }
  return value;
}

function asObject(value: unknown): JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as JsonMap)
    : {};
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function getNestedValue(value: unknown, path: string[]): unknown {
  let current: unknown = value;
  for (const segment of path) {
    if (typeof current !== "object" || current === null || Array.isArray(current)) {
      return null;
    }
    current = (current as Record<string, unknown>)[segment];
  }
  return current;
}

function getNestedString(value: unknown, path: string[]): string | null {
  return asString(getNestedValue(value, path));
}

function hex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;

  let mismatch = 0;
  for (let index = 0; index < left.length; index += 1) {
    mismatch |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }

  return mismatch === 0;
}

function basicAuthHeader(keyId: string, keySecret: string): string {
  return `Basic ${btoa(`${keyId}:${keySecret}`)}`;
}

function toUnixSeconds(isoTimestamp: string | null | undefined): number | undefined {
  if (!isoTimestamp) return undefined;
  const milliseconds = Date.parse(isoTimestamp);
  if (!Number.isFinite(milliseconds)) return undefined;
  return Math.floor(milliseconds / 1000);
}

function normalizeRazorpayEventType(eventType: string | null): string {
  return (eventType || "provider_event").trim().toLowerCase();
}

function resolveStatusFromEventType(eventType: string): string {
  switch (eventType) {
    case "payment_link.paid":
    case "payment.captured":
      return "paid";
    case "payment.failed":
      return "failed";
    case "payment_link.cancelled":
      return "cancelled";
    case "payment_link.expired":
      return "expired";
    default:
      return "pending";
  }
}

export async function createRazorpayPaymentLink(args: PaymentLinkArgs): Promise<PaymentLinkResult> {
  const keyId = requireEnv("RAZORPAY_KEY_ID");
  const keySecret = requireEnv("RAZORPAY_KEY_SECRET");

  const amountPaise = Math.round(args.amount * 100);
  if (!Number.isFinite(amountPaise) || amountPaise <= 0) {
    throw new EdgeHttpError(
      "Quoted payment amount must be greater than zero for Razorpay checkout.",
      409,
      "INVALID_CHECKOUT_AMOUNT",
      { amount: args.amount },
    );
  }

  const requestBody: JsonMap = {
    amount: amountPaise,
    currency: args.currencyCode,
    accept_partial: false,
    description: `${args.companyName} - ${args.planName}`,
    reference_id: args.internalCheckoutId,
    callback_url: args.returnUrl,
    callback_method: "get",
    notes: {
      platform_checkout_id: args.internalCheckoutId,
      provision_request_id: args.provisionRequestId,
      request_key: args.requestKey,
      plan_code: args.planCode,
      cancel_url: args.cancelUrl,
    },
    customer: {
      name: args.customerName || args.companyName,
      email: args.customerEmail,
      contact: args.customerMobile || undefined,
    },
  };

  const expireBy = toUnixSeconds(args.expiresAt);
  if (expireBy) {
    requestBody.expire_by = expireBy;
  }

  const response = await fetch("https://api.razorpay.com/v1/payment_links", {
    method: "POST",
    headers: {
      Authorization: basicAuthHeader(keyId, keySecret),
      "Content-Type": "application/json",
    },
    body: JSON.stringify(requestBody),
  });

  const rawPayload = await response.text();
  let parsedPayload: unknown = {};
  try {
    parsedPayload = rawPayload ? JSON.parse(rawPayload) : {};
  } catch {
    parsedPayload = { raw_payload: rawPayload };
  }

  if (!response.ok) {
    throw new EdgeHttpError(
      "Unable to create the payment checkout link.",
      502,
      "CHECKOUT_PROVIDER_ERROR",
      asObject(parsedPayload),
    );
  }

  const payload = asObject(parsedPayload);
  const externalCheckoutId = asString(payload.id);
  const checkoutUrl = asString(payload.short_url) || asString(payload.payment_link);
  if (!externalCheckoutId || !checkoutUrl) {
    throw new EdgeHttpError(
      "Razorpay checkout response was incomplete.",
      502,
      "CHECKOUT_PROVIDER_ERROR",
      payload,
    );
  }

  return {
    externalCheckoutId,
    checkoutUrl,
    expiresAt: asString(payload.expire_by)
      ? new Date(Number(payload.expire_by) * 1000).toISOString()
      : null,
    raw: payload,
  };
}

export async function verifyRazorpaySignature(rawBody: string, signature: string): Promise<boolean> {
  const webhookSecret = requireEnv("RAZORPAY_WEBHOOK_SECRET");
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(webhookSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const digest = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    new TextEncoder().encode(rawBody),
  );

  return timingSafeEqual(hex(digest), signature.trim().toLowerCase());
}

export function buildRazorpayWebhookRecordParams(
  payload: JsonMap,
  headerEventId: string | null,
): WebhookRecordParams {
  const eventType = normalizeRazorpayEventType(asString(payload.event));
  const notes = asObject(getNestedValue(payload, ["payload", "payment_link", "entity", "notes"]));
  const fallbackNotes = asObject(getNestedValue(payload, ["payload", "payment", "entity", "notes"]));
  const mergedNotes = { ...fallbackNotes, ...notes };

  const externalCheckoutId =
    getNestedString(payload, ["payload", "payment_link", "entity", "id"]) ||
    getNestedString(payload, ["payload", "payment", "entity", "order_id"]) ||
    asString(mergedNotes.platform_checkout_external_id);

  const providerEventId =
    headerEventId ||
    getNestedString(payload, ["payload", "payment", "entity", "id"]) ||
    getNestedString(payload, ["payload", "payment_link", "entity", "id"]) ||
    `${eventType}:${externalCheckoutId || "unknown"}`;

  return {
    checkoutId: asString(mergedNotes.platform_checkout_id),
    externalCheckoutId,
    providerEventId,
    eventType,
    resolvedStatus: resolveStatusFromEventType(eventType),
    payload,
    provisionRequestId: asString(mergedNotes.provision_request_id),
  };
}
