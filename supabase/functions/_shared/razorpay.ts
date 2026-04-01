type JsonMap = Record<string, unknown>;

type PaymentLinkArgs = {
  amount: number;
  currencyCode: string;
  internalOrderId: string;
  description: string;
  callbackUrl?: string | null;
  callbackMethod?: "get" | "post";
  metadata?: JsonMap;
};

export type PaymentLinkResult = {
  externalOrderId: string;
  checkoutUrl: string;
  expiresAt: string | null;
  raw: JsonMap;
};

export type WebhookRecordParams = {
  paymentOrderId: string | null;
  externalOrderId: string | null;
  providerEventId: string;
  externalPaymentId: string | null;
  eventType: string;
  resolvedStatus: string;
  payload: JsonMap;
};

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function asObject(value: unknown): JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as JsonMap) : {};
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function getNestedValue(value: unknown, path: string[]): unknown {
  let current: unknown = value;
  for (const segment of path) {
    if (typeof current !== "object" || current === null || Array.isArray(current)) return null;
    current = (current as Record<string, unknown>)[segment];
  }
  return current;
}

function getNestedString(value: unknown, path: string[]): string | null {
  return asString(getNestedValue(value, path));
}

function basicAuthHeader(keyId: string, keySecret: string): string {
  return `Basic ${btoa(`${keyId}:${keySecret}`)}`;
}

function toUnixSeconds(isoTimestamp: string | null | undefined): number | undefined {
  if (!isoTimestamp) return undefined;
  const parsed = Date.parse(isoTimestamp);
  return Number.isFinite(parsed) ? Math.floor(parsed / 1000) : undefined;
}

function hex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer)).map((value) => value.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let mismatch = 0;
  for (let i = 0; i < left.length; i += 1) mismatch |= left.charCodeAt(i) ^ right.charCodeAt(i);
  return mismatch === 0;
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

  const body: JsonMap = {
    amount: amountPaise,
    currency: args.currencyCode,
    accept_partial: false,
    description: args.description,
    reference_id: args.internalOrderId,
    callback_method: args.callbackMethod || "get",
    notes: args.metadata || {},
  };

  if (args.callbackUrl) body.callback_url = args.callbackUrl;
  const expireBy = toUnixSeconds(asString(args.metadata?.expires_at));
  if (expireBy) body.expire_by = expireBy;

  const response = await fetch("https://api.razorpay.com/v1/payment_links", {
    method: "POST",
    headers: {
      Authorization: basicAuthHeader(keyId, keySecret),
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  let parsed: unknown = {};
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch {
    parsed = { raw_payload: text };
  }
  const payload = asObject(parsed);
  if (!response.ok) throw new Error(`Razorpay payment link creation failed: ${JSON.stringify(payload)}`);

  const externalOrderId = asString(payload.id);
  const checkoutUrl = asString(payload.short_url) || asString(payload.payment_link);
  if (!externalOrderId || !checkoutUrl) throw new Error("Razorpay payment link response was incomplete.");

  return {
    externalOrderId,
    checkoutUrl,
    expiresAt: asString(payload.expire_by) ? new Date(Number(payload.expire_by) * 1000).toISOString() : null,
    raw: payload,
  };
}

export async function verifyRazorpaySignature(rawBody: string, signature: string): Promise<boolean> {
  const secret = requireEnv("RAZORPAY_WEBHOOK_SECRET");
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(rawBody));
  return timingSafeEqual(hex(digest), signature.trim().toLowerCase());
}

export function buildRazorpayBillingWebhookRecordParams(payload: JsonMap, headerEventId: string | null): WebhookRecordParams {
  const eventType = (asString(payload.event) || "provider_event").toLowerCase();
  const linkNotes = asObject(getNestedValue(payload, ["payload", "payment_link", "entity", "notes"]));
  const paymentNotes = asObject(getNestedValue(payload, ["payload", "payment", "entity", "notes"]));
  const mergedNotes = { ...paymentNotes, ...linkNotes };
  const externalOrderId =
    getNestedString(payload, ["payload", "payment_link", "entity", "id"]) ||
    getNestedString(payload, ["payload", "payment", "entity", "order_id"]) ||
    asString(mergedNotes.platform_payment_order_external_id);
  const externalPaymentId = getNestedString(payload, ["payload", "payment", "entity", "id"]);
  const providerEventId = headerEventId || externalPaymentId || externalOrderId || `${eventType}:unknown`;

  return {
    paymentOrderId: asString(mergedNotes.platform_payment_order_id),
    externalOrderId,
    providerEventId,
    externalPaymentId,
    eventType,
    resolvedStatus: resolveStatusFromEventType(eventType),
    payload,
  };
}
