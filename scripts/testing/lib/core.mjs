import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { access, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const currentDir = path.dirname(fileURLToPath(import.meta.url));
export const repoRoot = path.resolve(currentDir, "..", "..", "..");
const envFileValues = loadTestingEnvFiles();

export function parseArgs(argv = process.argv.slice(2)) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      args[key] = true;
      continue;
    }
    args[key] = next;
    index += 1;
  }
  return args;
}

export function getTestingEnv() {
  return {
    API_URL: process.env.API_URL ?? envFileValues.API_URL ?? "http://127.0.0.1:54321",
    REST_URL: process.env.REST_URL ?? envFileValues.REST_URL ?? "http://127.0.0.1:54321/rest/v1",
    FUNCTIONS_URL: process.env.FUNCTIONS_URL ?? envFileValues.FUNCTIONS_URL ?? "http://127.0.0.1:54321/functions/v1",
    STUDIO_URL: process.env.STUDIO_URL ?? envFileValues.STUDIO_URL ?? "http://127.0.0.1:54323",
    LOCAL_DB_CONTAINER: process.env.LOCAL_DB_CONTAINER ?? envFileValues.LOCAL_DB_CONTAINER ?? "supabase_db_payrolleazy-localtest"
  };
}

export async function fileExists(targetPath) {
  try {
    await access(targetPath);
    return true;
  } catch {
    return false;
  }
}

export async function listFilesRecursive(rootPath, predicate) {
  if (!(await fileExists(rootPath))) return [];
  const entries = await readdir(rootPath, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const fullPath = path.join(rootPath, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await listFilesRecursive(fullPath, predicate)));
      continue;
    }
    if (!predicate || predicate(fullPath)) files.push(fullPath);
  }
  return files.sort();
}

export async function readJson(targetPath) {
  const content = await readFile(targetPath, "utf8");
  return JSON.parse(content.replace(/^\uFEFF/, ""));
}

export function replaceTokens(value, env) {
  if (typeof value === "string") {
    return value.replace(/\{\{([A-Z0-9_]+)\}\}/g, (_, key) => env[key] ?? "");
  }
  if (Array.isArray(value)) {
    return value.map((item) => replaceTokens(item, env));
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, replaceTokens(item, env)]));
  }
  return value;
}

export function printSection(title) {
  console.log(`\n== ${title} ==`);
}

export async function runCommand(command, args, options = {}) {
  const { cwd = repoRoot, input } = options;
  return await new Promise((resolve) => {
    const child = spawn(command, args, { cwd, stdio: "pipe" });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("close", (code) => resolve({ code, stdout, stderr }));
    child.on("error", (error) => resolve({ code: 1, stdout, stderr: String(error) }));
    if (typeof input === "string") {
      child.stdin.write(input);
    }
    child.stdin.end();
  });
}

function parseEnvFile(content) {
  const values = {};
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const delimiterIndex = line.indexOf("=");
    if (delimiterIndex === -1) continue;
    const key = line.slice(0, delimiterIndex).trim();
    let value = line.slice(delimiterIndex + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return values;
}

function loadTestingEnvFiles() {
  const merged = {};
  for (const candidate of [".env", ".env.test"]) {
    const filePath = path.join(repoRoot, candidate);
    if (!existsSync(filePath)) continue;
    Object.assign(merged, parseEnvFile(readFileSync(filePath, "utf8")));
  }
  return merged;
}
