import { z } from "npm:zod@3.23.8";

import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  jsonResponse,
  logStructured,
  readJsonBody,
  requireBearerToken,
} from "../_shared_i05/http.ts";
import { requirePlatformSuccess } from "../_shared_i05/platform.ts";
import { callPlatformRpc, createServiceRoleClient, createUserClient } from "../_shared_i05/supabase.ts";

const MAX_BODY_BYTES = 16 * 1024;

const CompleteUploadSchema = z.object({
  upload_intent_id: z.string().uuid(),
  file_size_bytes: z.number().int().positive().max(100 * 1024 * 1024).optional(),
  checksum_sha256: z.string().regex(/^[A-Fa-f0-9]{64}$/).optional(),
  storage_metadata: z.record(z.string(), z.unknown()).default({}),
  document_metadata: z.record(z.string(), z.unknown()).default({}),
  expires_on: z.string().date().optional(),
}).strict();

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
    const body = CompleteUploadSchema.parse(await readJsonBody(req, MAX_BODY_BYTES));
    const userClient = createUserClient(accessToken);
    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData.user) {
      throw new EdgeHttpError("Authenticated user context is not available.", 401, "INVALID_JWT");
    }

    const serviceClient = createServiceRoleClient();
    const details = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_complete_document_upload", {
        upload_intent_id: body.upload_intent_id,
        uploaded_by_actor_user_id: userData.user.id,
        file_size_bytes: body.file_size_bytes ?? null,
        checksum_sha256: body.checksum_sha256 ?? null,
        storage_metadata: {
          ...body.storage_metadata,
          completed_via: "document-upload-complete",
          request_id: requestId,
        },
        document_metadata: body.document_metadata,
        expires_on: body.expires_on ?? null,
      }),
      "DOCUMENT_UPLOAD_COMPLETE_FAILED",
      "Unable to complete document upload.",
    );

    logStructured("info", "document-upload-complete completed", {
      request_id: requestId,
      actor_user_id: userData.user.id,
      tenant_id: typeof details.tenant_id === "string" ? details.tenant_id : null,
      document_id: typeof details.document_id === "string" ? details.document_id : null,
      duration_ms: Date.now() - startedAt,
    });

    return jsonResponse({
      success: true,
      request_id: requestId,
      document: details,
    });
  } catch (error) {
    const edgeError = error instanceof EdgeHttpError
      ? error
      : new EdgeHttpError(
        error instanceof Error ? error.message : "Unexpected error.",
        500,
        "DOCUMENT_UPLOAD_COMPLETE_FAILED",
      );

    logStructured("error", "document-upload-complete failed", {
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
