import { z } from "npm:zod@3.23.8";

import {
  CORS_HEADERS,
  createRequestId,
  EdgeHttpError,
  jsonResponse,
  logStructured,
  readJsonBody,
  requireBearerToken,
} from "../_shared/http.ts";
import {
  buildTemplateCsv,
  parseExchangeContract,
  requirePlatformSuccess,
} from "../_shared_i06/platform.ts";
import { callPlatformRpc, createServiceRoleClient, createUserClient } from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 16 * 1024;

const TemplateRequestSchema = z.object({
  tenant_id: z.string().uuid().optional(),
  tenant_code: z.string().min(1).max(100).transform((value) => value.trim().toLowerCase()).optional(),
  contract_code: z.string().min(1).max(120).transform((value) => value.trim().toLowerCase()),
  format: z.enum(["csv"]).default("csv"),
  include_default_row: z.boolean().default(true),
}).strict().refine((value) => Boolean(value.tenant_id || value.tenant_code), {
  message: "tenant_id or tenant_code is required",
  path: ["tenant_id"],
});

type TemplateRequestBody = z.infer<typeof TemplateRequestSchema>;

async function resolveTenantId(
  serviceClient: ReturnType<typeof createServiceRoleClient>,
  body: TemplateRequestBody,
): Promise<string> {
  if (body.tenant_id) return body.tenant_id;

  const { data, error } = await (serviceClient as any)
    .from("platform_tenant_registry_view")
    .select("tenant_id, tenant_code, ready_for_routing")
    .eq("tenant_code", body.tenant_code)
    .maybeSingle();

  if (error) throw new EdgeHttpError("Unable to resolve tenant context.", 500, "TENANT_RESOLUTION_FAILED");
  if (!data?.tenant_id || data.ready_for_routing !== true) {
    throw new EdgeHttpError("Tenant is not available for routing.", 404, "TENANT_NOT_READY", {
      tenant_code: body.tenant_code ?? null,
    });
  }

  return String(data.tenant_id);
}

function sanitizeFilename(value: string): string {
  return value.trim().replace(/[^A-Za-z0-9._-]+/g, "_") || "exchange-template";
}

Deno.serve(async (req: Request): Promise<Response> => {
  const requestId = createRequestId(req);
  const startedAt = Date.now();

  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    if (req.method !== "POST") throw new EdgeHttpError("Method not allowed.", 405, "METHOD_NOT_ALLOWED");

    const accessToken = requireBearerToken(req);
    const body = TemplateRequestSchema.parse(await readJsonBody(req, MAX_BODY_BYTES));
    const userClient = createUserClient(accessToken);
    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData.user) {
      throw new EdgeHttpError("Authenticated user context is not available.", 401, "INVALID_JWT");
    }

    const serviceClient = createServiceRoleClient();
    const tenantId = await resolveTenantId(serviceClient, body);
    const contractDetails = requirePlatformSuccess(
      await callPlatformRpc(serviceClient, "platform_get_exchange_contract", {
        tenant_id: tenantId,
        contract_code: body.contract_code,
        include_template_descriptor: true,
      }),
      "EXCHANGE_CONTRACT_RESOLVE_FAILED",
      "Unable to resolve exchange contract.",
    );
    const contract = parseExchangeContract(contractDetails);

    if (contract.direction !== "import") {
      throw new EdgeHttpError("Template generation is only supported for import contracts.", 409, "TEMPLATE_DIRECTION_INVALID", {
        contract_code: contract.contractCode,
        direction: contract.direction,
      });
    }

    const accessRpc = await (serviceClient as unknown as {
      rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;
    }).rpc("platform_i06_assert_actor_access", {
      p_tenant_id: tenantId,
      p_actor_user_id: userData.user.id,
      p_allowed_role_codes: contract.allowedRoleCodes,
    });
    if (accessRpc.error) {
      throw new EdgeHttpError("Unable to validate actor access.", 500, "ACCESS_ASSERT_FAILED", {
        rpc_error: accessRpc.error.message,
      });
    }

    requirePlatformSuccess(
      (accessRpc.data ?? {}) as { success?: boolean; code?: string; message?: string; details?: Record<string, unknown> },
      "ACCESS_DENIED",
      "Actor is not allowed to generate this template.",
    );

    const csv = buildTemplateCsv(contract, body.include_default_row);
    const fileName = sanitizeFilename(`${contract.contractCode}-template.csv`);
    const headers = new Headers(CORS_HEADERS);
    headers.set("Cache-Control", "private, no-store");
    headers.set("Content-Type", "text/csv; charset=utf-8");
    headers.set("Content-Disposition", `attachment; filename=\"${fileName}\"`);
    headers.set("X-I06-Contract-Code", contract.contractCode);
    headers.set("X-Request-Id", requestId);

    logStructured("info", "exchange-template-generate completed", {
      request_id: requestId,
      actor_user_id: userData.user.id,
      tenant_id: tenantId,
      contract_code: contract.contractCode,
      column_count: contract.templateDescriptor.columns.length,
      duration_ms: Date.now() - startedAt,
    });

    return new Response(csv, { status: 200, headers });
  } catch (error) {
    const edgeError = error instanceof EdgeHttpError
      ? error
      : new EdgeHttpError(error instanceof Error ? error.message : "Unexpected error.", 500, "EXCHANGE_TEMPLATE_GENERATE_FAILED");

    logStructured("error", "exchange-template-generate failed", {
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
