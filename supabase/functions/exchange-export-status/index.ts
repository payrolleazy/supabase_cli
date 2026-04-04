import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  jsonResponse,
  logStructured,
  requireBearerToken,
} from "../_shared/http.ts";
import { requirePlatformSuccess } from "../_shared_i06/platform.ts";
import { createServiceRoleClient, createUserClient } from "../_shared/supabase.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  const requestId = createRequestId(req);
  const startedAt = Date.now();

  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    if (req.method !== "GET") throw new EdgeHttpError("Method not allowed.", 405, "METHOD_NOT_ALLOWED");

    const accessToken = requireBearerToken(req);
    const exportJobId = new URL(req.url).searchParams.get("export_job_id")?.trim() || "";
    if (!exportJobId) throw new EdgeHttpError("export_job_id is required.", 400, "EXPORT_JOB_ID_REQUIRED");

    const userClient = createUserClient(accessToken);
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      throw new EdgeHttpError("Authenticated user context is not available.", 401, "INVALID_JWT");
    }

    const serviceClient = createServiceRoleClient();
    const { data: exportJob, error: exportJobError } = await (serviceClient as any)
      .from("platform_rm_export_job_overview")
      .select("export_job_id, tenant_id, contract_code, entity_code, requested_by_actor_user_id, job_id, artifact_document_id, export_artifact_id, file_name, content_type, file_size_bytes, retention_expires_at, artifact_status, job_status, progress_percent, result_summary, error_details, queued_at, started_at, completed_at, expires_at, created_at, updated_at")
      .eq("export_job_id", exportJobId)
      .maybeSingle();

    if (exportJobError) throw new EdgeHttpError("Unable to resolve export job status.", 500, "EXPORT_STATUS_LOOKUP_FAILED");
    if (!exportJob) throw new EdgeHttpError("Export job not found.", 404, "EXPORT_JOB_NOT_FOUND", { export_job_id: exportJobId });

    const { data: contract, error: contractError } = await (serviceClient as any)
      .from("platform_exchange_contract")
      .select("contract_code, allowed_role_codes")
      .eq("contract_code", exportJob.contract_code)
      .eq("contract_status", "active")
      .maybeSingle();

    if (contractError || !contract) {
      throw new EdgeHttpError("Active exchange contract could not be resolved for this export job.", 500, "CONTRACT_LOOKUP_FAILED", {
        contract_code: exportJob.contract_code,
      });
    }

    const accessRpc = await (serviceClient as unknown as {
      rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;
    }).rpc("platform_i06_assert_actor_access", {
      p_tenant_id: exportJob.tenant_id,
      p_actor_user_id: userData.user.id,
      p_allowed_role_codes: Array.isArray(contract.allowed_role_codes) ? contract.allowed_role_codes : [],
    });
    if (accessRpc.error) {
      throw new EdgeHttpError("Unable to validate actor access.", 500, "ACCESS_ASSERT_FAILED", {
        rpc_error: accessRpc.error.message,
      });
    }

    requirePlatformSuccess(
      (accessRpc.data ?? {}) as { success?: boolean; code?: string; message?: string; details?: Record<string, unknown> },
      "ACCESS_DENIED",
      "Actor is not allowed to inspect this export job.",
    );

    const publicBaseUrl = new URL(Deno.env.get("SUPABASE_URL")?.trim() || req.url);
    const downloadUrl = new URL("/functions/v1/exchange-export-download", publicBaseUrl);
    downloadUrl.searchParams.set("export_job_id", String(exportJob.export_job_id));

    logStructured("info", "exchange-export-status completed", {
      request_id: requestId,
      actor_user_id: userData.user.id,
      export_job_id: exportJob.export_job_id,
      job_status: exportJob.job_status,
      duration_ms: Date.now() - startedAt,
    });

    return jsonResponse({
      success: true,
      request_id: requestId,
      export_job: {
        export_job_id: String(exportJob.export_job_id),
        tenant_id: String(exportJob.tenant_id),
        contract_code: String(exportJob.contract_code),
        entity_code: String(exportJob.entity_code),
        requested_by_actor_user_id: exportJob.requested_by_actor_user_id ? String(exportJob.requested_by_actor_user_id) : null,
        job_id: exportJob.job_id ? String(exportJob.job_id) : null,
        artifact_document_id: exportJob.artifact_document_id ? String(exportJob.artifact_document_id) : null,
        export_artifact_id: exportJob.export_artifact_id ? String(exportJob.export_artifact_id) : null,
        file_name: exportJob.file_name ? String(exportJob.file_name) : null,
        content_type: exportJob.content_type ? String(exportJob.content_type) : null,
        file_size_bytes: typeof exportJob.file_size_bytes === "number" ? exportJob.file_size_bytes : null,
        retention_expires_at: exportJob.retention_expires_at ? String(exportJob.retention_expires_at) : null,
        artifact_status: exportJob.artifact_status ? String(exportJob.artifact_status) : null,
        job_status: String(exportJob.job_status),
        progress_percent: typeof exportJob.progress_percent === "number" ? exportJob.progress_percent : null,
        result_summary: exportJob.result_summary ?? {},
        error_details: exportJob.error_details ?? {},
        queued_at: exportJob.queued_at ? String(exportJob.queued_at) : null,
        started_at: exportJob.started_at ? String(exportJob.started_at) : null,
        completed_at: exportJob.completed_at ? String(exportJob.completed_at) : null,
        expires_at: exportJob.expires_at ? String(exportJob.expires_at) : null,
        created_at: exportJob.created_at ? String(exportJob.created_at) : null,
        updated_at: exportJob.updated_at ? String(exportJob.updated_at) : null,
      },
      download: exportJob.job_status === "completed" && exportJob.artifact_document_id ? { ready: true, url: downloadUrl.toString() } : { ready: false, url: null },
    });
  } catch (error) {
    const edgeError = error instanceof EdgeHttpError
      ? error
      : new EdgeHttpError(error instanceof Error ? error.message : "Unexpected error.", 500, "EXCHANGE_EXPORT_STATUS_FAILED");

    logStructured("error", "exchange-export-status failed", {
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
