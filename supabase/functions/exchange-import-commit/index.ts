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

const MAX_BODY_BYTES = 16 * 1024;

const CommitSchema = z.object({
  import_session_id: z.string().uuid(),
  metadata: z.record(z.string(), z.unknown()).default({}),
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
    const body = CommitSchema.parse(await readJsonBody(req, MAX_BODY_BYTES));
    const userClient = createUserClient(accessToken);
    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData.user) {
      throw new EdgeHttpError("Authenticated user context is not available.", 401, "INVALID_JWT");
    }

    const serviceClient = createServiceRoleClient();
    const details = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_commit_import_session", {
        import_session_id: body.import_session_id,
        actor_user_id: userData.user.id,
        metadata: {
          ...body.metadata,
          committed_via: "exchange-import-commit",
          request_id: requestId,
        },
      }),
      "IMPORT_COMMIT_FAILED",
      "Unable to queue import commit.",
    );

    logStructured("info", "exchange-import-commit completed", {
      request_id: requestId,
      actor_user_id: userData.user.id,
      import_session_id: body.import_session_id,
      import_run_id: details.import_run_id ?? null,
      duration_ms: Date.now() - startedAt,
    });

    return jsonResponse({
      success: true,
      request_id: requestId,
      commit: details,
    });
  } catch (error) {
    const edgeError = error instanceof EdgeHttpError
      ? error
      : new EdgeHttpError(
        error instanceof Error ? error.message : "Unexpected error.",
        500,
        "EXCHANGE_IMPORT_COMMIT_FAILED",
      );

    logStructured("error", "exchange-import-commit failed", {
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
