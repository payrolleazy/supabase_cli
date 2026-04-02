import { z } from "zod";

import { createOrUpdateOwnerIdentity } from "../_shared_i02/auth.ts";
import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  jsonResponse,
  logStructured,
  readJsonBody,
} from "../_shared_i02/http.ts";
import {
  credentialSetupRoute,
  getOwnerBootstrapContext,
  getProvisionState,
  lookupBootstrapTokenState,
  requirePlatformSuccess,
} from "../_shared_i02/platform.ts";
import {
  callPlatformRpc,
  createServiceRoleClient,
} from "../_shared_i02/supabase.ts";

const MAX_BODY_BYTES = 12 * 1024;

const CompleteCredentialSetupSchema = z.object({
  action: z.literal("complete_credential_setup"),
  credential_setup_token: z.string().min(24).max(256),
  password: z.string().min(8).max(128),
  display_name: z.string().min(2).max(200).transform((value) => value.trim()).optional(),
  primary_mobile: z.string().max(30).transform((value) => value.trim()).optional(),
  provision_request_id: z.string().uuid().optional(),
});

type CompleteCredentialSetupBody = z.infer<typeof CompleteCredentialSetupSchema>;

function readyForSigninResponse(args: {
  provisionRequestId: string;
  tenantId: string | null;
  actorUserId: string | null;
  recoveredReplay?: boolean;
  identityCreated?: boolean;
  identityRecovered?: boolean;
}) {
  return jsonResponse({
    success: true,
    action: "complete_credential_setup",
    provision: {
      provision_request_id: args.provisionRequestId,
      provisioning_status: "ready_for_signin",
      next_action: "signin",
      tenant_id: args.tenantId,
      owner_actor_user_id: args.actorUserId,
    },
    signin: {
      route: "/signin",
      endpoint: "/functions/v1/identity-signin",
      credential_setup_route: credentialSetupRoute(),
    },
    metadata: {
      idempotent_replay: args.recoveredReplay === true,
      identity_created: args.identityCreated === true,
      identity_recovered: args.identityRecovered === true,
    },
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
    const payload = CompleteCredentialSetupSchema.parse(body);
    const serviceClient = createServiceRoleClient();

    let bootstrapContext;
    try {
      bootstrapContext = await getOwnerBootstrapContext(
        serviceClient,
        payload.credential_setup_token,
        "credential_setup",
      );
    } catch (error) {
      if (
        error instanceof EdgeHttpError &&
        (error.code === "TOKEN_NOT_ACTIVE" || error.code === "BOOTSTRAP_CONTEXT_UNAVAILABLE")
      ) {
        const tokenState = await lookupBootstrapTokenState(serviceClient, payload.credential_setup_token);
        if (tokenState) {
          const state = await getProvisionState(serviceClient, {
            provision_request_id: tokenState.provision_request_id,
          });

          if (state.provisioning_status === "ready_for_signin") {
            return readyForSigninResponse({
              provisionRequestId: state.provision_request_id,
              tenantId: state.tenant_id,
              actorUserId: state.owner_actor_user_id,
              recoveredReplay: true,
            });
          }
        }
      }

      throw error;
    }

    if (
      payload.provision_request_id &&
      payload.provision_request_id !== bootstrapContext.provision_request_id
    ) {
      throw new EdgeHttpError(
        "credential_setup_token does not match the provision request.",
        409,
        "TOKEN_CONTEXT_MISMATCH",
        {
          token_provision_request_id: bootstrapContext.provision_request_id,
          request_provision_request_id: payload.provision_request_id,
        },
      );
    }

    let provisionState = await getProvisionState(serviceClient, {
      provision_request_id: bootstrapContext.provision_request_id,
    });

    if (provisionState.provisioning_status === "ready_for_signin") {
      return readyForSigninResponse({
        provisionRequestId: provisionState.provision_request_id,
        tenantId: provisionState.tenant_id,
        actorUserId: provisionState.owner_actor_user_id,
        recoveredReplay: true,
      });
    }

    const identityResult = await createOrUpdateOwnerIdentity(serviceClient, {
      existingActorUserId: bootstrapContext.owner_actor_user_id,
      email: bootstrapContext.primary_work_email,
      password: payload.password,
      displayName: payload.display_name || provisionState.primary_contact_name || bootstrapContext.company_name,
      primaryMobile: payload.primary_mobile || provisionState.primary_mobile,
      provisionRequestId: bootstrapContext.provision_request_id,
    });

    requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_mark_client_identity_created", {
        provision_request_id: bootstrapContext.provision_request_id,
        actor_user_id: identityResult.actorUserId,
        primary_email: bootstrapContext.primary_work_email,
        primary_mobile: payload.primary_mobile || provisionState.primary_mobile,
        display_name: payload.display_name || provisionState.primary_contact_name || bootstrapContext.company_name,
        email_verified: true,
      }),
      409,
      "IDENTITY_MARK_FAILED",
      "Unable to mark the owner identity as created.",
    );

    requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_bootstrap_client_tenant_header", {
        provision_request_id: bootstrapContext.provision_request_id,
      }),
      409,
      "TENANT_BOOTSTRAP_FAILED",
      "Unable to bootstrap the client tenant.",
    );

    requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_bind_client_owner_admin", {
        provision_request_id: bootstrapContext.provision_request_id,
        actor_user_id: identityResult.actorUserId,
        primary_email: bootstrapContext.primary_work_email,
        primary_mobile: payload.primary_mobile || provisionState.primary_mobile,
        display_name: payload.display_name || provisionState.primary_contact_name || bootstrapContext.company_name,
      }),
      409,
      "OWNER_BIND_FAILED",
      "Unable to bind the owner admin access.",
    );

    requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_seed_client_commercial_state", {
        provision_request_id: bootstrapContext.provision_request_id,
      }),
      409,
      "COMMERCIAL_SEED_FAILED",
      "Unable to seed the client commercial baseline.",
    );

    requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_seed_client_owner_setup_state", {
        provision_request_id: bootstrapContext.provision_request_id,
      }),
      409,
      "OWNER_SETUP_SEED_FAILED",
      "Unable to finalize the owner setup state.",
    );

    requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_consume_owner_bootstrap_token", {
        token: payload.credential_setup_token,
        token_purpose: "credential_setup",
        consumed_by_user_id: identityResult.actorUserId,
      }),
      409,
      "CREDENTIAL_TOKEN_CONSUME_FAILED",
      "Unable to finalize the credential setup token.",
    );

    provisionState = await getProvisionState(serviceClient, {
      provision_request_id: bootstrapContext.provision_request_id,
    });

    if (provisionState.provisioning_status !== "ready_for_signin") {
      throw new EdgeHttpError(
        "Credential bootstrap did not reach ready_for_signin.",
        409,
        "BOOTSTRAP_NOT_FINALIZED",
        {
          provisioning_status: provisionState.provisioning_status,
          next_action: provisionState.next_action,
        },
      );
    }

    logStructured("info", "client_owner_credential_bootstrap_completed", {
      request_id: requestId,
      provision_request_id: bootstrapContext.provision_request_id,
      actor_user_id: identityResult.actorUserId,
      tenant_id: provisionState.tenant_id,
      duration_ms: Date.now() - startedAt,
    });

    return readyForSigninResponse({
      provisionRequestId: provisionState.provision_request_id,
      tenantId: provisionState.tenant_id,
      actorUserId: identityResult.actorUserId,
      identityCreated: identityResult.created,
      identityRecovered: identityResult.recovered,
    });
  } catch (error) {
    logStructured("error", "client_owner_credential_bootstrap_failed", {
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
      error: "Unable to complete the owner credential bootstrap.",
      error_code: "INTERNAL_ERROR",
    }, 500);
  }
});

