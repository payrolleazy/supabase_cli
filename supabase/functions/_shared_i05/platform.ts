import { EdgeHttpError } from "./http.ts";
import type { JsonMap, PlatformRpcResult } from "./supabase.ts";

export type UploadIntentDescriptor = {
  uploadIntentId: string;
  tenantId: string;
  documentClassCode: string;
  bucketCode: string;
  bucketName: string;
  storageObjectName: string;
  originalFileName: string;
  contentType: string;
  protectionMode: string;
  accessMode: string;
  intentExpiresAt: string;
};

export type DocumentAccessDescriptor = {
  documentId: string;
  tenantId: string;
  documentClassCode: string;
  bucketCode: string;
  bucketName: string;
  storageObjectName: string;
  originalFileName: string;
  contentType: string;
  protectionMode: string;
  accessMode: string;
  accessReason: string;
  documentStatus: string;
};

export function asObject(value: unknown): JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as JsonMap)
    : {};
}

export function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function mapI05ErrorStatus(code: string): number {
  switch (code) {
    case "AUTH_REQUIRED":
    case "INVALID_JWT":
    case "UNAUTHENTICATED":
      return 401;
    case "ACCESS_DENIED":
    case "ACTOR_TENANT_ACCESS_REQUIRED":
    case "UPLOAD_COMPLETION_NOT_ALLOWED":
    case "INTERNAL_CALLER_REQUIRED":
      return 403;
    case "DOCUMENT_NOT_FOUND":
    case "DOCUMENT_CLASS_NOT_FOUND":
    case "BUCKET_NOT_FOUND":
    case "UPLOAD_INTENT_NOT_FOUND":
      return 404;
    case "UPLOAD_INTENT_EXPIRED":
      return 410;
    case "UPLOAD_INTENT_NOT_PENDING":
    case "UPLOAD_ALREADY_MARKED_COMPLETED":
    case "STORAGE_OBJECT_NOT_FOUND":
      return 409;
    case "TENANT_ID_REQUIRED":
    case "DOCUMENT_CLASS_CODE_REQUIRED":
    case "ORIGINAL_FILE_NAME_REQUIRED":
    case "CONTENT_TYPE_REQUIRED":
    case "INVALID_METADATA":
    case "BINDING_TARGET_ARGUMENTS_INVALID":
    case "INVALID_INTENT_EXPIRY":
    case "CONTENT_TYPE_NOT_ALLOWED":
    case "INVALID_EXPECTED_SIZE":
    case "FILE_SIZE_EXCEEDS_CLASS_LIMIT":
    case "FILE_SIZE_EXCEEDS_BUCKET_LIMIT":
    case "REQUESTED_BY_ACTOR_REQUIRED":
    case "UPLOAD_INTENT_ID_REQUIRED":
    case "UPLOADED_BY_ACTOR_REQUIRED":
    case "INVALID_CHECKSUM":
    case "INVALID_FILE_SIZE":
    case "DOCUMENT_ID_REQUIRED":
      return 400;
    default:
      return 500;
  }
}

export function requirePlatformSuccess(
  result: PlatformRpcResult,
  fallbackCode: string,
  fallbackMessage: string,
): JsonMap {
  if (result?.success) {
    return asObject(result.details);
  }

  const code = asString(result?.code) || fallbackCode;
  throw new EdgeHttpError(
    asString(result?.message) || fallbackMessage,
    mapI05ErrorStatus(code),
    code,
    asObject(result?.details),
  );
}

function requireField(details: JsonMap, key: string, label: string): string {
  const value = asString(details[key]);
  if (!value) {
    throw new EdgeHttpError(`${label} is missing from the platform response.`, 500, "INVALID_PLATFORM_RESPONSE", {
      field: key,
    });
  }
  return value;
}

export function parseUploadIntentDescriptor(details: JsonMap): UploadIntentDescriptor {
  return {
    uploadIntentId: requireField(details, "upload_intent_id", "upload_intent_id"),
    tenantId: requireField(details, "tenant_id", "tenant_id"),
    documentClassCode: requireField(details, "document_class_code", "document_class_code"),
    bucketCode: requireField(details, "bucket_code", "bucket_code"),
    bucketName: requireField(details, "bucket_name", "bucket_name"),
    storageObjectName: requireField(details, "storage_object_name", "storage_object_name"),
    originalFileName: requireField(details, "original_file_name", "original_file_name"),
    contentType: requireField(details, "content_type", "content_type"),
    protectionMode: requireField(details, "protection_mode", "protection_mode"),
    accessMode: requireField(details, "access_mode", "access_mode"),
    intentExpiresAt: requireField(details, "intent_expires_at", "intent_expires_at"),
  };
}

export function parseDocumentAccessDescriptor(details: JsonMap): DocumentAccessDescriptor {
  return {
    documentId: requireField(details, "document_id", "document_id"),
    tenantId: requireField(details, "tenant_id", "tenant_id"),
    documentClassCode: requireField(details, "document_class_code", "document_class_code"),
    bucketCode: requireField(details, "bucket_code", "bucket_code"),
    bucketName: requireField(details, "bucket_name", "bucket_name"),
    storageObjectName: requireField(details, "storage_object_name", "storage_object_name"),
    originalFileName: requireField(details, "original_file_name", "original_file_name"),
    contentType: requireField(details, "content_type", "content_type"),
    protectionMode: requireField(details, "protection_mode", "protection_mode"),
    accessMode: requireField(details, "access_mode", "access_mode"),
    accessReason: requireField(details, "access_reason", "access_reason"),
    documentStatus: requireField(details, "document_status", "document_status"),
  };
}
