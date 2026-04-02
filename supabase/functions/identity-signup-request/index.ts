import { z } from "npm:zod@3.23.8";

import { createOpaqueToken, encryptJsonPayload, sha256Hex } from "../_shared/crypto.ts";
import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  getClientMetadata,
  jsonResponse,
  logStructured,
  readJsonBody,
} from "../_shared/http.ts";
import { requirePlatformSuccess } from "../_shared/platform.ts";
import {
  callPlatformRpc,
  createServiceRoleClient,
  type JsonMap,
  type SupabaseClient,
} from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 8 * 1024;
const SIGNUP_IP_WINDOW_MINUTES = 15;
const SIGNUP_IP_MAX_REQUESTS = 10;
const SIGNUP_IDENTITY_WINDOW_MINUTES = 60;
const SIGNUP_IDENTITY_MAX_REQUESTS = 5;
const RATE_LIMIT_RETRY_AFTER_SECONDS = 15 * 60;

type SignupRequestBody = z.infer<typeof SignupRequestSchema>;

const SignupRequestSchema = z.object({
  email: z.string().email("Invalid email format").transform((value) => value.trim().toLowerCase()),
  password: z.string().min(8, "Password must be at least 8 characters").max(128, "Password is too long"),
  full_name: z.string().min(2, "Full name is required").max(200, "Full name is too long").transform((value) => value.trim()),
  mobile_no: z.string().transform((value) => value.replace(/\D/g, "")).refine((value) => /^\d{10,15}$/.test(value), "Valid mobile number required"),
  role_code: z.string().min(1).max(100).transform((value) => value.trim().toLowerCase()).optional(),
  invitation_role: z.string().min(1).max(100).transform((value) => value.trim().toLowerCase()).optional(),
});

function resolveRoleCode(payload: SignupRequestBody): string | undefined {
  return payload.role_code || payload.invitation_role || undefined;
}

function acceptedResponse(requestId: string, statusToken: string, rateLimited = false): Response {
  const payload = rateLimited
    ? {
      success: false,
      message: "Signup request rate limit reached. Please wait before trying again.",
      request_id: requestId,
      status_token: statusToken,
      status_check_endpoint: "/functions/v1/identity-signup-status",
      status_check_method: "POST",
      retry_after_seconds: RATE_LIMIT_RETRY_AFTER_SECONDS,
    }
    : {
      success: true,
      message: "If the invitation details are valid, your signup request is now being processed.",
      request_id: requestId,
      status_token: statusToken,
      status_check_endpoint: "/functions/v1/identity-signup-status",
      status_check_method: "POST",
    };

  return jsonResponse(
    payload,
    rateLimited ? 429 : 202,
    rateLimited ? { "Retry-After": String(RATE_LIMIT_RETRY_AFTER_SECONDS) } : undefined,
  );
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
    logStructured("warning", "best_effort_signup_status_update_failed", {
      signup_request_id: signupRequestId,
      request_status: requestStatus,
      decision_reason: decisionReason,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

async function createSignupRequestRecord(
  serviceClient: SupabaseClient,
  payload: SignupRequestBody,
  metadata: { sourceIp: string; userAgent: string },
): Promise<{ requestId: string; requestStatus: string; statusToken: string; decisionReason: string | null }> {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const statusToken = createOpaqueToken();
    const statusTokenHash = await sha256Hex(statusToken);
    const registerResult = await callPlatformRpc(serviceClient, "platform_register_signup_request", {
      email: payload.email,
      mobile_no: payload.mobile_no,
      role_code: resolveRoleCode(payload),
      status_token_hash: statusTokenHash,
      source_ip: metadata.sourceIp,
      user_agent: metadata.userAgent,
      metadata: {
        full_name: payload.full_name,
        request_origin: "identity-signup-request",
      },
    });

    if (!registerResult.success && registerResult.code === "STATUS_TOKEN_HASH_DUPLICATE") {
      continue;
    }

    const details = requirePlatformSuccess(
      registerResult,
      500,
      "SIGNUP_REQUEST_CREATE_FAILED",
      "Unable to register signup request.",
    );

    const requestId = String(details.signup_request_id ?? "").trim();
    const requestStatus = String(details.request_status ?? "").trim().toLowerCase();

    if (!requestId || !requestStatus) {
      throw new EdgeHttpError(
        "Signup request contract returned incomplete details.",
        500,
        "SIGNUP_REQUEST_CREATE_FAILED",
      );
    }

    return {
      requestId,
      requestStatus,
      statusToken,
      decisionReason: typeof details.decision_reason === "string" ? details.decision_reason : null,
    };
  }

  throw new EdgeHttpError(
    "Unable to register signup request.",
    500,
    "STATUS_TOKEN_GENERATION_FAILED",
  );
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  const requestId = createRequestId(req);
  const startedAt = Date.now();

  try {
    if (req.method !== "POST") {
      return jsonResponse({
        success: false,
        error: "Method not allowed. Use POST.",
        error_code: "METHOD_NOT_ALLOWED",
      }, 405);
    }

    const body = await readJsonBody(req, MAX_BODY_BYTES);
    const payload = SignupRequestSchema.parse(body);
    const metadata = getClientMetadata(req);
    const serviceClient = createServiceRoleClient();

    const rateLimitResult = await callPlatformRpc(serviceClient, "platform_check_signup_rate_limit", {
      source_ip: metadata.sourceIp,
      email: payload.email,
      mobile_no: payload.mobile_no,
      ip_window_minutes: SIGNUP_IP_WINDOW_MINUTES,
      ip_max_requests: SIGNUP_IP_MAX_REQUESTS,
      identity_window_minutes: SIGNUP_IDENTITY_WINDOW_MINUTES,
      identity_max_requests: SIGNUP_IDENTITY_MAX_REQUESTS,
    });

    const rateLimitDetails = requirePlatformSuccess(
      rateLimitResult,
      500,
      "SIGNUP_RATE_LIMIT_CHECK_FAILED",
      "Unable to validate signup request.",
    );

    const contractRecord = await createSignupRequestRecord(serviceClient, payload, metadata);

    if (rateLimitDetails.is_allowed !== true) {
      await bestEffortUpdateSignupRequestStatus(
        serviceClient,
        contractRecord.requestId,
        "denied",
        String(rateLimitDetails.decision_reason ?? "RATE_LIMITED"),
        {
          rate_limit_source: "identity-signup-request",
        },
      );

      logStructured("warning", "signup_rate_limited", {
        request_id: requestId,
        signup_request_id: contractRecord.requestId,
        source_ip: metadata.sourceIp,
        duration_ms: Date.now() - startedAt,
      });

      return acceptedResponse(contractRecord.requestId, contractRecord.statusToken, true);
    }

    if (contractRecord.requestStatus !== "received") {
      logStructured("info", "signup_denied_before_queue", {
        request_id: requestId,
        signup_request_id: contractRecord.requestId,
        request_status: contractRecord.requestStatus,
        decision_reason: contractRecord.decisionReason,
        duration_ms: Date.now() - startedAt,
      });

      return acceptedResponse(contractRecord.requestId, contractRecord.statusToken);
    }

    const encryptionSecret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() || "";
    if (!encryptionSecret) {
      throw new EdgeHttpError(
        "Signup runtime secret is unavailable.",
        500,
        "SIGNUP_SECRET_UNAVAILABLE",
      );
    }

    const encryptedCredentials = await encryptJsonPayload(encryptionSecret, {
      password: payload.password,
    });

    const enqueueResult = await callPlatformRpc(serviceClient, "platform_enqueue_signup_request", {
      signup_request_id: contractRecord.requestId,
      full_name: payload.full_name,
      role_code: resolveRoleCode(payload),
      encrypted_credentials: encryptedCredentials,
      priority: 100,
      max_attempts: 5,
    });

    if (!enqueueResult.success) {
      await bestEffortUpdateSignupRequestStatus(
        serviceClient,
        contractRecord.requestId,
        "failed",
        String(enqueueResult.code ?? "SIGNUP_ENQUEUE_FAILED"),
        {
          enqueue_error_message: enqueueResult.message ?? null,
        },
      );

      logStructured("warning", "signup_enqueue_failed", {
        request_id: requestId,
        signup_request_id: contractRecord.requestId,
        error_code: enqueueResult.code ?? "SIGNUP_ENQUEUE_FAILED",
        duration_ms: Date.now() - startedAt,
      });

      return acceptedResponse(contractRecord.requestId, contractRecord.statusToken);
    }

    logStructured("info", "signup_queued_for_async_processing", {
      request_id: requestId,
      signup_request_id: contractRecord.requestId,
      duration_ms: Date.now() - startedAt,
    });

    return acceptedResponse(contractRecord.requestId, contractRecord.statusToken);
  } catch (error) {
    logStructured("error", "identity_signup_request_failed", {
      request_id: requestId,
      duration_ms: Date.now() - startedAt,
      error: error instanceof Error ? error.message : String(error),
    });

    if (error instanceof EdgeHttpError) {
      return jsonResponse({
        success: false,
        error: error.message,
        error_code: error.code,
        details: error.details,
      }, error.status, error.headers);
    }

    if (error instanceof z.ZodError) {
      return jsonResponse({
        success: false,
        error: "Validation failed",
        error_code: "VALIDATION_ERROR",
        details: error.flatten().fieldErrors,
      }, 400);
    }

    return jsonResponse({
      success: false,
      error: "Unable to register signup request.",
      error_code: "INTERNAL_ERROR",
    }, 500);
  }
});
