import {
  CORS_HEADERS,
  createRequestId,
  jsonResponse,
  logStructured,
  readJsonBody,
} from "../_shared/http.ts";
import { requireServiceRoleAccess } from "../_shared/internal.ts";
import { asObject } from "../_shared_i06/platform.ts";
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

type ImportRunRow = {
  import_run_id: string;
  import_session_id: string;
  run_status: string;
};

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function positiveInt(value: unknown, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.trunc(parsed);
}

async function bestEffortWriteEvent(serviceClient: SupabaseClient, payload: JsonMap): Promise<void> {
  try {
    await callPlatformRpc(serviceClient, "platform_exchange_write_event", payload);
  } catch (error) {
    logStructured("warning", "i06_import_worker_event_write_failed", {
      error: error instanceof Error ? error.message : String(error),
      payload,
    });
  }
}

async function loadImportRun(serviceClient: SupabaseClient, jobId: string): Promise<ImportRunRow | null> {
  const { data, error } = await (serviceClient as any)
    .from("platform_import_run")
    .select("import_run_id, import_session_id, run_status")
    .eq("job_id", jobId)
    .maybeSingle();

  if (error) throw new Error(`Unable to load import run: ${error.message}`);
  return data ? { import_run_id: String(data.import_run_id), import_session_id: String(data.import_session_id), run_status: String(data.run_status) } : null;
}

async function updateImportRun(serviceClient: SupabaseClient, importRunId: string, patch: JsonMap): Promise<void> {
  const { error } = await (serviceClient as any).from("platform_import_run").update(patch).eq("import_run_id", importRunId);
  if (error) throw new Error(`Unable to update import run: ${error.message}`);
}

async function updateImportSession(serviceClient: SupabaseClient, importSessionId: string, patch: JsonMap): Promise<void> {
  const { error } = await (serviceClient as any).from("platform_import_session").update(patch).eq("import_session_id", importSessionId);
  if (error) throw new Error(`Unable to update import session: ${error.message}`);
}

async function recordFailure(serviceClient: SupabaseClient, args: { jobId: string; claimedByWorker: string; importSessionId?: string | null; importRunId?: string | null; errorCode: string; errorMessage: string; errorDetails: JsonMap; terminal: boolean; }): Promise<void> {
  const nowIso = new Date().toISOString();

  if (args.importRunId) {
    await updateImportRun(serviceClient, args.importRunId, {
      run_status: args.terminal ? "failed" : "queued",
      completed_at: args.terminal ? nowIso : null,
      diagnostics: { error_code: args.errorCode, error_message: args.errorMessage, error_details: args.errorDetails },
      updated_at: nowIso,
    });
  }

  if (args.terminal && args.importSessionId) {
    await updateImportSession(serviceClient, args.importSessionId, { session_status: "preview_ready", updated_at: nowIso });
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
  const importSessionId = asString(payload.import_session_id);
  const requestedByActorUserId = asString(payload.requested_by_actor_user_id);
  const importRun = await loadImportRun(serviceClient, job.job_id);

  if (!importSessionId) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, importRunId: importRun?.import_run_id, errorCode: "INVALID_IMPORT_JOB_PAYLOAD", errorMessage: "I06 import job payload is missing import_session_id.", errorDetails: { payload }, terminal: true });
    return "failed_terminal";
  }

  await callPlatformRpc(serviceClient, "platform_async_heartbeat_job", { job_id: job.job_id, claimed_by_worker: job.claimed_by_worker });

  const { data: session, error: sessionError } = await (serviceClient as any)
    .from("platform_import_session")
    .select("import_session_id, tenant_id, requested_by_actor_user_id, session_status, validation_summary")
    .eq("import_session_id", importSessionId)
    .maybeSingle();

  if (sessionError) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, importSessionId, importRunId: importRun?.import_run_id, errorCode: "IMPORT_SESSION_LOOKUP_FAILED", errorMessage: sessionError.message, errorDetails: {}, terminal: false });
    return "retry_wait";
  }
  if (!session) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, importSessionId, importRunId: importRun?.import_run_id, errorCode: "IMPORT_SESSION_NOT_FOUND", errorMessage: "Import session not found.", errorDetails: { import_session_id: importSessionId }, terminal: true });
    return "failed_terminal";
  }

  const sessionStatus = String(session.session_status);
  if (sessionStatus === "committed") {
    if (importRun?.import_run_id) {
      await updateImportRun(serviceClient, importRun.import_run_id, { run_status: "completed", completed_at: new Date().toISOString(), updated_at: new Date().toISOString() });
    }
    await callPlatformRpc(serviceClient, "platform_async_complete_job", { job_id: job.job_id, claimed_by_worker: job.claimed_by_worker, result_summary: { import_session_id: importSessionId, outcome: "already_committed" } });
    return "completed";
  }

  if (!["committing", "ready_to_commit"].includes(sessionStatus)) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, importSessionId, importRunId: importRun?.import_run_id, errorCode: "IMPORT_SESSION_NOT_READY", errorMessage: `Import session is not ready for commit: ${sessionStatus}`, errorDetails: { import_session_id: importSessionId, session_status: sessionStatus }, terminal: true });
    return "failed_terminal";
  }

  const { data: stagingRows, error: stagingError } = await (serviceClient as any)
    .from("platform_import_staging_row")
    .select("staging_row_id, source_row_number, canonical_row")
    .eq("import_session_id", importSessionId)
    .eq("validation_status", "ready")
    .order("source_row_number", { ascending: true });

  if (stagingError) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, importSessionId, importRunId: importRun?.import_run_id, errorCode: "IMPORT_STAGING_LOOKUP_FAILED", errorMessage: stagingError.message, errorDetails: {}, terminal: false });
    return "retry_wait";
  }
  if (!Array.isArray(stagingRows) || stagingRows.length === 0) {
    await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, importSessionId, importRunId: importRun?.import_run_id, errorCode: "IMPORT_SESSION_NOT_READY", errorMessage: "No ready staging rows are available for commit.", errorDetails: { import_session_id: importSessionId }, terminal: true });
    return "failed_terminal";
  }

  const nowIso = new Date().toISOString();
  if (importRun?.import_run_id) {
    await updateImportRun(serviceClient, importRun.import_run_id, { run_status: "running", started_at: nowIso, updated_at: nowIso });
  }

  let committedRows = 0;
  for (const row of stagingRows) {
    const canonicalRow = asObject(row.canonical_row);
    const employeeCode = asString(canonicalRow.employee_code);
    const fullName = asString(canonicalRow.full_name);
    const startDate = asString(canonicalRow.start_date) || null;
    const salary = canonicalRow.salary ?? null;

    if (!employeeCode || !fullName) {
      throw new Error(`Ready staging row is missing required proof fields at row ${row.source_row_number}.`);
    }

    const { data: upsertedRow, error: upsertError } = await (serviceClient as any)
      .from("i06_proof_entity")
      .upsert({
        tenant_id: String(session.tenant_id),
        employee_code: employeeCode,
        full_name: fullName,
        salary,
        start_date: startDate,
        metadata: { import_session_id: importSessionId, source_row_number: row.source_row_number, committed_via: "i06-import-worker", request_id: requestId },
        created_by: asString(session.requested_by_actor_user_id) || requestedByActorUserId || null,
      }, { onConflict: "tenant_id,employee_code" })
      .select("proof_entity_id")
      .maybeSingle();

    if (upsertError) throw new Error(`Unable to upsert proof entity row ${row.source_row_number}: ${upsertError.message}`);

    const { error: stagingUpdateError } = await (serviceClient as any)
      .from("platform_import_staging_row")
      .update({ commit_result: { success: true, proof_entity_id: upsertedRow?.proof_entity_id ? String(upsertedRow.proof_entity_id) : null, committed_at: nowIso, worker_request_id: requestId }, updated_at: nowIso })
      .eq("staging_row_id", row.staging_row_id);

    if (stagingUpdateError) throw new Error(`Unable to update staging commit result for row ${row.source_row_number}: ${stagingUpdateError.message}`);
    committedRows += 1;
  }

  const summary = { ...(asObject(session.validation_summary)), import_session_id: importSessionId, committed_rows: committedRows, failed_rows: 0, session_status: "committed" };

  const { error: validationSummaryError } = await (serviceClient as any)
    .from("platform_import_validation_summary")
    .update({ committed_rows: committedRows, failed_rows: 0, summary_payload: summary, updated_at: nowIso })
    .eq("import_session_id", importSessionId);

  if (validationSummaryError) throw new Error(`Unable to update import validation summary: ${validationSummaryError.message}`);

  await updateImportSession(serviceClient, importSessionId, { session_status: "committed", committed_at: nowIso, validation_summary: summary, updated_at: nowIso });

  if (importRun?.import_run_id) {
    await updateImportRun(serviceClient, importRun.import_run_id, { run_status: "completed", result_summary: summary, completed_at: nowIso, updated_at: nowIso });
  }

  await bestEffortWriteEvent(serviceClient, {
    contract_id: null,
    tenant_id: String(session.tenant_id),
    actor_user_id: asString(session.requested_by_actor_user_id) || requestedByActorUserId || null,
    event_type: "import_run_completed",
    message: "I06 import worker completed import run.",
    details: { import_session_id: importSessionId, import_run_id: importRun?.import_run_id ?? null, committed_rows: committedRows },
  });

  await callPlatformRpc(serviceClient, "platform_async_complete_job", {
    job_id: job.job_id,
    claimed_by_worker: job.claimed_by_worker,
    result_summary: { import_session_id: importSessionId, import_run_id: importRun?.import_run_id ?? null, committed_rows: committedRows, outcome: "completed" },
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
    const claimResult = await callPlatformRpc(serviceClient, "platform_async_claim_jobs", { worker_code: "i06_import_worker", batch_size: batchSize, claimed_by_worker: `i06-import-worker:${requestId}` });

    if (claimResult.success !== true) {
      return jsonResponse({ success: false, request_id: requestId, error: claimResult.message || "Unable to claim I06 import jobs.", error_code: claimResult.code || "I06_IMPORT_CLAIM_FAILED", details: claimResult.details || {} }, 409);
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
        const importRun = await loadImportRun(serviceClient, job.job_id).catch(() => null);
        await recordFailure(serviceClient, { jobId: job.job_id, claimedByWorker: job.claimed_by_worker, importRunId: importRun?.import_run_id, importSessionId: asString(job.payload.import_session_id) || null, errorCode: "I06_IMPORT_WORKER_FAILED", errorMessage: error instanceof Error ? error.message : String(error), errorDetails: {}, terminal: false });
        retryWait += 1;
      }
    }

    logStructured("info", "i06-import-worker completed", {
      request_id: requestId,
      claimed_count: jobs.length,
      completed_count: completed,
      retry_wait_count: retryWait,
      failed_terminal_count: failedTerminal,
      duration_ms: Date.now() - startedAt,
    });

    return jsonResponse({ success: true, request_id: requestId, claimed_count: jobs.length, completed_count: completed, retry_wait_count: retryWait, failed_terminal_count: failedTerminal });
  } catch (error) {
    logStructured("error", "i06-import-worker failed", {
      request_id: requestId,
      duration_ms: Date.now() - startedAt,
      error: error instanceof Error ? error.message : String(error),
    });
    return jsonResponse({ success: false, request_id: requestId, error: error instanceof Error ? error.message : "Unable to process I06 import jobs.", error_code: "I06_IMPORT_WORKER_FAILED" }, 500);
  }
});

