import { asObject, CORS_HEADERS, createRequestId, EdgeHttpError, jsonResponse, logStructured, readJsonBody } from "../_shared/http.ts";
import { invokeInternalFunction, requireServiceRoleAccess } from "../_shared/internal.ts";
import { callPlatformRpc, createServiceRoleClient, type JsonMap } from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 8 * 1024;

type AutoscaleConfig = {
  configStatus: string;
  autoscaleEnabled: boolean;
  minParallelInvocations: number;
  maxParallelInvocations: number;
  scaleUpThreshold: number;
  scaleDownThreshold: number;
  defaultBatchSize: number;
  maxBatchSize: number;
};

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function positiveInt(value: unknown, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.trunc(parsed);
}

async function loadAutoscaleConfig(): Promise<AutoscaleConfig> {
  const client = createServiceRoleClient();
  const { data, error } = await client
    .from("platform_signup_autoscale_config")
    .select("config_status, autoscale_enabled, min_parallel_invocations, max_parallel_invocations, scale_up_threshold, scale_down_threshold, default_batch_size, max_batch_size")
    .eq("config_code", "primary")
    .maybeSingle();

  if (error) {
    throw new Error(`Unable to load signup autoscale config: ${error.message}`);
  }

  return {
    configStatus: String(data?.config_status ?? "active"),
    autoscaleEnabled: data?.autoscale_enabled !== false,
    minParallelInvocations: positiveInt(data?.min_parallel_invocations, 1),
    maxParallelInvocations: positiveInt(data?.max_parallel_invocations, 3),
    scaleUpThreshold: Math.max(0, Number(data?.scale_up_threshold ?? 10)),
    scaleDownThreshold: Math.max(0, Number(data?.scale_down_threshold ?? 0)),
    defaultBatchSize: positiveInt(data?.default_batch_size, 5),
    maxBatchSize: positiveInt(data?.max_batch_size, 10),
  };
}

function computeParallelTarget(
  dueJobCount: number,
  config: AutoscaleConfig,
  batchSize: number,
  overrideValue: unknown,
): number {
  if (dueJobCount <= 0) return 0;

  const overrideTarget = Number(overrideValue);
  if (Number.isFinite(overrideTarget) && overrideTarget > 0) {
    return clamp(Math.trunc(overrideTarget), 1, Math.min(config.maxParallelInvocations, dueJobCount));
  }

  if (config.configStatus !== "active" || !config.autoscaleEnabled) {
    return 1;
  }

  let target = Math.max(config.minParallelInvocations, Math.ceil(dueJobCount / batchSize));
  if (config.scaleUpThreshold > 0 && dueJobCount >= config.scaleUpThreshold) {
    target = config.maxParallelInvocations;
  } else if (dueJobCount <= config.scaleDownThreshold) {
    target = config.minParallelInvocations;
  }

  return clamp(target, config.minParallelInvocations, Math.min(config.maxParallelInvocations, dueJobCount));
}

async function captureMetrics(
  client: ReturnType<typeof createServiceRoleClient>,
  parallelTarget: number,
  batchSize: number,
  metadata: JsonMap,
): Promise<void> {
  try {
    await callPlatformRpc(client, "platform_capture_signup_metrics", {
      parallel_invocation_target: Math.max(parallelTarget, 1),
      configured_batch_size: Math.max(batchSize, 1),
      metadata,
    });
  } catch (error) {
    logStructured("warning", "identity_signup_orchestrator_metrics_capture_failed", {
      error: error instanceof Error ? error.message : String(error),
      parallel_target: parallelTarget,
      batch_size: batchSize,
    });
  }
}

async function invokeWorker(batchSize: number, requestId: string, invocationIndex: number): Promise<JsonMap> {
  try {
    const response = await invokeInternalFunction("identity-signup-worker", {
      batch_size: batchSize,
      orchestrator_request_id: requestId,
      invocation_index: invocationIndex,
    });

    let payload: JsonMap = {};
    try {
      payload = asObject(await response.json());
    } catch {
      payload = { success: false, error_code: "INVALID_WORKER_RESPONSE", error: "Worker returned non-JSON response." };
    }

    return {
      invocation_index: invocationIndex,
      ok: response.ok,
      status: response.status,
      payload,
    };
  } catch (error) {
    return {
      invocation_index: invocationIndex,
      ok: false,
      status: 0,
      payload: {
        success: false,
        error_code: "WORKER_INVOCATION_FAILED",
        error: error instanceof Error ? error.message : String(error),
      },
    };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  const requestId = createRequestId(req);
  const startedAt = Date.now();

  try {
    if (req.method !== "POST") {
      return jsonResponse({ success: false, error: "Method not allowed.", error_code: "METHOD_NOT_ALLOWED" }, 405);
    }

    await requireServiceRoleAccess(req);
    const body = asObject(await readJsonBody(req, MAX_BODY_BYTES));
    const serviceClient = createServiceRoleClient();
    const config = await loadAutoscaleConfig();

    const breaker = await callPlatformRpc(serviceClient, "platform_signup_circuit_breaker_check", {});
    const breakerDetails = asObject(breaker.details);
    if (breaker.success !== true || breakerDetails.is_allowed !== true) {
      await captureMetrics(serviceClient, config.minParallelInvocations, config.defaultBatchSize, {
        request_id: requestId,
        blocked: true,
        source: body.source ?? "edge",
      });
      return jsonResponse({
        success: true,
        request_id: requestId,
        blocked: true,
        breaker: breakerDetails,
      });
    }

    const readiness = await callPlatformRpc(serviceClient, "platform_async_dispatch_due_jobs", {
      worker_code: "i01_signup_worker",
      dispatch_mode: "edge_worker",
      limit_workers: 1,
    });

    if (readiness.success !== true) {
      return jsonResponse({
        success: false,
        error: readiness.message || "Unable to resolve signup dispatch readiness.",
        error_code: readiness.code || "SIGNUP_DISPATCH_READINESS_FAILED",
        details: readiness.details || {},
      }, 409);
    }

    const readinessDetails = asObject(readiness.details);
    const workers = Array.isArray(readinessDetails.workers) ? readinessDetails.workers : [];
    const worker = workers.length > 0 ? asObject(workers[0]) : {};
    const dueJobCount = Math.max(0, Number(worker.due_job_count ?? 0));
    const batchSize = clamp(positiveInt(body.batch_size, config.defaultBatchSize), 1, config.maxBatchSize);
    const parallelTarget = computeParallelTarget(dueJobCount, config, batchSize, body.parallel_invocation_target);

    if (dueJobCount <= 0 || parallelTarget <= 0) {
      await captureMetrics(serviceClient, config.minParallelInvocations, batchSize, {
        request_id: requestId,
        source: body.source ?? "edge",
        due_job_count: dueJobCount,
        idle: true,
      });
      return jsonResponse({
        success: true,
        request_id: requestId,
        idle: true,
        due_job_count: dueJobCount,
        configured_batch_size: batchSize,
      });
    }

    const invocations = await Promise.all(
      Array.from({ length: parallelTarget }, (_, index) => invokeWorker(batchSize, requestId, index + 1)),
    );

    const okCount = invocations.filter((item) => item.ok === true).length;
    const totalClaimed = invocations.reduce((sum, item) => sum + positiveInt(asObject(item.payload).claimed_count, 0), 0);
    const totalCompleted = invocations.reduce((sum, item) => sum + positiveInt(asObject(item.payload).completed_count, 0), 0);
    const totalRetryWait = invocations.reduce((sum, item) => sum + positiveInt(asObject(item.payload).retry_wait_count, 0), 0);
    const totalFailedTerminal = invocations.reduce((sum, item) => sum + positiveInt(asObject(item.payload).failed_terminal_count, 0), 0);

    await captureMetrics(serviceClient, parallelTarget, batchSize, {
      request_id: requestId,
      source: body.source ?? "edge",
      due_job_count: dueJobCount,
      worker_invocation_count: parallelTarget,
      successful_invocations: okCount,
    });

    if (okCount === 0) {
      return jsonResponse({
        success: false,
        error: "Signup worker invocation failed.",
        error_code: "SIGNUP_WORKER_INVOCATION_FAILED",
        request_id: requestId,
        due_job_count: dueJobCount,
        configured_batch_size: batchSize,
        parallel_invocation_target: parallelTarget,
        invocations,
      }, 502);
    }

    return jsonResponse({
      success: true,
      request_id: requestId,
      due_job_count: dueJobCount,
      configured_batch_size: batchSize,
      parallel_invocation_target: parallelTarget,
      successful_invocations: okCount,
      claimed_count: totalClaimed,
      completed_count: totalCompleted,
      retry_wait_count: totalRetryWait,
      failed_terminal_count: totalFailedTerminal,
      invocations,
    });
  } catch (error) {
    logStructured("error", "identity_signup_orchestrator_failed", {
      request_id: requestId,
      duration_ms: Date.now() - startedAt,
      error: error instanceof Error ? error.message : String(error),
    });
    if (error instanceof EdgeHttpError) {
      return jsonResponse({ success: false, error: error.message, error_code: error.code, details: error.details }, error.status, error.headers);
    }
    return jsonResponse({ success: false, error: "Unable to orchestrate signup worker.", error_code: "INTERNAL_ERROR" }, 500);
  }
});