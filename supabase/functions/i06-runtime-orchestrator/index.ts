import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  jsonResponse,
  logStructured,
  readJsonBody,
} from "../_shared/http.ts";
import { invokeInternalFunction, requireServiceRoleAccess } from "../_shared/internal.ts";
import { asObject, requirePlatformSuccess } from "../_shared_i06/platform.ts";
import { callPlatformRpc, createServiceRoleClient, type JsonMap } from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 8 * 1024;

function positiveInt(value: unknown, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.trunc(parsed);
}

async function invokeWorker(functionSlug: string, body: JsonMap): Promise<JsonMap> {
  try {
    const response = await invokeInternalFunction(functionSlug, body);
    let payload: JsonMap = {};
    try {
      payload = asObject(await response.json());
    } catch {
      payload = { success: false, error_code: "INVALID_WORKER_RESPONSE", error: "Worker returned a non-JSON response." };
    }
    return { function_slug: functionSlug, ok: response.ok, status: response.status, payload };
  } catch (error) {
    return { function_slug: functionSlug, ok: false, status: 0, payload: { success: false, error_code: "WORKER_INVOCATION_FAILED", error: error instanceof Error ? error.message : String(error) } };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  const requestId = createRequestId(req);
  const startedAt = Date.now();

  try {
    if (req.method !== "POST") return jsonResponse({ success: false, error: "Method not allowed.", error_code: "METHOD_NOT_ALLOWED" }, 405);

    await requireServiceRoleAccess(req);
    const body = asObject(await readJsonBody(req, MAX_BODY_BYTES));
    const serviceClient = createServiceRoleClient();
    const source = typeof body.source === "string" && body.source.trim() ? body.source.trim() : "edge";

    const maintenance = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_i06_run_exchange_maintenance", { source, request_id: requestId }),
      "I06_MAINTENANCE_FAILED",
      "Unable to complete I06 maintenance.",
    );

    const readiness = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_async_dispatch_due_jobs", { module_code: "I06", dispatch_mode: "edge_worker", limit_workers: 10 }),
      "I06_DISPATCH_READINESS_FAILED",
      "Unable to resolve I06 dispatch readiness.",
    );

    const workers = Array.isArray(readiness.workers) ? readiness.workers.map((entry) => asObject(entry)) : [];
    const importReady = workers.find((entry) => String(entry.worker_code ?? "") === "i06_import_worker");
    const exportReady = workers.find((entry) => String(entry.worker_code ?? "") === "i06_export_worker");
    const importDueCount = positiveInt(importReady?.due_job_count, 0);
    const exportDueCount = positiveInt(exportReady?.due_job_count, 0);
    const batchSizeOverride = positiveInt(body.batch_size, 10);

    if (importDueCount <= 0 && exportDueCount <= 0) {
      return jsonResponse({ success: true, request_id: requestId, idle: true, source, maintenance, readiness: workers });
    }

    const invocations: JsonMap[] = [];
    if (importDueCount > 0) {
      invocations.push(await invokeWorker("i06-import-worker", { batch_size: Math.max(1, Math.min(50, importDueCount, batchSizeOverride)), source: "i06-runtime-orchestrator", orchestrator_request_id: requestId }));
    }
    if (exportDueCount > 0) {
      invocations.push(await invokeWorker("i06-export-worker", { batch_size: Math.max(1, Math.min(50, exportDueCount, batchSizeOverride)), source: "i06-runtime-orchestrator", orchestrator_request_id: requestId }));
    }

    const successfulInvocations = invocations.filter((entry) => entry.ok === true).length;

    logStructured("info", "i06-runtime-orchestrator completed", {
      request_id: requestId,
      source,
      import_due_count: importDueCount,
      export_due_count: exportDueCount,
      successful_invocations: successfulInvocations,
      duration_ms: Date.now() - startedAt,
    });

    if (successfulInvocations === 0) {
      return jsonResponse({ success: false, request_id: requestId, error: "I06 worker invocation failed.", error_code: "I06_WORKER_INVOCATION_FAILED", maintenance, readiness: workers, invocations }, 502);
    }

    return jsonResponse({ success: true, request_id: requestId, source, maintenance, readiness: workers, invocations });
  } catch (error) {
    logStructured("error", "i06-runtime-orchestrator failed", {
      request_id: requestId,
      duration_ms: Date.now() - startedAt,
      error: error instanceof Error ? error.message : String(error),
    });

    if (error instanceof EdgeHttpError) {
      return jsonResponse({ success: false, error: error.message, error_code: error.code, details: error.details }, error.status, error.headers);
    }

    return jsonResponse({ success: false, request_id: requestId, error: error instanceof Error ? error.message : "Unable to orchestrate I06 runtime.", error_code: "I06_RUNTIME_ORCHESTRATOR_FAILED" }, 500);
  }
});
