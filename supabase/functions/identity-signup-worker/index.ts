import { asObject, CORS_HEADERS, createRequestId, EdgeHttpError, jsonResponse, logStructured, readJsonBody } from "../_shared/http.ts";
import { decryptJsonPayload } from "../_shared/crypto.ts";
import { requireServiceRoleAccess } from "../_shared/internal.ts";
import { callPlatformRpc, createServiceRoleClient, safeDeleteAuthUser, type JsonMap, type SupabaseClient } from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 8 * 1024;
const DEFAULT_BATCH_SIZE = 5;

type ClaimedJob = {
  job_id: string;
  tenant_id: string;
  worker_code: string;
  attempt_count: number;
  claimed_by_worker: string;
  payload: JsonMap;
};

function mapAuthCreateErrorCode(error: unknown): string {
  const code = String((error as { code?: string })?.code ?? "").trim().toUpperCase();
  const message = String((error as { message?: string })?.message ?? "").toUpperCase();
  if (code.includes("WEAK_PASSWORD") || message.includes("WEAK PASSWORD")) return "AUTH_WEAK_PASSWORD";
  if (code.includes("USER_ALREADY_EXISTS") || message.includes("ALREADY REGISTERED")) return "AUTH_USER_EXISTS";
  if (code.includes("EMAIL_ADDRESS_INVALID") || message.includes("INVALID EMAIL")) return "AUTH_INVALID_EMAIL";
  if (code.includes("OVER_REQUEST_RATE_LIMIT") || message.includes("RATE LIMIT")) return "AUTH_RATE_LIMIT";
  return code || "AUTH_CREATE_USER_FAILED";
}

function isTerminalAuthError(code: string): boolean {
  return ["AUTH_WEAK_PASSWORD", "AUTH_USER_EXISTS", "AUTH_INVALID_EMAIL"].includes(code);
}

function isTerminalCompletionCode(code: string): boolean {
  return [
    "INVITATION_NOT_FOUND",
    "INVITATION_NOT_PENDING",
    "INVITATION_EXPIRED",
    "INVITATION_IDENTITY_MISMATCH",
    "SIGNUP_REQUEST_NOT_FOUND",
    "SIGNUP_REQUEST_NOT_INVITED",
    "SIGNUP_REQUEST_NOT_COMPLETABLE",
  ].includes(code);
}

async function bestEffortUpdateSignupRequestStatus(
  serviceClient: SupabaseClient,
  signupRequestId: string,
  requestStatus: string,
  decisionReason: string,
  metadataPatch: JsonMap = {},
): Promise<void> {
  try {
    await callPlatformRpc(serviceClient, "platform_update_signup_request_status", {
      signup_request_id: signupRequestId,
      request_status: requestStatus,
      decision_reason: decisionReason,
      metadata_patch: metadataPatch,
    });
  } catch (error) {
    logStructured("warning", "i01_signup_worker_status_update_failed", {
      signup_request_id: signupRequestId,
      request_status: requestStatus,
      decision_reason: decisionReason,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

async function recordFailure(
  serviceClient: SupabaseClient,
  args: {
    jobId: string;
    claimedByWorker: string;
    signupRequestId: string;
    errorCode: string;
    errorMessage: string;
    metadataPatch: JsonMap;
    terminal: boolean;
  },
): Promise<void> {
  await bestEffortUpdateSignupRequestStatus(
    serviceClient,
    args.signupRequestId,
    args.terminal ? "failed" : "queued",
    args.errorCode,
    args.metadataPatch,
  );

  await callPlatformRpc(serviceClient, "platform_signup_circuit_breaker_record_failure", {
    error_code: args.errorCode,
    error_message: args.errorMessage,
  });

  await callPlatformRpc(serviceClient, "platform_async_fail_job", {
    job_id: args.jobId,
    claimed_by_worker: args.claimedByWorker,
    terminal: args.terminal,
    dead_letter: args.terminal,
    error_code: args.errorCode,
    error_message: args.errorMessage,
    error_details: args.metadataPatch,
  });
}

async function processClaimedJob(serviceClient: SupabaseClient, job: ClaimedJob): Promise<{ state: string; signupRequestId?: string }> {
  const payload = asObject(job.payload);
  const signupRequestId = String(payload.signup_request_id ?? "").trim();
  const email = String(payload.email ?? "").trim().toLowerCase();
  const mobileNo = String(payload.mobile_no ?? "").trim();
  const fullName = String(payload.full_name ?? "").trim();
  const encryptedCredentials = asObject(payload.encrypted_credentials);

  if (!signupRequestId || !email || !mobileNo || !fullName) {
    await recordFailure(serviceClient, {
      jobId: job.job_id,
      claimedByWorker: job.claimed_by_worker,
      signupRequestId,
      errorCode: "INVALID_SIGNUP_JOB_PAYLOAD",
      errorMessage: "Signup job payload is incomplete.",
      metadataPatch: { payload },
      terminal: true,
    });
    return { state: "failed_terminal", signupRequestId };
  }

  await callPlatformRpc(serviceClient, "platform_async_heartbeat_job", {
    job_id: job.job_id,
    claimed_by_worker: job.claimed_by_worker,
  });

  await bestEffortUpdateSignupRequestStatus(
    serviceClient,
    signupRequestId,
    "processing",
    "SIGNUP_PROCESSING_STARTED",
    { async_worker: "i01_signup_worker", async_job_id: job.job_id },
  );

  const encryptionSecret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() || "";
  if (!encryptionSecret) {
    await recordFailure(serviceClient, {
      jobId: job.job_id,
      claimedByWorker: job.claimed_by_worker,
      signupRequestId,
      errorCode: "SIGNUP_SECRET_UNAVAILABLE",
      errorMessage: "Signup worker secret is unavailable.",
      metadataPatch: {},
      terminal: false,
    });
    return { state: "retry_wait", signupRequestId };
  }

  let decrypted: JsonMap;
  try {
    decrypted = await decryptJsonPayload(encryptionSecret, {
      ciphertext: String(encryptedCredentials.ciphertext ?? ""),
      iv: String(encryptedCredentials.iv ?? ""),
    });
  } catch (error) {
    await recordFailure(serviceClient, {
      jobId: job.job_id,
      claimedByWorker: job.claimed_by_worker,
      signupRequestId,
      errorCode: "INVALID_ENCRYPTED_CREDENTIALS",
      errorMessage: error instanceof Error ? error.message : "Unable to decrypt signup credentials.",
      metadataPatch: {},
      terminal: true,
    });
    return { state: "failed_terminal", signupRequestId };
  }

  const password = String(decrypted.password ?? "").trim();
  if (!password) {
    await recordFailure(serviceClient, {
      jobId: job.job_id,
      claimedByWorker: job.claimed_by_worker,
      signupRequestId,
      errorCode: "INVALID_ENCRYPTED_CREDENTIALS",
      errorMessage: "Decrypted signup credentials are incomplete.",
      metadataPatch: {},
      terminal: true,
    });
    return { state: "failed_terminal", signupRequestId };
  }

  const createUserResult = await serviceClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: {
      display_name: fullName,
      primary_mobile: mobileNo,
    },
  });

  if (createUserResult.error || !createUserResult.data.user?.id) {
    const errorCode = mapAuthCreateErrorCode(createUserResult.error);
    const terminal = isTerminalAuthError(errorCode);
    await recordFailure(serviceClient, {
      jobId: job.job_id,
      claimedByWorker: job.claimed_by_worker,
      signupRequestId,
      errorCode,
      errorMessage: createUserResult.error?.message ?? "Unable to create auth user.",
      metadataPatch: { auth_error_message: createUserResult.error?.message ?? null },
      terminal,
    });
    return { state: terminal ? "failed_terminal" : "retry_wait", signupRequestId };
  }

  const authUserId = createUserResult.data.user.id;
  const completionResult = await callPlatformRpc(serviceClient, "platform_complete_invited_signup", {
    signup_request_id: signupRequestId,
    actor_user_id: authUserId,
    email,
    mobile_no: mobileNo,
    display_name: fullName,
  });

  if (!completionResult.success) {
    const cleanupSucceeded = await safeDeleteAuthUser(serviceClient, authUserId);
    const errorCode = String(completionResult.code ?? "SIGNUP_COMPLETION_FAILED").trim();
    const terminal = isTerminalCompletionCode(errorCode) || !cleanupSucceeded;
    await recordFailure(serviceClient, {
      jobId: job.job_id,
      claimedByWorker: job.claimed_by_worker,
      signupRequestId,
      errorCode,
      errorMessage: String(completionResult.message ?? "Unable to complete invited signup."),
      metadataPatch: {
        auth_user_cleanup_attempted: true,
        auth_user_cleanup_succeeded: cleanupSucceeded,
      },
      terminal,
    });
    return { state: terminal ? "failed_terminal" : "retry_wait", signupRequestId };
  }

  await callPlatformRpc(serviceClient, "platform_signup_circuit_breaker_record_success", {});
  await callPlatformRpc(serviceClient, "platform_async_complete_job", {
    job_id: job.job_id,
    claimed_by_worker: job.claimed_by_worker,
    result_summary: {
      signup_request_id: signupRequestId,
      actor_user_id: authUserId,
      outcome: "completed",
    },
  });

  return { state: "completed", signupRequestId };
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
    const batchSize = Math.max(1, Number(body.batch_size ?? DEFAULT_BATCH_SIZE));
    const serviceClient = createServiceRoleClient();
    const breaker = await callPlatformRpc(serviceClient, "platform_signup_circuit_breaker_check", {});
    const breakerDetails = asObject(breaker.details);
    if (breaker.success !== true || breakerDetails.is_allowed !== true) {
      await callPlatformRpc(serviceClient, "platform_capture_signup_metrics", {
        parallel_invocation_target: 1,
        configured_batch_size: batchSize,
        metadata: { blocked: true, request_id: requestId },
      });
      return jsonResponse({ success: true, blocked: true, breaker: breakerDetails, request_id: requestId });
    }

    const claimResult = await callPlatformRpc(serviceClient, "platform_async_claim_jobs", {
      worker_code: "i01_signup_worker",
      batch_size: batchSize,
      claimed_by_worker: `identity-signup-worker:${requestId}`,
    });
    const claimDetails = asObject(claimResult.details);
    const jobs = Array.isArray(claimDetails.jobs) ? claimDetails.jobs as JsonMap[] : [];

    let completed = 0;
    let retryWait = 0;
    let failedTerminal = 0;

    for (const rawJob of jobs) {
      const job = {
        job_id: String(rawJob.job_id ?? ""),
        tenant_id: String(rawJob.tenant_id ?? ""),
        worker_code: String(rawJob.worker_code ?? ""),
        attempt_count: Number(rawJob.attempt_count ?? 0),
        claimed_by_worker: String(rawJob.claimed_by_worker ?? `identity-signup-worker:${requestId}`),
        payload: asObject(rawJob.payload),
      };
      const outcome = await processClaimedJob(serviceClient, job);
      if (outcome.state === "completed") completed += 1;
      else if (outcome.state === "retry_wait") retryWait += 1;
      else failedTerminal += 1;
    }

    await callPlatformRpc(serviceClient, "platform_capture_signup_metrics", {
      parallel_invocation_target: 1,
      configured_batch_size: batchSize,
      metadata: {
        completed,
        retry_wait: retryWait,
        failed_terminal: failedTerminal,
        request_id: requestId,
      },
    });

    return jsonResponse({
      success: true,
      request_id: requestId,
      claimed_count: jobs.length,
      completed_count: completed,
      retry_wait_count: retryWait,
      failed_terminal_count: failedTerminal,
    });
  } catch (error) {
    logStructured("error", "identity_signup_worker_failed", {
      request_id: requestId,
      duration_ms: Date.now() - startedAt,
      error: error instanceof Error ? error.message : String(error),
    });
    if (error instanceof EdgeHttpError) {
      return jsonResponse({ success: false, error: error.message, error_code: error.code, details: error.details }, error.status, error.headers);
    }
    return jsonResponse({ success: false, error: "Unable to process signup worker.", error_code: "INTERNAL_ERROR" }, 500);
  }
});
