import { z } from "npm:zod@3.23.8";

import { createOpaqueToken, sha256Hex } from "../_shared/crypto.ts";
import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  getClientMetadata,
  jsonResponse,
  logStructured,
  readJsonBody,
} from "../_shared/http.ts";
import {
  parseAccessContext,
  parseSigninPolicy,
  requirePlatformSuccess,
  selectAllowedMembership,
} from "../_shared/platform.ts";
import {
  callPlatformRpc,
  createAnonClient,
  createServiceRoleClient,
  type JsonMap,
  type SupabaseClient,
} from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 8 * 1024;
const SIGNIN_WINDOW_MINUTES = 15;
const SIGNIN_MAX_ATTEMPTS_EMAIL = 5;
const SIGNIN_MAX_ATTEMPTS_IP = 20;

const PasswordStageSchema = z.object({
  email: z.string().email("Valid email is required").transform((value) => value.trim().toLowerCase()),
  password: z.string().min(1, "Password is required").max(128, "Password is too long"),
  policy_code: z.string().min(1).max(100).transform((value) => value.trim().toLowerCase()).optional(),
  configId: z.string().min(1).max(100).transform((value) => value.trim().toLowerCase()).optional(),
  tenant_id: z.string().uuid("tenant_id must be a UUID").optional(),
}).refine((value) => Boolean(value.policy_code || value.configId), {
  message: "policy_code or configId is required",
  path: ["policy_code"],
});

const OtpStageSchema = z.object({
  otp: z.string().min(4, "OTP is required").max(12, "Invalid OTP"),
  challenge_token: z.string().min(24, "challenge_token is required").max(256).optional(),
  state_token: z.string().min(24, "state_token is required").max(256).optional(),
}).refine((value) => Boolean(value.challenge_token || value.state_token), {
  message: "challenge_token or state_token is required",
  path: ["challenge_token"],
});

type PasswordStageBody = z.infer<typeof PasswordStageSchema>;
type OtpStageBody = z.infer<typeof OtpStageSchema>;

function resolvePolicyCode(payload: PasswordStageBody): string {
  return (payload.policy_code || payload.configId || "").trim().toLowerCase();
}

function mapOtpDispatchError(error: unknown): { status: number; code: string; message: string } {
  const code = String((error as { code?: string })?.code ?? "").trim().toUpperCase();
  const message = String((error as { message?: string })?.message ?? "").trim().toUpperCase();

  if (code.includes("RATE_LIMIT") || message.includes("RATE LIMIT")) {
    return {
      status: 429,
      code: "OTP_RATE_LIMITED",
      message: "Too many one-time code requests. Please wait before trying again.",
    };
  }

  if (code.includes("EMAIL_ADDRESS_INVALID") || (message.includes("EMAIL ADDRESS") && message.includes("INVALID"))) {
    return {
      status: 400,
      code: "OTP_DELIVERY_UNAVAILABLE",
      message: "A one-time code cannot be sent to this email address. Contact support.",
    };
  }

  return {
    status: 502,
    code: "OTP_DISPATCH_FAILED",
    message: "Could not initiate sign-in.",
  };
}

async function recordSigninAttempt(
  serviceClient: SupabaseClient,
  args: {
    email: string;
    sourceIp: string;
    policyCode: string;
    attemptResult: string;
    actorUserId?: string;
    metadata?: JsonMap;
  },
): Promise<void> {
  const requests: Promise<unknown>[] = [
    callPlatformRpc(serviceClient, "platform_record_signin_attempt", {
      identifier: args.email,
      identifier_type: "email",
      policy_code: args.policyCode,
      attempt_result: args.attemptResult,
      source_ip: args.sourceIp,
      actor_user_id: args.actorUserId,
      metadata: args.metadata ?? {},
    }),
  ];

  if (args.sourceIp && args.sourceIp !== "unknown") {
    requests.push(callPlatformRpc(serviceClient, "platform_record_signin_attempt", {
      identifier: args.sourceIp,
      identifier_type: "ip",
      policy_code: args.policyCode,
      attempt_result: args.attemptResult,
      source_ip: args.sourceIp,
      actor_user_id: args.actorUserId,
      metadata: args.metadata ?? {},
    }));
  }

  await Promise.allSettled(requests);
}

async function enforceSigninRateLimit(
  serviceClient: SupabaseClient,
  email: string,
  sourceIp: string,
  policyCode: string,
): Promise<void> {
  const emailResult = requirePlatformSuccess(
    await callPlatformRpc(serviceClient, "platform_check_signin_rate_limit", {
      identifier: email,
      identifier_type: "email",
      window_minutes: SIGNIN_WINDOW_MINUTES,
      max_attempts: SIGNIN_MAX_ATTEMPTS_EMAIL,
    }),
    500,
    "SIGNIN_RATE_LIMIT_CHECK_FAILED",
    "Unable to validate sign-in request.",
  );

  if (emailResult.is_allowed !== true) {
    await recordSigninAttempt(serviceClient, {
      email,
      sourceIp,
      policyCode,
      attemptResult: "failed_rate_limit",
    });
    throw new EdgeHttpError(
      "Too many login attempts. Please try again later.",
      429,
      "SIGNIN_RATE_LIMITED",
    );
  }

  if (sourceIp && sourceIp !== "unknown") {
    const ipResult = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_check_signin_rate_limit", {
        identifier: sourceIp,
        identifier_type: "ip",
        window_minutes: SIGNIN_WINDOW_MINUTES,
        max_attempts: SIGNIN_MAX_ATTEMPTS_IP,
      }),
      500,
      "SIGNIN_RATE_LIMIT_CHECK_FAILED",
      "Unable to validate sign-in request.",
    );

    if (ipResult.is_allowed !== true) {
      await recordSigninAttempt(serviceClient, {
        email,
        sourceIp,
        policyCode,
        attemptResult: "failed_rate_limit",
      });
      throw new EdgeHttpError(
        "Too many requests from your location. Please try again later.",
        429,
        "SIGNIN_RATE_LIMITED",
      );
    }
  }
}

async function handlePasswordStage(
  req: Request,
  body: unknown,
  requestId: string,
  startedAt: number,
): Promise<Response> {
  const payload = PasswordStageSchema.parse(body);
  const policyCode = resolvePolicyCode(payload);
  const metadata = getClientMetadata(req);
  const serviceClient = createServiceRoleClient();
  const anonClient = createAnonClient();

  await enforceSigninRateLimit(serviceClient, payload.email, metadata.sourceIp, policyCode);

  const policyResult = await callPlatformRpc(serviceClient, "platform_get_signin_policy", {
    policy_code: policyCode,
  });
  if (!policyResult.success) {
    await recordSigninAttempt(serviceClient, {
      email: payload.email,
      sourceIp: metadata.sourceIp,
      policyCode,
      attemptResult: "failed_policy",
    });
    return jsonResponse({
      success: false,
      error: "Invalid credentials.",
      error_code: "INVALID_CREDENTIALS",
    }, 401);
  }

  const policy = parseSigninPolicy(requirePlatformSuccess(
    policyResult,
    500,
    "SIGNIN_POLICY_LOOKUP_FAILED",
    "Unable to validate sign-in request.",
  ));

  const signInResult = await anonClient.auth.signInWithPassword({
    email: payload.email,
    password: payload.password,
  });

  if (signInResult.error || !signInResult.data.user?.id) {
    await recordSigninAttempt(serviceClient, {
      email: payload.email,
      sourceIp: metadata.sourceIp,
      policyCode,
      attemptResult: "failed_credentials",
    });

    return jsonResponse({
      success: false,
      error: "Invalid credentials.",
      error_code: "INVALID_CREDENTIALS",
    }, 401);
  }

  const actorUserId = signInResult.data.user.id;
  const accessContext = parseAccessContext(requirePlatformSuccess(
    await callPlatformRpc(serviceClient, "platform_get_actor_access_context", {
      actor_user_id: actorUserId,
    }),
    500,
    "SIGNIN_ACCESS_CONTEXT_FAILED",
    "Unable to resolve sign-in access context.",
  ));

  const selectedMembership = selectAllowedMembership(accessContext, policy, payload.tenant_id);
  if (!selectedMembership) {
    await recordSigninAttempt(serviceClient, {
      email: payload.email,
      sourceIp: metadata.sourceIp,
      policyCode,
      actorUserId,
      attemptResult: "failed_policy",
    });

    return jsonResponse({
      success: false,
      error: "Access is not available for this account.",
      error_code: "ACCESS_NOT_AVAILABLE",
    }, 403);
  }

  if (policy.requires_otp) {
    const otpResult = await anonClient.auth.signInWithOtp({
      email: payload.email,
      options: {
        shouldCreateUser: false,
      },
    });

    if (otpResult.error) {
      const otpDispatchFailure = mapOtpDispatchError(otpResult.error);

      await recordSigninAttempt(serviceClient, {
        email: payload.email,
        sourceIp: metadata.sourceIp,
        policyCode,
        actorUserId,
        attemptResult: "failed_otp",
        metadata: {
          auth_error_code: otpResult.error.code ?? null,
          auth_error_message: otpResult.error.message ?? null,
        },
      });

      throw new EdgeHttpError(
        otpDispatchFailure.message,
        otpDispatchFailure.status,
        otpDispatchFailure.code,
        {
          auth_error_code: otpResult.error.code ?? null,
          auth_error_message: otpResult.error.message ?? null,
        },
      );
    }

    const challengeToken = createOpaqueToken();
    const challengeTokenHash = await sha256Hex(challengeToken);
    const challengeDetails = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_issue_signin_challenge", {
        actor_user_id: actorUserId,
        policy_code: policy.policy_code,
        challenge_token_hash: challengeTokenHash,
        source_ip: metadata.sourceIp,
        metadata: {
          selected_tenant_id: selectedMembership.tenant_id,
          selected_tenant_code: selectedMembership.tenant_code,
          selected_role_codes: selectedMembership.active_role_codes,
        },
      }),
      500,
      "SIGNIN_CHALLENGE_CREATE_FAILED",
      "Unable to initiate sign-in.",
    );

    await recordSigninAttempt(serviceClient, {
      email: payload.email,
      sourceIp: metadata.sourceIp,
      policyCode,
      actorUserId,
      attemptResult: "allowed",
    });

    logStructured("info", "signin_password_stage_passed", {
      request_id: requestId,
      actor_user_id: actorUserId,
      tenant_id: selectedMembership.tenant_id,
      requires_otp: true,
      duration_ms: Date.now() - startedAt,
    });

    return jsonResponse({
      success: true,
      status: "otp_sent",
      challenge_token: challengeToken,
      state_token: challengeToken,
      expires_at: challengeDetails.expires_at ?? null,
      policy_code: policy.policy_code,
      tenant: {
        tenant_id: selectedMembership.tenant_id,
        tenant_code: selectedMembership.tenant_code,
      },
    });
  }

  if (!signInResult.data.session) {
    throw new EdgeHttpError(
      "Could not complete sign-in.",
      500,
      "SIGNIN_SESSION_MISSING",
    );
  }

  await recordSigninAttempt(serviceClient, {
    email: payload.email,
    sourceIp: metadata.sourceIp,
    policyCode,
    actorUserId,
    attemptResult: "succeeded",
  });

  requirePlatformSuccess(
    await callPlatformRpc(serviceClient, "platform_mark_actor_signin_success", {
      tenant_id: selectedMembership.tenant_id,
      actor_user_id: actorUserId,
    }),
    500,
    "SIGNIN_SUCCESS_MARK_FAILED",
    "Unable to finalize sign-in.",
  );

  logStructured("info", "signin_completed_without_otp", {
    request_id: requestId,
    actor_user_id: actorUserId,
    tenant_id: selectedMembership.tenant_id,
    duration_ms: Date.now() - startedAt,
  });

  return jsonResponse({
    success: true,
    session: signInResult.data.session,
    user: signInResult.data.user,
    policy_code: policy.policy_code,
    selected_tenant: {
      tenant_id: selectedMembership.tenant_id,
      tenant_code: selectedMembership.tenant_code,
    },
    access_context: accessContext,
  });
}

async function handleOtpStage(
  req: Request,
  body: unknown,
  requestId: string,
  startedAt: number,
): Promise<Response> {
  const payload = OtpStageSchema.parse(body);
  const challengeToken = payload.challenge_token || payload.state_token || "";
  const challengeTokenHash = await sha256Hex(challengeToken);
  const metadata = getClientMetadata(req);
  const serviceClient = createServiceRoleClient();
  const anonClient = createAnonClient();

  const challengeResult = await callPlatformRpc(serviceClient, "platform_consume_signin_challenge", {
    challenge_token_hash: challengeTokenHash,
  });

  if (!challengeResult.success) {
    return jsonResponse({
      success: false,
      error: "Invalid or expired code. Please try again.",
      error_code: "INVALID_OTP_CHALLENGE",
    }, 400);
  }

  const challengeDetails = requirePlatformSuccess(
    challengeResult,
    500,
    "SIGNIN_CHALLENGE_LOOKUP_FAILED",
    "Unable to validate sign-in request.",
  );

  const actorUserId = String(challengeDetails.actor_user_id ?? "").trim();
  const policyCode = String(challengeDetails.policy_code ?? "").trim().toLowerCase();
  if (!actorUserId || !policyCode) {
    throw new EdgeHttpError(
      "Challenge contract returned incomplete details.",
      500,
      "SIGNIN_CHALLENGE_LOOKUP_FAILED",
    );
  }

  const authUserResult = await serviceClient.auth.admin.getUserById(actorUserId);
  if (authUserResult.error || !authUserResult.data.user?.email) {
    throw new EdgeHttpError(
      "Unable to resolve sign-in identity.",
      500,
      "SIGNIN_ACTOR_LOOKUP_FAILED",
    );
  }

  const email = authUserResult.data.user.email.toLowerCase();
  const verifyResult = await anonClient.auth.verifyOtp({
    email,
    token: payload.otp,
    type: "email",
  });

  if (verifyResult.error || !verifyResult.data.user?.id || !verifyResult.data.session) {
    await recordSigninAttempt(serviceClient, {
      email,
      sourceIp: metadata.sourceIp,
      policyCode,
      actorUserId,
      attemptResult: "failed_otp",
    });

    return jsonResponse({
      success: false,
      error: "Invalid or expired code. Please try again.",
      error_code: "INVALID_OTP",
    }, 401);
  }

  const policy = parseSigninPolicy(requirePlatformSuccess(
    await callPlatformRpc(serviceClient, "platform_get_signin_policy", {
      policy_code: policyCode,
    }),
    500,
    "SIGNIN_POLICY_LOOKUP_FAILED",
    "Unable to validate sign-in request.",
  ));

  const accessContext = parseAccessContext(requirePlatformSuccess(
    await callPlatformRpc(serviceClient, "platform_get_actor_access_context", {
      actor_user_id: actorUserId,
    }),
    500,
    "SIGNIN_ACCESS_CONTEXT_FAILED",
    "Unable to resolve sign-in access context.",
  ));

  const challengeMetadata = typeof challengeDetails.metadata === "object" && challengeDetails.metadata !== null
    ? (challengeDetails.metadata as JsonMap)
    : {};
  const selectedMembership = selectAllowedMembership(
    accessContext,
    policy,
    typeof challengeMetadata.selected_tenant_id === "string" ? challengeMetadata.selected_tenant_id : undefined,
  );

  if (!selectedMembership) {
    await recordSigninAttempt(serviceClient, {
      email,
      sourceIp: metadata.sourceIp,
      policyCode,
      actorUserId,
      attemptResult: "failed_policy",
    });

    return jsonResponse({
      success: false,
      error: "Access is not available for this account.",
      error_code: "ACCESS_NOT_AVAILABLE",
    }, 403);
  }

  await recordSigninAttempt(serviceClient, {
    email,
    sourceIp: metadata.sourceIp,
    policyCode,
    actorUserId,
    attemptResult: "succeeded",
  });

  requirePlatformSuccess(
    await callPlatformRpc(serviceClient, "platform_mark_actor_signin_success", {
      tenant_id: selectedMembership.tenant_id,
      actor_user_id: actorUserId,
    }),
    500,
    "SIGNIN_SUCCESS_MARK_FAILED",
    "Unable to finalize sign-in.",
  );

  logStructured("info", "signin_completed_with_otp", {
    request_id: requestId,
    actor_user_id: actorUserId,
    tenant_id: selectedMembership.tenant_id,
    duration_ms: Date.now() - startedAt,
  });

  return jsonResponse({
    success: true,
    session: verifyResult.data.session,
    user: verifyResult.data.user,
    policy_code: policy.policy_code,
    selected_tenant: {
      tenant_id: selectedMembership.tenant_id,
      tenant_code: selectedMembership.tenant_code,
    },
    access_context: accessContext,
  });
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
    const isOtpStage =
      typeof body === "object" &&
      body !== null &&
      ("otp" in body || "challenge_token" in body || "state_token" in body);

    return isOtpStage
      ? await handleOtpStage(req, body, requestId, startedAt)
      : await handlePasswordStage(req, body, requestId, startedAt);
  } catch (error) {
    logStructured("error", "identity_signin_failed", {
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
      error: "Unable to complete sign-in.",
      error_code: "INTERNAL_ERROR",
    }, 500);
  }
});
