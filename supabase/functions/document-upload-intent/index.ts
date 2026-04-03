import { z } from "npm:zod@3.23.8";

import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  getClientMetadata,
  jsonResponse,
  logStructured,
  readJsonBody,
  requireBearerToken,
} from "../_shared_i05/http.ts";
import {
  asObject,
  parseUploadIntentDescriptor,
  requirePlatformSuccess,
} from "../_shared_i05/platform.ts";
import {
  callPlatformRpc,
  createServiceRoleClient,
  createUserClient,
  type JsonMap,
} from "../_shared_i05/supabase.ts";

const MAX_BODY_BYTES = 16 * 1024;

const IssueUploadIntentSchema = z.object({
  tenant_id: z.string().uuid().optional(),
  tenant_code: z.string().min(1).max(100).transform((value) => value.trim().toLowerCase()).optional(),
  document_class_code: z.string().min(1).max(120).transform((value) => value.trim().toLowerCase()),
  owner_actor_user_id: z.string().uuid().optional(),
  original_file_name: z.string().min(1).max(255).transform((value) => value.trim()),
  content_type: z.string().min(1).max(200).transform((value) => value.trim().toLowerCase()),
  expected_size_bytes: z.number().int().positive().max(100 * 1024 * 1024).optional(),
  binding_target_entity_code: z.string().min(1).max(120).transform((value) => value.trim().toLowerCase()).optional(),
  binding_target_key: z.string().min(1).max(200).transform((value) => value.trim()).optional(),
  binding_relation_purpose: z.string().min(1).max(120).transform((value) => value.trim().toLowerCase()).optional(),
  expires_in_seconds: z.number().int().min(60).max(86400).optional(),
  metadata: z.record(z.string(), z.unknown()).default({}),
}).strict().refine((value) => Boolean(value.tenant_id || value.tenant_code), {
  message: "tenant_id or tenant_code is required",
  path: ["tenant_id"],
}).refine((value) =>
  (value.binding_target_entity_code && value.binding_target_key)
  || (!value.binding_target_entity_code && !value.binding_target_key), {
    message: "binding_target_entity_code and binding_target_key must be provided together",
    path: ["binding_target_entity_code"],
  });

type IssueUploadIntentBody = z.infer<typeof IssueUploadIntentSchema>;

function buildRpcPayload(
  body: IssueUploadIntentBody,
  actorUserId: string,
  requestId: string,
  req: Request,
): JsonMap {
  const client = getClientMetadata(req);
  return {
    tenant_id: body.tenant_id ?? null,
    tenant_code: body.tenant_code ?? null,
    document_class_code: body.document_class_code,
    requested_by_actor_user_id: actorUserId,
    owner_actor_user_id: body.owner_actor_user_id ?? actorUserId,
    original_file_name: body.original_file_name,
    content_type: body.content_type,
    expected_size_bytes: body.expected_size_bytes ?? null,
    binding_target_entity_code: body.binding_target_entity_code ?? null,
    binding_target_key: body.binding_target_key ?? null,
    binding_relation_purpose: body.binding_relation_purpose ?? null,
    expires_in_seconds: body.expires_in_seconds ?? null,
    metadata: {
      ...body.metadata,
      source: "document-upload-intent",
      request_id: requestId,
      source_ip: client.sourceIp,
      user_agent: client.userAgent,
    },
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  const requestId = createRequestId(req);
  const startedAt = Date.now();

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    if (req.method !== "POST") {
      throw new EdgeHttpError("Method not allowed.", 405, "METHOD_NOT_ALLOWED");
    }

    const accessToken = requireBearerToken(req);
    const body = IssueUploadIntentSchema.parse(await readJsonBody(req, MAX_BODY_BYTES));
    const userClient = createUserClient(accessToken);
    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData.user) {
      throw new EdgeHttpError("Authenticated user context is not available.", 401, "INVALID_JWT");
    }

    const serviceClient = createServiceRoleClient();
    const details = requirePlatformSuccess(
      await callPlatformRpc(
        serviceClient,
        "platform_issue_document_upload_intent",
        buildRpcPayload(body, userData.user.id, requestId, req),
      ),
      "DOCUMENT_UPLOAD_INTENT_FAILED",
      "Unable to issue document upload intent.",
    );
    const uploadIntent = parseUploadIntentDescriptor(details);

    const storageApi = serviceClient.storage.from(uploadIntent.bucketName) as any;
    const { data: signedUploadData, error: signedUploadError } = await storageApi.createSignedUploadUrl(
      uploadIntent.storageObjectName,
    );

    if (signedUploadError) {
      throw new EdgeHttpError(
        "Unable to issue signed upload target.",
        502,
        "SIGNED_UPLOAD_URL_FAILED",
        { bucket_name: uploadIntent.bucketName, storage_object_name: uploadIntent.storageObjectName },
      );
    }

    const signedUploadInfo = asObject(signedUploadData);

    logStructured("info", "document-upload-intent completed", {
      request_id: requestId,
      actor_user_id: userData.user.id,
      tenant_id: uploadIntent.tenantId,
      document_class_code: uploadIntent.documentClassCode,
      duration_ms: Date.now() - startedAt,
    });

    return jsonResponse({
      success: true,
      request_id: requestId,
      upload_intent: {
        upload_intent_id: uploadIntent.uploadIntentId,
        tenant_id: uploadIntent.tenantId,
        document_class_code: uploadIntent.documentClassCode,
        bucket_code: uploadIntent.bucketCode,
        bucket_name: uploadIntent.bucketName,
        storage_object_name: uploadIntent.storageObjectName,
        original_file_name: uploadIntent.originalFileName,
        content_type: uploadIntent.contentType,
        protection_mode: uploadIntent.protectionMode,
        access_mode: uploadIntent.accessMode,
        intent_expires_at: uploadIntent.intentExpiresAt,
      },
      upload_target: {
        path: typeof signedUploadInfo.path === "string" ? signedUploadInfo.path : uploadIntent.storageObjectName,
        token: typeof signedUploadInfo.token === "string" ? signedUploadInfo.token : null,
        signed_upload_url: typeof signedUploadInfo.signedUrl === "string" ? signedUploadInfo.signedUrl : null,
      },
    });
  } catch (error) {
    const edgeError = error instanceof EdgeHttpError
      ? error
      : new EdgeHttpError(
        error instanceof Error ? error.message : "Unexpected error.",
        500,
        "DOCUMENT_UPLOAD_INTENT_FAILED",
      );

    logStructured("error", "document-upload-intent failed", {
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
