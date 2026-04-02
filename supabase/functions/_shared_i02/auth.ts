import { EdgeHttpError } from "./http.ts";
import { autoConfirmOwnerEmail, asString } from "./platform.ts";
import type { SupabaseClient } from "./supabase.ts";

type OwnerIdentityArgs = {
  existingActorUserId?: string | null;
  email: string;
  password: string;
  displayName?: string | null;
  primaryMobile?: string | null;
  provisionRequestId: string;
};

type OwnerIdentityResult = {
  actorUserId: string;
  created: boolean;
  recovered: boolean;
};

function buildUserMetadata(args: OwnerIdentityArgs): Record<string, unknown> {
  const metadata: Record<string, unknown> = {
    bootstrap_source: "client_owner_credential_bootstrap",
    i02_provision_request_id: args.provisionRequestId,
  };

  if (args.displayName) {
    metadata.display_name = args.displayName;
  }
  if (args.primaryMobile) {
    metadata.primary_mobile = args.primaryMobile;
  }

  return metadata;
}

function authErrorSnapshot(error: unknown): Record<string, unknown> {
  return {
    auth_error_code: (error as { code?: string })?.code ?? null,
    auth_error_message: (error as { message?: string })?.message ?? null,
  };
}

function throwMappedAuthError(error: unknown, fallbackMessage: string): never {
  const code = String((error as { code?: string })?.code ?? "").trim().toUpperCase();
  const message = String((error as { message?: string })?.message ?? "").trim().toUpperCase();

  if (code.includes("WEAK_PASSWORD") || message.includes("WEAK PASSWORD")) {
    throw new EdgeHttpError(
      "The password does not meet security requirements.",
      400,
      "OWNER_PASSWORD_WEAK",
      authErrorSnapshot(error),
    );
  }

  if (code.includes("EMAIL_ADDRESS_INVALID") || message.includes("INVALID EMAIL")) {
    throw new EdgeHttpError(
      "The owner email address is invalid.",
      400,
      "OWNER_EMAIL_INVALID",
      authErrorSnapshot(error),
    );
  }

  if (code.includes("OVER_REQUEST_RATE_LIMIT") || message.includes("RATE LIMIT")) {
    throw new EdgeHttpError(
      "Too many credential bootstrap attempts were detected. Please wait before trying again.",
      429,
      "OWNER_AUTH_RATE_LIMITED",
      authErrorSnapshot(error),
    );
  }

  if (
    code.includes("USER_ALREADY_EXISTS") ||
    code.includes("EMAIL_EXISTS") ||
    message.includes("ALREADY REGISTERED") ||
    message.includes("ALREADY EXISTS")
  ) {
    throw new EdgeHttpError(
      "An account already exists for this owner email.",
      409,
      "OWNER_AUTH_CONFLICT",
      authErrorSnapshot(error),
    );
  }

  throw new EdgeHttpError(
    fallbackMessage,
    502,
    "OWNER_AUTH_WRITE_FAILED",
    authErrorSnapshot(error),
  );
}

async function findAuthUserByEmail(client: SupabaseClient, email: string): Promise<Record<string, unknown> | null> {
  const normalizedEmail = email.trim().toLowerCase();

  for (let page = 1; page <= 10; page += 1) {
    const { data, error } = await client.auth.admin.listUsers({
      page,
      perPage: 200,
    });

    if (error) {
      throw new EdgeHttpError(
        "Unable to inspect existing owner identities.",
        502,
        "OWNER_AUTH_LOOKUP_FAILED",
        authErrorSnapshot(error),
      );
    }

    const users = Array.isArray(data?.users) ? data.users : [];
    const found = users.find((entry) => String(entry.email ?? "").trim().toLowerCase() === normalizedEmail);
    if (found) {
      return found as unknown as Record<string, unknown>;
    }

    if (users.length < 200) {
      break;
    }
  }

  return null;
}

export async function createOrUpdateOwnerIdentity(
  client: SupabaseClient,
  args: OwnerIdentityArgs,
): Promise<OwnerIdentityResult> {
  const metadata = buildUserMetadata(args);
  const emailConfirm = autoConfirmOwnerEmail();

  if (args.existingActorUserId) {
    const updateResult = await client.auth.admin.updateUserById(args.existingActorUserId, {
      email: args.email,
      password: args.password,
      email_confirm: emailConfirm,
      user_metadata: metadata,
    });

    if (updateResult.error || !updateResult.data.user?.id) {
      throwMappedAuthError(
        updateResult.error,
        "Unable to update the owner account.",
      );
    }

    return {
      actorUserId: updateResult.data.user.id,
      created: false,
      recovered: false,
    };
  }

  const createResult = await client.auth.admin.createUser({
    email: args.email,
    password: args.password,
    email_confirm: emailConfirm,
    user_metadata: metadata,
  });

  if (!createResult.error && createResult.data.user?.id) {
    return {
      actorUserId: createResult.data.user.id,
      created: true,
      recovered: false,
    };
  }

  const existingUser = await findAuthUserByEmail(client, args.email);
  const existingUserId = asString(existingUser?.id);
  const existingMetadata = typeof existingUser?.user_metadata === "object" && existingUser.user_metadata !== null
    ? (existingUser.user_metadata as Record<string, unknown>)
    : {};

  if (
    existingUserId &&
    asString(existingMetadata.i02_provision_request_id) === args.provisionRequestId
  ) {
    const updateResult = await client.auth.admin.updateUserById(existingUserId, {
      email: args.email,
      password: args.password,
      email_confirm: emailConfirm,
      user_metadata: metadata,
    });

    if (updateResult.error || !updateResult.data.user?.id) {
      throwMappedAuthError(
        updateResult.error,
        "Unable to recover the owner account.",
      );
    }

    return {
      actorUserId: updateResult.data.user.id,
      created: false,
      recovered: true,
    };
  }

  throwMappedAuthError(
    createResult.error,
    "Unable to create the owner account.",
  );
}
