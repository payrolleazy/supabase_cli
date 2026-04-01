import { CORS_HEADERS, EdgeHttpError, asObject, createRequestId, jsonResponse, logStructured, readJsonBody, requireServiceRoleBearer } from "../_shared/http.ts";
import { callPlatformRpc, createServiceRoleClient } from "../_shared/supabase.ts";

const MAX_BODY_BYTES = 16 * 1024;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  const requestId = createRequestId(req);
  const startedAt = Date.now();

  try {
    if (req.method !== "POST") return jsonResponse({ success: false, error: "Method not allowed.", error_code: "METHOD_NOT_ALLOWED" }, 405);
    requireServiceRoleBearer(req);
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
