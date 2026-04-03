import { createClient } from "npm:@supabase/supabase-js@2";

export type JsonMap = Record<string, unknown>;
export type SupabaseClient = ReturnType<typeof createClient>;

export type PlatformRpcResult = {
  success?: boolean;
  code?: string;
  message?: string;
  details?: JsonMap;
};

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export function createUserClient(accessToken: string): SupabaseClient {
  return createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_ANON_KEY"),
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
      global: {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      },
    },
  );
}

export function createServiceRoleClient(): SupabaseClient {
  return createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );
}

export async function callPlatformRpc(
  client: SupabaseClient,
  functionName: string,
  params: JsonMap,
): Promise<PlatformRpcResult> {
  const rpcInvoker = (client as unknown as {
    rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;
  }).rpc.bind(client);
  const { data, error } = await rpcInvoker(functionName, { p_params: params });
  if (error) {
    throw new Error(`${functionName} failed: ${error.message}`);
  }
  return (data ?? {}) as PlatformRpcResult;
}
