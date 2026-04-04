import { EdgeHttpError } from "../_shared/http.ts";
import type { JsonMap, PlatformRpcResult } from "../_shared/supabase.ts";

export type TemplateColumn = {
  columnCode: string;
  label: string;
  dataType: string;
  required: boolean;
  defaultValue: unknown;
};

export type ExchangeContractDescriptor = {
  contractId: string;
  contractCode: string;
  direction: string;
  contractLabel: string;
  ownerModuleCode: string;
  entityCode: string;
  entityLabel: string;
  workerCode: string;
  sourceOperationCode: string | null;
  targetOperationCode: string | null;
  joinProfileCode: string | null;
  templateMode: string;
  acceptedFileFormats: string[];
  allowedRoleCodes: string[];
  uploadDocumentClassCode: string | null;
  artifactDocumentClassCode: string | null;
  artifactBucketCode: string | null;
  validationProfile: JsonMap;
  deliveryProfile: JsonMap;
  templateDescriptor: {
    entityCode: string | null;
    tenantId: string | null;
    targetRelationSchema: string | null;
    targetRelationName: string | null;
    columns: TemplateColumn[];
  };
};

export type ImportSessionIssueDescriptor = {
  importSessionId: string;
  tenantId: string;
  contractCode: string;
  uploadIntentId: string;
  bucketName: string;
  storageObjectName: string;
  sessionStatus: string;
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

export type ExportDeliveryDescriptor = {
  exportJobId: string;
  tenantId: string;
  contractCode: string;
  exportArtifactId: string;
  artifactStatus: string;
  fileName: string;
  contentType: string;
  retentionExpiresAt: string | null;
  documentAccess: DocumentAccessDescriptor;
};

export function asObject(value: unknown): JsonMap {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as JsonMap)
    : {};
}

export function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function asStringOrNull(value: unknown): string | null {
  const normalized = asString(value);
  return normalized || null;
}

export function asStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.map((entry) => asString(entry)).filter((entry) => entry.length > 0)
    : [];
}

function asBoolean(value: unknown): boolean {
  return value === true;
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

export function mapI06ErrorStatus(code: string): number {
  switch (code) {
    case "AUTH_REQUIRED":
    case "INVALID_JWT":
    case "UNAUTHENTICATED":
      return 401;
    case "ACCESS_DENIED":
    case "INSUFFICIENT_ROLE":
    case "ACTOR_TENANT_ACCESS_REQUIRED":
    case "INTERNAL_CALLER_REQUIRED":
      return 403;
    case "CONTRACT_NOT_FOUND":
    case "IMPORT_CONTRACT_NOT_FOUND":
    case "EXPORT_CONTRACT_NOT_FOUND":
    case "IMPORT_SESSION_NOT_FOUND":
    case "EXPORT_JOB_NOT_FOUND":
    case "EXPORT_ARTIFACT_NOT_FOUND":
    case "DOCUMENT_NOT_FOUND":
    case "ENTITY_NOT_FOUND":
    case "JOIN_PROFILE_NOT_FOUND":
    case "BUCKET_NOT_FOUND":
    case "DOCUMENT_CLASS_NOT_FOUND":
      return 404;
    case "UPLOAD_INTENT_EXPIRED":
      return 410;
    case "SOURCE_DOCUMENT_NOT_READY":
    case "IMPORT_SESSION_PREVIEW_BLOCKED":
    case "IMPORT_SESSION_NOT_READY":
    case "EXPORT_ARTIFACT_NOT_READY":
    case "EXPORT_ARTIFACT_DOCUMENT_REQUIRED":
    case "UPLOAD_INTENT_NOT_PENDING":
    case "UPLOAD_ALREADY_MARKED_COMPLETED":
    case "DOCUMENT_TENANT_MISMATCH":
    case "TEMPLATE_DESCRIPTOR_EMPTY":
      return 409;
    case "EXPORT_QUOTA_EXCEEDED":
    case "EXPORT_DAILY_QUOTA_EXCEEDED":
      return 429;
    case "TENANT_ID_REQUIRED":
    case "CONTRACT_CODE_REQUIRED":
    case "ACTOR_USER_ID_REQUIRED":
    case "SOURCE_FILE_NAME_REQUIRED":
    case "CONTENT_TYPE_REQUIRED":
    case "INVALID_JSON_OBJECT":
    case "INVALID_METADATA":
    case "INVALID_FILE_FORMAT":
    case "IMPORT_SESSION_ID_REQUIRED":
    case "STAGED_ROWS_REQUIRED":
    case "STAGED_ROWS_ARRAY_REQUIRED":
    case "EXPORT_JOB_ID_REQUIRED":
    case "DOCUMENT_ID_REQUIRED":
    case "UPLOAD_INTENT_ID_REQUIRED":
    case "TEMPLATE_FORMAT_NOT_SUPPORTED":
      return 400;
    case "SIGNED_UPLOAD_URL_FAILED":
    case "SIGNED_URL_ISSUE_FAILED":
      return 502;
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
    mapI06ErrorStatus(code),
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

function parseTemplateColumns(value: unknown): TemplateColumn[] {
  return asArray(value).map((entry) => {
    const row = asObject(entry);
    return {
      columnCode: requireField(row, "column_code", "column_code"),
      label: requireField(row, "label", "label"),
      dataType: requireField(row, "data_type", "data_type"),
      required: asBoolean(row.required),
      defaultValue: Object.prototype.hasOwnProperty.call(row, "default_value") ? row.default_value : null,
    };
  });
}

export function parseExchangeContract(details: JsonMap): ExchangeContractDescriptor {
  const templateDescriptor = asObject(details.template_descriptor);
  return {
    contractId: requireField(details, "contract_id", "contract_id"),
    contractCode: requireField(details, "contract_code", "contract_code"),
    direction: requireField(details, "direction", "direction"),
    contractLabel: requireField(details, "contract_label", "contract_label"),
    ownerModuleCode: requireField(details, "owner_module_code", "owner_module_code"),
    entityCode: requireField(details, "entity_code", "entity_code"),
    entityLabel: requireField(details, "entity_label", "entity_label"),
    workerCode: requireField(details, "worker_code", "worker_code"),
    sourceOperationCode: asStringOrNull(details.source_operation_code),
    targetOperationCode: asStringOrNull(details.target_operation_code),
    joinProfileCode: asStringOrNull(details.join_profile_code),
    templateMode: requireField(details, "template_mode", "template_mode"),
    acceptedFileFormats: asStringArray(details.accepted_file_formats),
    allowedRoleCodes: asStringArray(details.allowed_role_codes),
    uploadDocumentClassCode: asStringOrNull(details.upload_document_class_code),
    artifactDocumentClassCode: asStringOrNull(details.artifact_document_class_code),
    artifactBucketCode: asStringOrNull(details.artifact_bucket_code),
    validationProfile: asObject(details.validation_profile),
    deliveryProfile: asObject(details.delivery_profile),
    templateDescriptor: {
      entityCode: asStringOrNull(templateDescriptor.entity_code),
      tenantId: asStringOrNull(templateDescriptor.tenant_id),
      targetRelationSchema: asStringOrNull(templateDescriptor.target_relation_schema),
      targetRelationName: asStringOrNull(templateDescriptor.target_relation_name),
      columns: parseTemplateColumns(templateDescriptor.columns),
    },
  };
}

export function parseImportSessionIssue(details: JsonMap): ImportSessionIssueDescriptor {
  return {
    importSessionId: requireField(details, "import_session_id", "import_session_id"),
    tenantId: requireField(details, "tenant_id", "tenant_id"),
    contractCode: requireField(details, "contract_code", "contract_code"),
    uploadIntentId: requireField(details, "upload_intent_id", "upload_intent_id"),
    bucketName: requireField(details, "bucket_name", "bucket_name"),
    storageObjectName: requireField(details, "storage_object_name", "storage_object_name"),
    sessionStatus: requireField(details, "session_status", "session_status"),
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

export function parseExportDeliveryDescriptor(details: JsonMap): ExportDeliveryDescriptor {
  return {
    exportJobId: requireField(details, "export_job_id", "export_job_id"),
    tenantId: requireField(details, "tenant_id", "tenant_id"),
    contractCode: requireField(details, "contract_code", "contract_code"),
    exportArtifactId: requireField(details, "export_artifact_id", "export_artifact_id"),
    artifactStatus: requireField(details, "artifact_status", "artifact_status"),
    fileName: requireField(details, "file_name", "file_name"),
    contentType: requireField(details, "content_type", "content_type"),
    retentionExpiresAt: asStringOrNull(details.retention_expires_at),
    documentAccess: parseDocumentAccessDescriptor(asObject(details.document_access)),
  };
}

function csvCell(value: unknown): string {
  if (value === null || value === undefined) return "";
  const raw = typeof value === "string"
    ? value
    : typeof value === "number" || typeof value === "boolean"
    ? String(value)
    : "";
  if (/[",\r\n]/.test(raw)) {
    return `"${raw.replace(/"/g, '""')}"`;
  }
  return raw;
}

export function buildTemplateCsv(contract: ExchangeContractDescriptor, includeDefaultRow = true): string {
  const columns = contract.templateDescriptor.columns;
  if (columns.length === 0) {
    throw new EdgeHttpError("Template descriptor does not contain any columns.", 409, "TEMPLATE_DESCRIPTOR_EMPTY", {
      contract_code: contract.contractCode,
    });
  }

  const lines: string[] = [];
  lines.push(columns.map((column) => csvCell(column.columnCode)).join(","));
  if (includeDefaultRow) {
    lines.push(columns.map((column) => csvCell(column.defaultValue)).join(","));
  }
  return lines.join("\r\n") + "\r\n";
}
