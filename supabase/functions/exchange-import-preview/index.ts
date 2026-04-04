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

const MAX_BODY_BYTES = 1024 * 1024;

const PreviewSchema = z.object({
  import_session_id: z.string().uuid(),
  staged_rows: z.array(z.record(z.string(), z.unknown())).min(1),
}).strict();

Deno.serve(async (req: Request): Promise<Response> => {
  const requestId = createRequestId(req);
  const startedAt = Date.now();

  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    if (req.method !== "POST") throw new EdgeHttpError("Method not allowed.", 405, "METHOD_NOT_ALLOWED");

    const accessToken = requireBearerToken(req);
    const body = PreviewSchema.parse(await readJsonBody(req, MAX_BODY_BYTES));
    const userClient = createUserClient(accessToken);
    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData.user) {
      throw new EdgeHttpError("Authenticated user context is not available.", 401, "INVALID_JWT");
    }

    const serviceClient = createServiceRoleClient();
    const details = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_preview_import_session", {
        import_session_id: body.import_session_id,
        actor_user_id: userData.user.id,
        staged_rows: body.staged_rows,
      }),
      "IMPORT_PREVIEW_FAILED",
      "Unable to preview import session.",
    );

    logStructured("info", "exchange-import-preview completed", {
      request_id: requestId,
      actor_user_id: userData.user.id,
      import_session_id: body.import_session_id,
      total_rows: details.total_rows ?? null,
      duration_ms: Date.now() - startedAt,
    });

    return jsonResponse({ success: true, request_id: requestId, preview: details });
  } catch (error) {
    const edgeError = error instanceof EdgeHttpError
      ? error
      : new EdgeHttpError(error instanceof Error ? error.message : "Unexpected error.", 500, "EXCHANGE_IMPORT_PREVIEW_FAILED");

    logStructured("error", "exchange-import-preview failed", {
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
