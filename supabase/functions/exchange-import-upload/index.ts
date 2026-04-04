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
} from "../_shared/http.ts";
import {
  asObject,
  parseImportSessionIssue,
  requirePlatformSuccess,
} from "../_shared_i06/platform.ts";
import { callPlatformRpc, createServiceRoleClient, createUserClient } from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 64 * 1024;

const IssueSchema = z.object({
  action: z.literal("issue"),
  tenant_id: z.string().uuid().optional(),
  tenant_code: z.string().min(1).max(100).transform((value) => value.trim().toLowerCase()).optional(),
  contract_code: z.string().min(1).max(120).transform((value) => value.trim().toLowerCase()),
  source_file_name: z.string().min(1).max(255).transform((value) => value.trim()),
  original_file_name: z.string().min(1).max(255).transform((value) => value.trim()).optional(),
  content_type: z.string().min(1).max(200).transform((value) => value.trim().toLowerCase()),
  expected_size_bytes: z.number().int().positive().max(100 * 1024 * 1024).optional(),
  idempotency_key: z.string().min(1).max(200).optional(),
  metadata: z.record(z.string(), z.unknown()).default({}),
}).strict().refine((value) => Boolean(value.tenant_id || value.tenant_code), {
  message: "tenant_id or tenant_code is required",
  path: ["tenant_id"],
});

const CompleteSchema = z.object({
  action: z.literal("complete"),
  upload_intent_id: z.string().uuid(),
  file_size_bytes: z.number().int().positive().max(100 * 1024 * 1024).optional(),
  checksum_sha256: z.string().regex(/^[A-Fa-f0-9]{64}$/).optional(),
  storage_metadata: z.record(z.string(), z.unknown()).default({}),
  document_metadata: z.record(z.string(), z.unknown()).default({}),
  expires_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
}).strict();

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new EdgeHttpError(`Missing required environment variable: ${name}`, 500, "MISSING_ENV");
  return value;
}

function encodeStorageObjectName(value: string): string {
  return value.split("/").map((segment) => encodeURIComponent(segment)).join("/");
}

async function issueSignedUploadTarget(bucketName: string, storageObjectName: string) {
  const url = new URL(`/storage/v1/object/upload/sign/${encodeURIComponent(bucketName)}/${encodeStorageObjectName(storageObjectName)}`, requireEnv("SUPABASE_URL"));
  const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${serviceRoleKey}`,
      apikey: serviceRoleKey,
      "Content-Type": "application/json",
    },
    body: "{}",
  });
  const payload = asObject(await response.json().catch(() => ({})));
  if (!response.ok) {
    throw new EdgeHttpError("Unable to issue signed upload target.", 502, "SIGNED_UPLOAD_URL_FAILED", {
      bucket_name: bucketName,
      storage_object_name: storageObjectName,
      storage_error: payload,
    });
  }

  return {
    path: typeof payload.path === "string" ? payload.path : storageObjectName,
    token: typeof payload.token === "string" ? payload.token : null,
    signed_upload_url: typeof payload.signedUrl === "string" ? payload.signedUrl : null,
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  const requestId = createRequestId(req);
  const startedAt = Date.now();

  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    if (req.method !== "POST") throw new EdgeHttpError("Method not allowed.", 405, "METHOD_NOT_ALLOWED");

    const accessToken = requireBearerToken(req);
    const rawBody = await readJsonBody(req, MAX_BODY_BYTES);
    const bodyObject = asObject(rawBody);
    const action = typeof bodyObject.action === "string" ? bodyObject.action.trim().toLowerCase() : "";
    if (action !== "issue" && action !== "complete") throw new EdgeHttpError("action must be issue or complete.", 400, "ACTION_REQUIRED");

    const userClient = createUserClient(accessToken);
    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData.user) {
      throw new EdgeHttpError("Authenticated user context is not available.", 401, "INVALID_JWT");
    }

    const serviceClient = createServiceRoleClient();

    if (action === "issue") {
      const body = IssueSchema.parse(rawBody);
      const client = getClientMetadata(req);
      const issueDetails = requirePlatformSuccess(
        await callPlatformRpc(serviceClient, "platform_issue_import_session", {
          tenant_id: body.tenant_id ?? null,
          tenant_code: body.tenant_code ?? null,
          contract_code: body.contract_code,
          actor_user_id: userData.user.id,
          source_file_name: body.source_file_name,
          original_file_name: body.original_file_name ?? body.source_file_name,
          content_type: body.content_type,
          expected_size_bytes: body.expected_size_bytes ?? null,
          idempotency_key: body.idempotency_key ?? null,
          metadata: {
            ...body.metadata,
            source: "exchange-import-upload",
            action: "issue",
            request_id: requestId,
            source_ip: client.sourceIp,
            user_agent: client.userAgent,
          },
        }),
        "IMPORT_SESSION_ISSUE_FAILED",
        "Unable to issue import session.",
      );
      const session = parseImportSessionIssue(issueDetails);
      const uploadTarget = await issueSignedUploadTarget(session.bucketName, session.storageObjectName);

      logStructured("info", "exchange-import-upload issued", {
        request_id: requestId,
        actor_user_id: userData.user.id,
        tenant_id: session.tenantId,
        contract_code: session.contractCode,
        import_session_id: session.importSessionId,
        duration_ms: Date.now() - startedAt,
      });

      return jsonResponse({
        success: true,
        request_id: requestId,
        import_session: {
          import_session_id: session.importSessionId,
          tenant_id: session.tenantId,
          contract_code: session.contractCode,
          upload_intent_id: session.uploadIntentId,
          session_status: session.sessionStatus,
          bucket_name: session.bucketName,
          storage_object_name: session.storageObjectName,
        },
        upload_target: uploadTarget,
      });
    }

    const body = CompleteSchema.parse(rawBody);
    const completeDetails = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_complete_document_upload", {
        upload_intent_id: body.upload_intent_id,
        uploaded_by_actor_user_id: userData.user.id,
        file_size_bytes: body.file_size_bytes ?? null,
        checksum_sha256: body.checksum_sha256 ?? null,
        storage_metadata: {
          ...body.storage_metadata,
          completed_via: "exchange-import-upload",
          request_id: requestId,
        },
        document_metadata: body.document_metadata,
        expires_on: body.expires_on ?? null,
      }),
      "IMPORT_UPLOAD_COMPLETE_FAILED",
      "Unable to finalize import upload.",
    );

    const { data: sessionData, error: sessionError } = await (serviceClient as any)
      .from("platform_import_session")
      .select("import_session_id, tenant_id, source_document_id, session_status")
      .eq("upload_intent_id", body.upload_intent_id)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (sessionError) throw new EdgeHttpError("Import session lookup failed after upload completion.", 500, "IMPORT_SESSION_LOOKUP_FAILED");

    logStructured("info", "exchange-import-upload completed", {
      request_id: requestId,
      actor_user_id: userData.user.id,
      upload_intent_id: body.upload_intent_id,
      import_session_id: sessionData?.import_session_id ?? null,
      duration_ms: Date.now() - startedAt,
    });

    return jsonResponse({
      success: true,
      request_id: requestId,
      document: completeDetails,
      import_session: sessionData ? {
        import_session_id: String(sessionData.import_session_id),
        tenant_id: String(sessionData.tenant_id),
        source_document_id: sessionData.source_document_id ? String(sessionData.source_document_id) : null,
        session_status: String(sessionData.session_status),
      } : null,
    });
  } catch (error) {
    const edgeError = error instanceof EdgeHttpError
      ? error
      : new EdgeHttpError(error instanceof Error ? error.message : "Unexpected error.", 500, "EXCHANGE_IMPORT_UPLOAD_FAILED");

    logStructured("error", "exchange-import-upload failed", {
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
