import * as XLSX from "npm:xlsx@0.18.5";

import {
  CORS_HEADERS,
  createRequestId,
  jsonResponse,
  logStructured,
  readJsonBody,
} from "../_shared/http.ts";
import { requireServiceRoleAccess } from "../_shared/internal.ts";
import { asObject, asStringOrNull, requirePlatformSuccess } from "../_shared_i06/platform.ts";
import { callPlatformRpc, createServiceRoleClient, type JsonMap, type SupabaseClient } from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 8 * 1024;
const DEFAULT_BATCH_SIZE = 10;

type ClaimedJob = {
  job_id: string;
  tenant_id: string;
  worker_code: string;
  attempt_count: number;
  claimed_by_worker: string;
  payload: JsonMap;
};

type ProofRow = {
  employee_code: string;
  full_name: string;
  salary: number | null;
  start_date: string | null;
};

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function positiveInt(value: unknown, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.trunc(parsed);
}

function csvCell(value: unknown): string {
  if (value === null || value === undefined) return "";
  const raw = typeof value === "string" ? value : String(value);
  if (/[",\r\n]/.test(raw)) return `"${raw.replace(/"/g, '""')}"`;
  return raw;
}

function buildCsv(rows: ProofRow[]): Uint8Array {
  const header = ["employee_code", "full_name", "salary", "start_date"];
  const lines = [header.join(",")];
  for (const row of rows) {
    lines.push([
      csvCell(row.employee_code),
      csvCell(row.full_name),
      csvCell(row.salary),
      csvCell(row.start_date),
    ].join(","));
  }
  return new TextEncoder().encode(lines.join("\r\n") + "\r\n");
}

function buildWorkbook(rows: ProofRow[]): Uint8Array {
  const sheetRows = [["employee_code", "full_name", "salary", "start_date"], ...rows.map((row) => [row.employee_code, row.full_name, row.salary, row.start_date])];
  const worksheet = XLSX.utils.aoa_to_sheet(sheetRows);
  const workbook = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook, worksheet, "employees");
  const arrayBuffer = XLSX.write(workbook, { type: "array", bookType: "xlsx" }) as ArrayBuffer;
  return new Uint8Array(arrayBuffer);
}

function normalizeFormat(requestPayload: JsonMap): "csv" | "xlsx" {
  return asString(requestPayload.format).toLowerCase() === "csv" ? "csv" : "xlsx";
}

function buildExportPayload(rows: ProofRow[], format: "csv" | "xlsx") {
  const timestamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
  if (format === "csv") {
    return { bytes: buildCsv(rows), contentType: "text/csv", fileName: `i06-proof-employees-${timestamp}.csv` };
  }
  return { bytes: buildWorkbook(rows), contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileName: `i06-proof-employees-${timestamp}.xlsx` };
}

async function bestEffortWriteEvent(serviceClient: SupabaseClient, payload: JsonMap): Promise<void> {
  try {
    await callPlatformRpc(serviceClient, "platform_exchange_write_event", payload);
  } catch (error) {
    logStructured("warning", "i06_export_worker_event_write_failed", { error: error instanceof Error ? error.message : String(error), payload });
  }
}

async function recordFailure(serviceClient: SupabaseClient, args: { jobId: string; claimedByWorker: string; exportJobId?: string | null; errorCode: string; errorMessage: string; errorDetails: JsonMap; terminal: boolean; }): Promise<void> {
  const nowIso = new Date().toISOString();
  if (args.exportJobId) {
    const { error } = await (serviceClient as any)
      .from("platform_export_job")
      .update({ job_status: args.terminal ? "failed" : "queued", error_details: { error_code: args.errorCode, error_message: args.errorMessage, error_details: args.errorDetails }, updated_at: nowIso })
      .eq("export_job_id", args.exportJobId);
    if (error) throw new Error(`Unable to update export job failure state: ${error.message}`);
  }

  await callPlatformRpc(serviceClient, "platform_async_fail_job", {
    job_id: args.jobId,
    claimed_by_worker: args.claimedByWorker,
    terminal: args.terminal,
    dead_letter: args.terminal,
    error_code: args.errorCode,
    error_message: args.errorMessage,
    error_details: args.errorDetails,
  });
}

async function processClaimedJob(serviceClient: SupabaseClient, requestId: string, job: ClaimedJob): Promise<string> {
  const payload = asObject(job.payload);
  const requestPayload = asObject(payload.request_payload);
  const exportJobQuery = await (serviceClient as any)
    .from("platform_export_job")
    .select("export_job_id, tenant_id, contract_id, requested_by_actor_user_id, job_id, artifact_document_id, request_payload, job_status, progress_percent, result_summary, error_details, queued_at, started_at, completed_at, expires_at")
    .eq("job_id", job.job_id)
    .maybeSingle();

  if (exportJobQuery.error) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, errorCode: "EXPORT_JOB_LOOKUP_FAILED", errorMessage: exportJobQuery.error.message, errorDetails: {}, terminal: false });
    return "retry_wait";
  }

  const exportJob = exportJobQuery.data;
  if (!exportJob) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, errorCode: "EXPORT_JOB_NOT_FOUND", errorMessage: "Export job not found for async job.", errorDetails: { job_id: job.job_id }, terminal: true });
    return "failed_terminal";
  }

  const exportJobId = String(exportJob.export_job_id);
  await callPlatformRpc(serviceClient, "platform_async_heartbeat_job", { job_id: job.job_id, claimed_by_worker: job.claimed_by_worker });

  const artifactQuery = await (serviceClient as any)
    .from("platform_export_artifact")
    .select("export_artifact_id, document_id, file_name, content_type, artifact_status, retention_expires_at")
    .eq("export_job_id", exportJobId)
    .eq("artifact_status", "active")
    .maybeSingle();

  if (artifactQuery.error) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, exportJobId, errorCode: "EXPORT_ARTIFACT_LOOKUP_FAILED", errorMessage: artifactQuery.error.message, errorDetails: {}, terminal: false });
    return "retry_wait";
  }

  const activeArtifact = artifactQuery.data;
  const retentionExpiresAt = activeArtifact?.retention_expires_at ? new Date(String(activeArtifact.retention_expires_at)) : null;
  const artifactStillFresh = Boolean(activeArtifact && (!retentionExpiresAt || retentionExpiresAt.getTime() > Date.now()));

  if (String(exportJob.job_status) === "completed" && artifactStillFresh) {
    await callPlatformRpc(serviceClient, "platform_async_complete_job", {
      job_id: job.job_id,
      claimed_by_worker: job.claimed_by_worker,
      result_summary: {
        export_job_id: exportJobId,
        export_artifact_id: activeArtifact?.export_artifact_id ? String(activeArtifact.export_artifact_id) : null,
        document_id: activeArtifact?.document_id ? String(activeArtifact.document_id) : null,
        file_name: activeArtifact?.file_name ? String(activeArtifact.file_name) : null,
        outcome: "already_completed",
      },
    });
    return "completed";
  }

  if (activeArtifact && retentionExpiresAt && retentionExpiresAt.getTime() <= Date.now()) {
    requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_i06_cleanup_expired_export_artifacts", { source: "i06-export-worker", export_job_id: exportJobId }),
      "I06_EXPORT_CLEANUP_FAILED",
      "Unable to clean up expired export artifacts.",
    );
  }

  const contractQuery = await (serviceClient as any)
    .from("platform_exchange_contract")
    .select("contract_code, artifact_document_class_code")
    .eq("contract_id", exportJob.contract_id)
    .maybeSingle();

  if (contractQuery.error || !contractQuery.data) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, exportJobId, errorCode: "EXPORT_CONTRACT_NOT_FOUND", errorMessage: contractQuery.error?.message ?? "Export contract not found.", errorDetails: {}, terminal: true });
    return "failed_terminal";
  }

  const contractCode = String(contractQuery.data.contract_code);
  const artifactDocumentClassCode = asString(contractQuery.data.artifact_document_class_code);
  if (!artifactDocumentClassCode) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, exportJobId, errorCode: "ARTIFACT_DOCUMENT_CLASS_REQUIRED", errorMessage: "Export contract is missing artifact_document_class_code.", errorDetails: { contract_code: contractCode }, terminal: true });
    return "failed_terminal";
  }

  const requestedByActorUserId = asString(exportJob.requested_by_actor_user_id) || asString(payload.requested_by_actor_user_id);
  if (!requestedByActorUserId) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, exportJobId, errorCode: "ACTOR_USER_ID_REQUIRED", errorMessage: "Export job is missing requested_by_actor_user_id.", errorDetails: {}, terminal: true });
    return "failed_terminal";
  }

  const { error: runningUpdateError } = await (serviceClient as any)
    .from("platform_export_job")
    .update({ job_status: "running", progress_percent: 10, started_at: exportJob.started_at ?? new Date().toISOString(), updated_at: new Date().toISOString(), error_details: {} })
    .eq("export_job_id", exportJobId);

  if (runningUpdateError) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, exportJobId, errorCode: "EXPORT_JOB_RUNNING_UPDATE_FAILED", errorMessage: runningUpdateError.message, errorDetails: {}, terminal: false });
    return "retry_wait";
  }

  const rowsQuery = await (serviceClient as any)
    .from("i06_proof_entity")
    .select("employee_code, full_name, salary, start_date")
    .eq("tenant_id", String(exportJob.tenant_id))
    .order("employee_code", { ascending: true });

  if (rowsQuery.error) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, exportJobId, errorCode: "I06_PROOF_EXPORT_SOURCE_FAILED", errorMessage: rowsQuery.error.message, errorDetails: {}, terminal: false });
    return "retry_wait";
  }

  const rows = Array.isArray(rowsQuery.data) ? rowsQuery.data.map((row) => ({ employee_code: asString(row.employee_code), full_name: asString(row.full_name), salary: row.salary === null || row.salary === undefined ? null : Number(row.salary), start_date: asStringOrNull(row.start_date) } satisfies ProofRow)) : [];
  const format = normalizeFormat(asObject(exportJob.request_payload ?? requestPayload));
  const rendered = buildExportPayload(rows, format);

  const uploadIntent = requirePlatformSuccess(
    await callPlatformRpc(serviceClient, "platform_issue_document_upload_intent", {
      tenant_id: String(exportJob.tenant_id),
      document_class_code: artifactDocumentClassCode,
      requested_by_actor_user_id: requestedByActorUserId,
      owner_actor_user_id: requestedByActorUserId,
      original_file_name: rendered.fileName,
      content_type: rendered.contentType,
      expected_size_bytes: rendered.bytes.byteLength,
      bypass_membership_check: true,
      metadata: { source: "i06-export-worker", export_job_id: exportJobId, contract_code: contractCode },
    }),
    "EXPORT_UPLOAD_INTENT_FAILED",
    "Unable to issue export artifact upload intent.",
  );

  const bucketName = asString(uploadIntent.bucket_name);
  const storageObjectName = asString(uploadIntent.storage_object_name);
  const uploadIntentId = asString(uploadIntent.upload_intent_id);
  if (!bucketName || !storageObjectName || !uploadIntentId) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, exportJobId, errorCode: "EXPORT_UPLOAD_INTENT_INVALID", errorMessage: "Export upload intent returned an incomplete response.", errorDetails: { upload_intent: uploadIntent }, terminal: false });
    return "retry_wait";
  }

  const storageResponse = await (serviceClient.storage.from(bucketName) as any).upload(storageObjectName, rendered.bytes, { contentType: rendered.contentType, upsert: true });
  if (storageResponse.error) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, exportJobId, errorCode: "EXPORT_STORAGE_UPLOAD_FAILED", errorMessage: storageResponse.error.message, errorDetails: {}, terminal: false });
    return "retry_wait";
  }

  const completedDocument = requirePlatformSuccess(
    await callPlatformRpc(serviceClient, "platform_complete_document_upload", {
      upload_intent_id: uploadIntentId,
      uploaded_by_actor_user_id: requestedByActorUserId,
      file_size_bytes: rendered.bytes.byteLength,
      storage_metadata: { source: "i06-export-worker", export_job_id: exportJobId },
      document_metadata: { contract_code: contractCode, export_job_id: exportJobId, format, row_count: rows.length },
    }),
    "EXPORT_DOCUMENT_COMPLETE_FAILED",
    "Unable to complete export document upload.",
  );

  const documentId = asString(completedDocument.document_id);
  if (!documentId) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, exportJobId, errorCode: "EXPORT_DOCUMENT_ID_MISSING", errorMessage: "Export document completion did not return document_id.", errorDetails: { completed_document: completedDocument }, terminal: false });
    return "retry_wait";
  }

  const artifact = requirePlatformSuccess(
    await callPlatformRpc(serviceClient, "platform_register_export_artifact", {
      export_job_id: exportJobId,
      document_id: documentId,
      created_by: requestedByActorUserId,
      metadata: { source: "i06-export-worker", contract_code: contractCode, format, row_count: rows.length },
    }),
    "EXPORT_ARTIFACT_REGISTER_FAILED",
    "Unable to register export artifact.",
  );

  await bestEffortWriteEvent(serviceClient, { export_job_id: exportJobId, contract_id: String(exportJob.contract_id), tenant_id: String(exportJob.tenant_id), actor_user_id: requestedByActorUserId, event_type: "export_job_completed", message: "I06 export worker completed export job.", details: { export_job_id: exportJobId, export_artifact_id: artifact.export_artifact_id ?? null, document_id: documentId, format, row_count: rows.length } });

  await callPlatformRpc(serviceClient, "platform_async_complete_job", {
    job_id: job.job_id,
    claimed_by_worker: job.claimed_by_worker,
    result_summary: { export_job_id: exportJobId, export_artifact_id: artifact.export_artifact_id ?? null, document_id: documentId, file_name: rendered.fileName, format, row_count: rows.length, outcome: "completed" },
  });

  return "completed";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  const requestId = createRequestId(req);
  const startedAt = Date.now();

  try {
    if (req.method !== "POST") return jsonResponse({ success: false, error: "Method not allowed.", error_code: "METHOD_NOT_ALLOWED" }, 405);

    await requireServiceRoleAccess(req);
    const body = asObject(await readJsonBody(req, MAX_BODY_BYTES));
    const batchSize = Math.max(1, positiveInt(body.batch_size, DEFAULT_BATCH_SIZE));
    const serviceClient = createServiceRoleClient();
    const claimResult = await callPlatformRpc(serviceClient, "platform_async_claim_jobs", { worker_code: "i06_export_worker", batch_size: batchSize, claimed_by_worker: `i06-export-worker:${requestId}` });

    if (claimResult.success !== true) {
      return jsonResponse({ success: false, request_id: requestId, error: claimResult.message || "Unable to claim I06 export jobs.", error_code: claimResult.code || "I06_EXPORT_CLAIM_FAILED", details: claimResult.details || {} }, 409);
    }

    const claimDetails = asObject(claimResult.details);
    const jobs = Array.isArray(claimDetails.jobs) ? claimDetails.jobs.map((entry) => {
      const row = asObject(entry);
      return {
        job_id: asString(row.job_id),
        tenant_id: asString(row.tenant_id),
        worker_code: asString(row.worker_code),
        attempt_count: positiveInt(row.attempt_count, 0),
        claimed_by_worker: asString(row.claimed_by_worker),
        payload: asObject(row.payload),
      } satisfies ClaimedJob;
    }) : [];

    let completed = 0;
    let retryWait = 0;
    let failedTerminal = 0;

    for (const job of jobs) {
      try {
        const outcome = await processClaimedJob(serviceClient, requestId, job);
        if (outcome === "completed") completed += 1;
        else if (outcome === "retry_wait") retryWait += 1;
        else failedTerminal += 1;
      } catch (error) {
        const exportJobQuery = await (serviceClient as any).from("platform_export_job").select("export_job_id").eq("job_id", job.job_id).maybeSingle();
        await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, exportJobId: exportJobQuery.data?.export_job_id ? String(exportJobQuery.data.export_job_id) : null, errorCode: "I06_EXPORT_WORKER_FAILED", errorMessage: error instanceof Error ? error.message : String(error), errorDetails: { payload: asObject(job.payload) }, terminal: false });
        retryWait += 1;
      }
    }

    logStructured("info", "i06-export-worker completed", {
      request_id: requestId,
      claimed_count: jobs.length,
      completed_count: completed,
      retry_wait_count: retryWait,
      failed_terminal_count: failedTerminal,
      duration_ms: Date.now() - startedAt,
    });

    return jsonResponse({ success: true, request_id: requestId, claimed_count: jobs.length, completed_count: completed, retry_wait_count: retryWait, failed_terminal_count: failedTerminal });
  } catch (error) {
    logStructured("error", "i06-export-worker failed", {
      request_id: requestId,
      duration_ms: Date.now() - startedAt,
      error: error instanceof Error ? error.message : String(error),
    });
    return jsonResponse({ success: false, request_id: requestId, error: error instanceof Error ? error.message : "Unable to process I06 export jobs.", error_code: "I06_EXPORT_WORKER_FAILED" }, 500);
  }
});
