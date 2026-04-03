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
import {
  asObject,
  parseDocumentAccessDescriptor,
  requirePlatformSuccess,
} from "../_shared_i05/platform.ts";
import { callPlatformRpc, createServiceRoleClient, createUserClient } from "../_shared_i05/supabase.ts";

const MAX_BODY_BYTES = 8 * 1024;

const DocumentAccessSchema = z.object({
  document_id: z.string().uuid(),
  expires_in_seconds: z.number().int().min(60).max(3600).optional(),
  disposition: z.enum(["inline", "attachment"]).optional(),
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
    const body = DocumentAccessSchema.parse(await readJsonBody(req, MAX_BODY_BYTES));
    const userClient = createUserClient(accessToken);
    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData.user) {
      throw new EdgeHttpError("Authenticated user context is not available.", 401, "INVALID_JWT");
    }

    const serviceClient = createServiceRoleClient();
    const details = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_get_document_access_descriptor", {
        document_id: body.document_id,
        actor_user_id: userData.user.id,
      }),
      "DOCUMENT_ACCESS_RESOLVE_FAILED",
      "Unable to resolve document access.",
    );
    const descriptor = parseDocumentAccessDescriptor(details);
    const disposition = body.disposition ?? "inline";

    if (descriptor.protectionMode === "signed_url") {
      const expiresInSeconds = body.expires_in_seconds ?? 300;
      const storageApi = serviceClient.storage.from(descriptor.bucketName) as any;
      const { data: signedUrlData, error: signedUrlError } = await storageApi.createSignedUrl(
        descriptor.storageObjectName,
        expiresInSeconds,
        disposition === "attachment" ? { download: descriptor.originalFileName } : undefined,
      );

      if (signedUrlError) {
        throw new EdgeHttpError(
          "Unable to issue signed document URL.",
          502,
          "SIGNED_URL_ISSUE_FAILED",
          { document_id: descriptor.documentId },
        );
      }

      const signedUrlInfo = asObject(signedUrlData);
      const signedUrl = typeof signedUrlInfo.signedUrl === "string" ? signedUrlInfo.signedUrl : "";
      if (!signedUrl) {
        throw new EdgeHttpError("Signed document URL is missing.", 502, "SIGNED_URL_ISSUE_FAILED");
      }

      logStructured("info", "document-access issued signed URL", {
        request_id: requestId,
        actor_user_id: userData.user.id,
        document_id: descriptor.documentId,
        duration_ms: Date.now() - startedAt,
      });

      return jsonResponse({
        success: true,
        request_id: requestId,
        document: {
          document_id: descriptor.documentId,
          tenant_id: descriptor.tenantId,
          document_class_code: descriptor.documentClassCode,
          content_type: descriptor.contentType,
          original_file_name: descriptor.originalFileName,
          protection_mode: descriptor.protectionMode,
          access_reason: descriptor.accessReason,
        },
        access: {
          delivery_mode: "signed_url",
          expires_in_seconds: expiresInSeconds,
          signed_url: signedUrl,
        },
      });
    }

    const publicBaseUrl = new URL(Deno.env.get("SUPABASE_URL")?.trim() || req.url);
    const streamUrl = new URL("/functions/v1/document-stream", publicBaseUrl);
    streamUrl.searchParams.set("document_id", descriptor.documentId);
    streamUrl.searchParams.set("disposition", disposition);

    logStructured("info", "document-access issued stream descriptor", {
      request_id: requestId,
      actor_user_id: userData.user.id,
      document_id: descriptor.documentId,
      protection_mode: descriptor.protectionMode,
      duration_ms: Date.now() - startedAt,
    });

    return jsonResponse({
      success: true,
      request_id: requestId,
      document: {
        document_id: descriptor.documentId,
        tenant_id: descriptor.tenantId,
        document_class_code: descriptor.documentClassCode,
        content_type: descriptor.contentType,
        original_file_name: descriptor.originalFileName,
        protection_mode: descriptor.protectionMode,
        access_reason: descriptor.accessReason,
      },
      access: {
        delivery_mode: "edge_stream",
        stream_url: streamUrl.toString(),
        disposition,
      },
    });
  } catch (error) {
    const edgeError = error instanceof EdgeHttpError
      ? error
      : new EdgeHttpError(
        error instanceof Error ? error.message : "Unexpected error.",
        500,
        "DOCUMENT_ACCESS_RESOLVE_FAILED",
      );

    logStructured("error", "document-access failed", {
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
