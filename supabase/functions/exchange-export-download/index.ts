import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  jsonResponse,
  logStructured,
  requireBearerToken,
} from "../_shared/http.ts";
import {
  asObject,
  parseExportDeliveryDescriptor,
  requirePlatformSuccess,
} from "../_shared_i06/platform.ts";
import { callPlatformRpc, createServiceRoleClient, createUserClient } from "../_shared/supabase.ts";

function normalizeDisposition(value: string | null): "inline" | "attachment" {
  return value?.toLowerCase() === "attachment" ? "attachment" : "inline";
}

function sanitizeFilename(value: string): string {
  const trimmed = value.trim();
  return trimmed.replace(/["\r\n]+/g, "_") || "export.bin";
}

Deno.serve(async (req: Request): Promise<Response> => {
  const requestId = createRequestId(req);
  const startedAt = Date.now();

  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    if (req.method !== "GET") throw new EdgeHttpError("Method not allowed.", 405, "METHOD_NOT_ALLOWED");

    const accessToken = requireBearerToken(req);
    const url = new URL(req.url);
    const exportJobId = url.searchParams.get("export_job_id")?.trim() || "";
    if (!exportJobId) throw new EdgeHttpError("export_job_id is required.", 400, "EXPORT_JOB_ID_REQUIRED");

    const disposition = normalizeDisposition(url.searchParams.get("disposition"));
    const expiresInSeconds = Math.max(60, Math.min(3600, Number(url.searchParams.get("expires_in_seconds") ?? "300") || 300));
    const userClient = createUserClient(accessToken);
    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData.user) {
      throw new EdgeHttpError("Authenticated user context is not available.", 401, "INVALID_JWT");
    }

    const serviceClient = createServiceRoleClient();
    const details = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_get_export_delivery_descriptor", {
        export_job_id: exportJobId,
        actor_user_id: userData.user.id,
      }),
      "EXPORT_DELIVERY_RESOLVE_FAILED",
      "Unable to resolve export delivery descriptor.",
    );
    const descriptor = parseExportDeliveryDescriptor(details);
    const documentAccess = descriptor.documentAccess;

    if (documentAccess.protectionMode === "signed_url") {
      const storageApi = serviceClient.storage.from(documentAccess.bucketName) as any;
      const { data: signedUrlData, error: signedUrlError } = await storageApi.createSignedUrl(
        documentAccess.storageObjectName,
        expiresInSeconds,
        disposition === "attachment" ? { download: sanitizeFilename(descriptor.fileName) } : undefined,
      );

      if (signedUrlError) {
        throw new EdgeHttpError("Unable to issue signed export URL.", 502, "SIGNED_URL_ISSUE_FAILED", { export_job_id: exportJobId });
      }

      const signedUrlInfo = asObject(signedUrlData);
      const signedUrl = typeof signedUrlInfo.signedUrl === "string" ? signedUrlInfo.signedUrl : "";
      if (!signedUrl) throw new EdgeHttpError("Signed export URL is missing.", 502, "SIGNED_URL_ISSUE_FAILED");

      logStructured("info", "exchange-export-download issued signed URL", {
        request_id: requestId,
        actor_user_id: userData.user.id,
        export_job_id: descriptor.exportJobId,
        duration_ms: Date.now() - startedAt,
      });

      return jsonResponse({
        success: true,
        request_id: requestId,
        export_job: {
          export_job_id: descriptor.exportJobId,
          tenant_id: descriptor.tenantId,
          contract_code: descriptor.contractCode,
          export_artifact_id: descriptor.exportArtifactId,
          artifact_status: descriptor.artifactStatus,
          file_name: descriptor.fileName,
          content_type: descriptor.contentType,
          retention_expires_at: descriptor.retentionExpiresAt,
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
    streamUrl.searchParams.set("document_id", documentAccess.documentId);
    streamUrl.searchParams.set("disposition", disposition);

    logStructured("info", "exchange-export-download issued stream descriptor", {
      request_id: requestId,
      actor_user_id: userData.user.id,
      export_job_id: descriptor.exportJobId,
      protection_mode: documentAccess.protectionMode,
      duration_ms: Date.now() - startedAt,
    });

    return jsonResponse({
      success: true,
      request_id: requestId,
      export_job: {
        export_job_id: descriptor.exportJobId,
        tenant_id: descriptor.tenantId,
        contract_code: descriptor.contractCode,
        export_artifact_id: descriptor.exportArtifactId,
        artifact_status: descriptor.artifactStatus,
        file_name: descriptor.fileName,
        content_type: descriptor.contentType,
        retention_expires_at: descriptor.retentionExpiresAt,
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
      : new EdgeHttpError(error instanceof Error ? error.message : "Unexpected error.", 500, "EXCHANGE_EXPORT_DOWNLOAD_FAILED");

    logStructured("error", "exchange-export-download failed", {
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
