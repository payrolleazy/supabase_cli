import { z } from "npm:zod@3.23.8";

import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  getClientMetadata,
  jsonResponse,
  logStructured,
  readJsonBody,
} from "../_shared/http.ts";
import { normalizeGatewayResponse } from "../_shared/platform.ts";
import { callPlatformRpc, createUserClient, type JsonMap } from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 32 * 1024;

const GatewayRequestSchema = z.object({
  operation_code: z.string().min(1).max(160).transform((value) => value.trim().toLowerCase()),
  route_tenant_id: z.preprocess((value) => value === null ? undefined : value, z.string().uuid().optional()),
  payload: z.record(z.string(), z.unknown()).default({}),
  idempotency_key: z.preprocess(
    (value) => value === null ? undefined : typeof value === "string" ? value.trim() : value,
    z.string().min(1).max(200).optional(),
  ),
  request_metadata: z.record(z.string(), z.unknown()).default({}),
}).strict();

type GatewayRequestBody = z.infer<typeof GatewayRequestSchema>;

function requireBearerToken(req: Request): string {
  const header = req.headers.get("authorization")?.trim() || "";
  if (!header.toLowerCase().startsWith("bearer ")) {
    throw new EdgeHttpError("Authorization bearer token is required.", 401, "AUTH_REQUIRED");
  }

  const token = header.slice(7).trim();
  if (!token) {
    throw new EdgeHttpError("Authorization bearer token is required.", 401, "AUTH_REQUIRED");
  }

  return token;
}

function mapGatewayErrorStatus(code: string): number {
  switch (code) {
    case "AUTH_REQUIRED":
    case "INVALID_JWT":
    case "UNAUTHENTICATED":
      return 401;
    case "OPERATION_NOT_FOUND":
      return 404;
    case "INSUFFICIENT_ROLE":
    case "TENANT_ACCESS_BLOCKED":
    case "ACTOR_MEMBERSHIP_NOT_ACTIVE":
    case "ACTOR_PROFILE_INACTIVE":
    case "ACTOR_ACCESS_NOT_FOUND":
      return 403;
    case "IDEMPOTENCY_IN_PROGRESS":
      return 409;
    case "INVALID_PAYLOAD":
    case "INVALID_REQUEST_METADATA":
    case "PAYLOAD_REQUIRED_KEY_MISSING":
    case "PAYLOAD_KEY_NOT_ALLOWED":
    case "OPERATION_CODE_REQUIRED":
    case "TENANT_CONTEXT_REQUIRED":
      return 400;
    default:
      return 500;
  }
}

function buildRequestMetadata(body: GatewayRequestBody, req: Request, requestId: string, userId: string): JsonMap {
  const client = getClientMetadata(req);
  return {
    ...body.request_metadata,
    source: "application-gateway",
    request_id: requestId,
    actor_user_id: userId,
    source_ip: client.sourceIp,
    user_agent: client.userAgent,
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  const requestId = createRequestId(req);
  const startedAt = Date.now();

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    if (req.method !== "POST") {
      throw new EdgeHttpError("Method not allowed.", 405, "METHOD_NOT_ALLOWED");
    }

    const accessToken = requireBearerToken(req);
    const body = GatewayRequestSchema.parse(await readJsonBody(req, MAX_BODY_BYTES));
    const userClient = createUserClient(accessToken);
    const { data: userData, error: userError } = await userClient.auth.getUser(accessToken);

    if (userError || !userData.user) {
      throw new EdgeHttpError("Authenticated user context is not available.", 401, "INVALID_JWT");
    }

    const requestMetadata = buildRequestMetadata(body, req, requestId, userData.user.id);
    const rpcResult = await callPlatformRpc(userClient, "platform_execute_gateway_request", {
      operation_code: body.operation_code,
      tenant_id: body.route_tenant_id ?? null,
      payload: body.payload,
      idempotency_key: body.idempotency_key ?? null,
      request_metadata: requestMetadata,
      request_id: requestId,
    });

    const envelope = normalizeGatewayResponse(rpcResult, {
      operationCode: body.operation_code,
      requestId,
      routeTenantId: body.route_tenant_id ?? null,
    });

    logStructured(envelope.success ? "info" : "warning", "application-gateway completed", {
      request_id: requestId,
      operation_code: envelope.operation_code,
      tenant_id: envelope.tenant_id,
      mode: envelope.mode,
      success: envelope.success,
      duration_ms: Date.now() - startedAt,
      error_code: envelope.error?.code ?? null,
    });

    return jsonResponse(envelope, envelope.success ? 200 : mapGatewayErrorStatus(envelope.error?.code || ""));
  } catch (error) {
    const edgeError = error instanceof EdgeHttpError
      ? error
      : error instanceof z.ZodError
      ? new EdgeHttpError(
        "Request body validation failed.",
        400,
        "INVALID_REQUEST",
        { issues: error.issues },
      )
      : new EdgeHttpError(
        error instanceof Error ? error.message : "Unexpected error.",
        500,
        "APPLICATION_GATEWAY_FAILED",
      );

    logStructured("error", "application-gateway failed", {
      request_id: requestId,
      duration_ms: Date.now() - startedAt,
      error_code: edgeError.code,
      error_message: edgeError.message,
      details: edgeError.details,
    });

    return jsonResponse({
      success: false,
      operation_code: null,
      request_id: requestId,
      tenant_id: null,
      mode: null,
      data: null,
      error: {
        code: edgeError.code,
        message: edgeError.message,
        details: edgeError.details ?? {},
      },
      meta: {},
    }, edgeError.status, edgeError.headers);
  }
});
