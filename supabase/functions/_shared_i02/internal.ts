import { EdgeHttpError } from "./http.ts";

const DEFAULT_AUTH_PROBE_PATH = "/rest/v1/platform_tenant?select=tenant_code&limit=1";

export async function requireServiceRoleAccess(req: Request, probePath = DEFAULT_AUTH_PROBE_PATH): Promise<void> {
  const authHeader = req.headers.get("authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() || "";
  if (!supabaseUrl || !token) {
    throw new EdgeHttpError("Forbidden", 403, "FORBIDDEN");
  }

  const response = await fetch(`${supabaseUrl}${probePath}`, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      apikey: token,
      "x-client-info": "i01-service-role-auth-probe",
    },
  });

  if (!response.ok) {
    throw new EdgeHttpError("Forbidden", 403, "FORBIDDEN");
  }
}

export async function invokeInternalFunction(
  functionSlug: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() || "";
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY for internal function invocation.");
  }

  return fetch(`${supabaseUrl}/functions/v1/${functionSlug}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${serviceRoleKey}`,
      apikey: serviceRoleKey,
      "Content-Type": "application/json",
      "x-client-info": `internal-${functionSlug}`,
    },
    body: JSON.stringify(body),
  });
}
