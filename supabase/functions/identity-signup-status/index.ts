import { z } from "npm:zod@3.23.8";

import { sha256Hex } from "../_shared/crypto.ts";
import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  jsonResponse,
  logStructured,
  readJsonBody,
} from "../_shared/http.ts";
import {
  callPlatformRpc,
  createServiceRoleClient,
  type JsonMap,
} from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 4 * 1024;

const StatusRequestSchema = z.object({
  request_id: z.string().uuid("Valid request_id is required"),
  status_token: z.string().min(32, "Valid status_token is required").max(256, "Invalid status_token"),
});

function asObject(value: unknown): JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as JsonMap)
    : {};
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function getFailureExplanation(decisionReason: string | null): string | null {
  switch (decisionReason) {
    case "AUTH_USER_EXISTS":
      return "An account with this email already exists. Please try signing in instead.";
    case "AUTH_WEAK_PASSWORD":
      return "The password did not meet security requirements. Please submit a fresh signup request with a stronger password.";
    case "AUTH_INVALID_EMAIL":
      return "The email address format is invalid. Please submit a fresh signup request with a valid email address.";
    case "AUTH_RATE_LIMIT":
      return "Too many signup attempts were detected. Please wait before submitting a fresh request.";
    case "INVITATION_EXPIRED":
      return "The invitation expired before signup could be completed. Please contact your administrator.";
    default:
      return "The signup request hit an issue and could not complete automatically. Please contact support.";
  }
}

function mapPublicStatus(details: JsonMap) {
  const requestStatus = asString(details.request_status)?.toLowerCase() ?? "received";
  const decisionReason = asString(details.decision_reason);

  if (requestStatus === "completed") {
    return {
      status: "completed",
      status_message: "Your account has been created successfully. You can now sign in.",
      next_steps: "Use your email and password to sign in.",
      last_error: null,
      last_error_code: null,
    };
  }

  if (requestStatus === "processing") {
    return {
      status: "processing",
      status_message: "Your account is being created right now.",
      next_steps: "Please check again shortly while the activation finishes.",
      last_error: null,
      last_error_code: null,
    };
  }

  if (requestStatus === "failed") {
    return {
      status: "failed",
      status_message: "Your signup request hit an issue and could not complete automatically.",
      next_steps: "Please contact support or submit a fresh signup request if advised.",
      last_error: getFailureExplanation(decisionReason),
      last_error_code: decisionReason,
    };
  }

  if (requestStatus === "denied") {
    if (decisionReason === "IP_RATE_LIMIT" || decisionReason === "IDENTITY_RATE_LIMIT") {
      return {
        status: "rate_limited",
        status_message: "This signup request was rate limited before account creation.",
        next_steps: "Please wait before submitting another signup request.",
        last_error: null,
        last_error_code: decisionReason,
      };
    }

    return {
      status: "unavailable",
      status_message: "This signup request could not be completed. Please contact your administrator.",
      next_steps: "Please verify the invitation details with your administrator and submit a fresh request if needed.",
      last_error: null,
      last_error_code: null,
    };
  }

  return {
    status: "pending",
    status_message: "Your signup request has been received and is waiting for processing.",
    next_steps: "Please check again shortly while the activation finishes.",
    last_error: null,
    last_error_code: null,
  };
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
    const payload = StatusRequestSchema.parse(body);
    const serviceClient = createServiceRoleClient();
    const statusTokenHash = await sha256Hex(payload.status_token);

    const statusResult = await callPlatformRpc(serviceClient, "platform_get_signup_request_status", {
      request_id: payload.request_id,
      status_token_hash: statusTokenHash,
    });

    if (!statusResult.success && statusResult.code === "SIGNUP_REQUEST_NOT_FOUND") {
      return jsonResponse({
        success: false,
        error: "No signup request found",
        error_code: "REQUEST_NOT_FOUND",
      }, 404);
    }

    if (!statusResult.success) {
      throw new EdgeHttpError(
        statusResult.message || "Unable to check signup status.",
        500,
        statusResult.code || "SIGNUP_STATUS_LOOKUP_FAILED",
        asObject(statusResult.details),
      );
    }

    const details = asObject(statusResult.details);
    const publicStatus = mapPublicStatus(details);

    return jsonResponse({
      success: true,
      request: {
        request_id: String(details.signup_request_id ?? payload.request_id),
        status: publicStatus.status,
        status_message: publicStatus.status_message,
        next_steps: publicStatus.next_steps,
        last_error: publicStatus.last_error,
        last_error_code: publicStatus.last_error_code,
        created_at: asString(details.created_at),
        updated_at: asString(details.updated_at),
        completed_at: asString(details.completed_at),
      },
      query_duration_ms: Date.now() - startedAt,
    });
  } catch (error) {
    logStructured("error", "identity_signup_status_failed", {
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
      error: "Unable to check signup status.",
      error_code: "INTERNAL_ERROR",
    }, 500);
  }
});
