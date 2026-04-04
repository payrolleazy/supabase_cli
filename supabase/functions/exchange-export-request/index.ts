import { z } from "npm:zod@3.23.8";

import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  jsonResponse,
  logStructured,
  readJsonBody,
  requireBearerToken,
} from "../_shared/http.ts";
import { requirePlatformSuccess } from "../_shared_i06/platform.ts";
import { callPlatformRpc, createServiceRoleClient, createUserClient } from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 64 * 1024;

const ExportRequestSchema = z.object({
  tenant_id: z.string().uuid().optional(),
  tenant_code: z.string().min(1).max(100).transform((value) => value.trim().toLowerCase()).optional(),
  contract_code: z.string().min(1).max(120).transform((value) => value.trim().toLowerCase()),
  request_payload: z.record(z.string(), z.unknown()).default({}),
  idempotency_key: z.string().min(1).max(200).optional(),
  deduplication_key: z.string().min(1).max(200).optional(),
  metadata: z.record(z.string(), z.unknown()).default({}),
}).strict().refine((value) => Boolean(value.tenant_id || value.tenant_code), {
  message: "tenant_id or tenant_code is required",
  path: ["tenant_id"],
});

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
    const body = ExportRequestSchema.parse(await readJsonBody(req, MAX_BODY_BYTES));
    const userClient = createUserClient(accessToken);
    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData.user) {
      throw new EdgeHttpError("Authenticated user context is not available.", 401, "INVALID_JWT");
    }

    const serviceClient = createServiceRoleClient();
    const details = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_request_export_job", {
        tenant_id: body.tenant_id ?? null,
        tenant_code: body.tenant_code ?? null,
        contract_code: body.contract_code,
        actor_user_id: userData.user.id,
        request_payload: body.request_payload,
        idempotency_key: body.idempotency_key ?? null,
        deduplication_key: body.deduplication_key ?? null,
        metadata: {
          ...body.metadata,
          requested_via: "exchange-export-request",
          request_id: requestId,
        },
      }),
      "EXPORT_REQUEST_FAILED",
      "Unable to request export job.",
    );

    logStructured("info", "exchange-export-request completed", {
      request_id: requestId,
      actor_user_id: userData.user.id,
      contract_code: body.contract_code,
      export_job_id: details.export_job_id ?? null,
      duration_ms: Date.now() - startedAt,
    });

    return jsonResponse({
      success: true,
      request_id: requestId,
      export_job: details,
    });
  } catch (error) {
    const edgeError = error instanceof EdgeHttpError
      ? error
      : new EdgeHttpError(
        error instanceof Error ? error.message : "Unexpected error.",
        500,
        "EXCHANGE_EXPORT_REQUEST_FAILED",
      );

    logStructured("error", "exchange-export-request failed", {
      request_id: requestId,
      duration_ms: Date.now() - startedAt,
      error_code: edgeError.code,
      error_message: edgeError.message,
      details: edgeError.details,
    });

    return jsonResponse({
      success: false,
      request_id: requestId,
      error: {
        code: edgeError.code,
        message: edgeError.message,
        details: edgeError.details ?? {},
      },
    }, edgeError.status, edgeError.headers);
  }
});
