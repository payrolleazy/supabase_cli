export const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-razorpay-signature, x-razorpay-event-id",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export class EdgeHttpError extends Error {
  status: number;
  code: string;
  details: Record<string, unknown> | undefined;
  headers: HeadersInit | undefined;

  constructor(message: string, status: number, code: string, details?: Record<string, unknown>, headers?: HeadersInit) {
    super(message);
    this.name = "EdgeHttpError";
    this.status = status;
    this.code = code;
    this.details = details;
    this.headers = headers;
  }
}

export function jsonResponse(payload: unknown, status = 200, headers?: HeadersInit): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      ...headers,
    },
  });
}

export async function readJsonBody(req: Request, maxBodyBytes: number): Promise<unknown> {
  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > maxBodyBytes) {
    throw new EdgeHttpError("Request body is too large.", 413, "BODY_TOO_LARGE");
  }

  const rawBody = await req.text();
  if (rawBody.length > maxBodyBytes) {
    throw new EdgeHttpError("Request body is too large.", 413, "BODY_TOO_LARGE");
  }

  try {
    return rawBody.trim() ? JSON.parse(rawBody) : {};
  } catch {
    throw new EdgeHttpError("Request body must be valid JSON.", 400, "INVALID_JSON");
  }
}

export function createRequestId(req: Request): string {
  return req.headers.get("x-request-id")?.trim() || crypto.randomUUID();
}

function firstForwardedValue(value: string | null): string | null {
  if (!value) return null;
  return value.split(",")[0]?.trim() || null;
}

export function getClientMetadata(req: Request): { sourceIp: string; userAgent: string } {
  return {
    sourceIp:
      firstForwardedValue(req.headers.get("cf-connecting-ip")) ||
      firstForwardedValue(req.headers.get("x-real-ip")) ||
      firstForwardedValue(req.headers.get("x-forwarded-for")) ||
      "unknown",
    userAgent: req.headers.get("user-agent") || "unknown",
  };
}

export function logStructured(level: "info" | "warning" | "error", message: string, context: Record<string, unknown> = {}): void {
  console.log(JSON.stringify({ level, message, timestamp: new Date().toISOString(), ...context }));
}

export function asObject(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

export function asString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

export function requireServiceRoleBearer(req: Request): void {
  const authHeader = req.headers.get("authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  const expected = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() || "";
  if (!expected || token !== expected) {
    throw new EdgeHttpError("Forbidden", 403, "FORBIDDEN");
  }
}
