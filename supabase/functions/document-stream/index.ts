import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  jsonResponse,
  logStructured,
  requireBearerToken,
} from "../_shared_i05/http.ts";
import { parseDocumentAccessDescriptor, requirePlatformSuccess } from "../_shared_i05/platform.ts";
import { callPlatformRpc, createServiceRoleClient, createUserClient } from "../_shared_i05/supabase.ts";

function normalizeDisposition(value: string | null): "inline" | "attachment" {
  return value?.toLowerCase() === "attachment" ? "attachment" : "inline";
}

function sanitizeFilename(value: string): string {
  const trimmed = value.trim();
  return trimmed.replace(/["\r\n]+/g, "_") || "document.bin";
}

Deno.serve(async (req: Request): Promise<Response> => {
  const requestId = createRequestId(req);
  const startedAt = Date.now();

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    if (req.method !== "GET") {
      throw new EdgeHttpError("Method not allowed.", 405, "METHOD_NOT_ALLOWED");
    }

    const accessToken = requireBearerToken(req);
    const url = new URL(req.url);
    const documentId = url.searchParams.get("document_id")?.trim() || "";
    if (!documentId) {
      throw new EdgeHttpError("document_id is required.", 400, "DOCUMENT_ID_REQUIRED");
    }

    const disposition = normalizeDisposition(url.searchParams.get("disposition"));
    const userClient = createUserClient(accessToken);
    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData.user) {
      throw new EdgeHttpError("Authenticated user context is not available.", 401, "INVALID_JWT");
    }

    const serviceClient = createServiceRoleClient();
    const details = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_get_document_access_descriptor", {
        document_id: documentId,
        actor_user_id: userData.user.id,
      }),
      "DOCUMENT_ACCESS_RESOLVE_FAILED",
      "Unable to resolve document access.",
    );
    const descriptor = parseDocumentAccessDescriptor(details);

    if (!["edge_stream", "encrypted_edge_stream"].includes(descriptor.protectionMode)) {
      throw new EdgeHttpError(
        "Document protection mode does not support edge streaming.",
        409,
        "STREAM_NOT_ALLOWED",
        { protection_mode: descriptor.protectionMode },
      );
    }

    const { data: blob, error: downloadError } = await serviceClient.storage
      .from(descriptor.bucketName)
      .download(descriptor.storageObjectName);

    if (downloadError || !blob) {
      throw new EdgeHttpError(
        "Document bytes could not be retrieved.",
        404,
        "DOCUMENT_BYTES_NOT_FOUND",
        { document_id: descriptor.documentId },
      );
    }

    const headers = new Headers(CORS_HEADERS);
    headers.set("Cache-Control", "private, no-store");
    headers.set("Content-Type", blob.type || descriptor.contentType || "application/octet-stream");
    headers.set(
      "Content-Disposition",
      `${disposition}; filename=\"${sanitizeFilename(descriptor.originalFileName)}\"`,
    );
    headers.set("X-I05-Protection-Mode", descriptor.protectionMode);

    logStructured("info", "document-stream completed", {
      request_id: requestId,
      actor_user_id: userData.user.id,
      document_id: descriptor.documentId,
      protection_mode: descriptor.protectionMode,
      duration_ms: Date.now() - startedAt,
    });

    return new Response(blob.stream(), {
      status: 200,
      headers,
    });
  } catch (error) {
    const edgeError = error instanceof EdgeHttpError
      ? error
      : new EdgeHttpError(
        error instanceof Error ? error.message : "Unexpected error.",
        500,
        "DOCUMENT_STREAM_FAILED",
      );

    logStructured("error", "document-stream failed", {
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
