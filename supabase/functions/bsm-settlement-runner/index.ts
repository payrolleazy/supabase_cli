import { CORS_HEADERS, EdgeHttpError, asObject, createRequestId, jsonResponse, logStructured, readJsonBody } from "../_shared/http.ts";
import { callPlatformRpc, createServiceRoleClient } from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 16 * 1024;
const AUTH_PROBE_PATH = "/rest/v1/platform_tenant?select=tenant_code&limit=1";

async function requireServiceRoleAccess(req: Request): Promise<void> {
  const authHeader = req.headers.get("authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() || "";
  if (!supabaseUrl || !token) {
    throw new EdgeHttpError("Forbidden", 403, "FORBIDDEN");
  }

  const response = await fetch(`${supabaseUrl}${AUTH_PROBE_PATH}`, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      apikey: token,
      "x-client-info": "bsm-settlement-runner-auth-probe",
    },
  });

  if (!response.ok) {
    throw new EdgeHttpError("Forbidden", 403, "FORBIDDEN");
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
    const client = createServiceRoleClient();
    const result = await callPlatformRpc(client, "platform_commercial_orchestrator", body);
    if (result.success !== true) {
      return jsonResponse({ success: false, error: result.message || "Commercial orchestrator failed.", error_code: result.code || "COMMERCIAL_ORCHESTRATOR_FAILED", details: result.details || {} }, 409);
    }
    return jsonResponse({ success: true, request_id: requestId, details: result.details || {} });
  } catch (error) {
    logStructured("error", "bsm_settlement_runner_failed", { request_id: requestId, duration_ms: Date.now() - startedAt, error: error instanceof Error ? error.message : String(error) });
    if (error instanceof EdgeHttpError) {
      return jsonResponse({ success: false, error: error.message, error_code: error.code, details: error.details }, error.status, error.headers);
    }
    return jsonResponse({ success: false, error: "Unable to process settlement runner request.", error_code: "INTERNAL_ERROR" }, 500);
  }
});
