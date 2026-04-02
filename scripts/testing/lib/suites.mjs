import path from "node:path";
import { readFile } from "node:fs/promises";
import { fileExists, getTestingEnv, listFilesRecursive, printSection, readJson, replaceTokens, repoRoot, runCommand } from "./core.mjs";

async function fetchWithCheck(url, options, expectedStatus) {
  const response = await fetch(url, options);
  const body = await response.text();
  return {
    ok: response.status === expectedStatus,
    status: response.status,
    body
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchWithRetry({ url, options, expectedStatus, retries = 1, delayMs = 0 }) {
  let lastResult = null;
  for (let attempt = 1; attempt <= retries; attempt += 1) {
    lastResult = await fetchWithCheck(url, options, expectedStatus);
    if (lastResult.ok) {
      return lastResult;
    }
    if (attempt < retries && delayMs > 0) {
      await sleep(delayMs);
    }
  }
  return lastResult;
}

function parseEnvContent(content) {
  const values = {};
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const delimiterIndex = line.indexOf("=");
    if (delimiterIndex === -1) continue;
    const key = line.slice(0, delimiterIndex).trim();
    let value = line.slice(delimiterIndex + 1).trim();
    if ((value.startsWith("\"") && value.endsWith("\"")) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return values;
}

async function loadFunctionsEnv(context) {
  const envPath = context.LOCAL_FUNCTIONS_ENV_PATH;
  if (!envPath || !(await fileExists(envPath))) {
    return {};
  }
  const content = await readFile(envPath, "utf8");
  return parseEnvContent(content);
}

function getNestedValue(payload, pathExpression) {
  return pathExpression.split(".").reduce((current, segment) => {
    if (current && typeof current === "object" && !Array.isArray(current) && Object.prototype.hasOwnProperty.call(current, segment)) {
      return current[segment];
    }
    return undefined;
  }, payload);
}

function parseTap(output) {
  const lines = output.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  const planLine = lines.find((line) => /^1\.\.[0-9]+$/.test(line));
  const planned = planLine ? Number(planLine.split("..", 2)[1]) : null;
  const okLines = lines.filter((line) => /^ok\b/i.test(line));
  const notOkLines = lines.filter((line) => /^not ok\b/i.test(line));
  const executed = okLines.length + notOkLines.length;
  const ok = planned !== null && notOkLines.length === 0 && executed === planned;
  return { ok, planned, executed, notOkLines, lines };
}

async function resolveLocalDbContainer(env) {
  const requested = env.LOCAL_DB_CONTAINER?.trim();
  const list = await runCommand("docker", ["ps", "--format", "{{.Names}}"]); 
  if (list.code !== 0) {
    throw new Error(`Unable to inspect local Docker containers. ${list.stderr || list.stdout}`.trim());
  }

  const dbContainers = list.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((name) => /^supabase_db_/i.test(name));

  if (requested && dbContainers.includes(requested)) {
    return requested;
  }

  if (dbContainers.length === 1) {
    return dbContainers[0];
  }

  throw new Error(
    requested
      ? `Configured local database container '${requested}' was not found. Active Supabase DB containers: ${dbContainers.join(", ") || "none"}.`
      : `Unable to resolve the local database container automatically. Active Supabase DB containers: ${dbContainers.join(", ") || "none"}.`,
  );
}

async function resolveTestingEnv(env = getTestingEnv()) {
  return {
    ...env,
    LOCAL_DB_CONTAINER: await resolveLocalDbContainer(env),
  };
}

function parseJsonTail(output, label) {
  const lines = output.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  if (lines.length === 0) return {};

  const tail = lines.at(-1);
  try {
    const parsed = JSON.parse(tail);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error(`${label} returned a non-object JSON payload.`);
    }
    return parsed;
  } catch (error) {
    throw new Error(`${label} did not return a JSON object tail.\n${output}\n${error instanceof Error ? error.message : String(error)}`);
  }
}

async function resolveSqlHookSource(hook, context) {
  if (hook.setup_sql_file || hook.teardown_sql_file) {
    const relativePath = hook.setup_sql_file || hook.teardown_sql_file;
    const filePath = path.join(repoRoot, relativePath);
    const content = await readFile(filePath, "utf8");
    return replaceTokens(content, context);
  }

  if (hook.setup_sql || hook.teardown_sql) {
    return replaceTokens(hook.setup_sql || hook.teardown_sql, context);
  }

  return null;
}

async function runSqlHook({ env, hook, context, label }) {
  const sql = await resolveSqlHookSource(hook, context);
  if (!sql) return {};

  const result = await runCommand(
    "docker",
    ["exec", "-i", env.LOCAL_DB_CONTAINER, "psql", "-U", "postgres", "-d", "postgres", "-t", "-A", "-q", "-v", "ON_ERROR_STOP=1", "-f", "-"],
    { input: sql },
  );

  if (result.code !== 0) {
    throw new Error(`${label} failed.\n${result.stderr || result.stdout}`);
  }

  return parseJsonTail(result.stdout, label);
}

async function runHttpHook({ hook, context, label }) {
  const hooks = Array.isArray(hook) ? hook : [hook];
  let accumulated = {};

  for (const currentHook of hooks) {
    const secretContext = await loadFunctionsEnv({ ...context, ...accumulated });
    const resolved = replaceTokens(currentHook, { ...context, ...secretContext, ...accumulated });
    const requestOptions = {
      method: resolved.method ?? "GET",
      headers: resolved.headers ?? {},
    };

    if (resolved.body !== undefined) {
      requestOptions.body = typeof resolved.body === "string" ? resolved.body : JSON.stringify(resolved.body);
      if (!requestOptions.headers["Content-Type"]) {
        requestOptions.headers["Content-Type"] = "application/json";
      }
    }

    const response = await fetch(resolved.url, requestOptions);
    const responseText = await response.text();
    if (response.status !== resolved.expect_status) {
      throw new Error(`${label} expected ${resolved.expect_status} but got ${response.status} for ${resolved.url}\n${responseText}`);
    }
    if (resolved.expect_contains && !responseText.includes(resolved.expect_contains)) {
      throw new Error(`${label} did not include expected text '${resolved.expect_contains}'.`);
    }

    if (resolved.response_tokens) {
      let parsed = {};
      if (responseText.trim()) {
        try {
          parsed = JSON.parse(responseText);
        } catch (error) {
          throw new Error(`${label} response token capture requires a JSON response.\n${responseText}\n${error instanceof Error ? error.message : String(error)}`);
        }
      }

      for (const [tokenName, tokenPath] of Object.entries(resolved.response_tokens)) {
        const tokenValue = getNestedValue(parsed, tokenPath);
        if (tokenValue === undefined || tokenValue === null || tokenValue === "") {
          throw new Error(`${label} could not resolve response token '${tokenName}' from path '${tokenPath}'.`);
        }
        accumulated[tokenName] = typeof tokenValue === "string" ? tokenValue : JSON.stringify(tokenValue);
      }
    }

    console.log(`PASS ${label} ${resolved.url} -> ${response.status}`);
  }

  return accumulated;
}

export async function runSmokeSuite({ env = getTestingEnv() } = {}) {
  printSection("Smoke");
  const resolvedEnv = await resolveTestingEnv(env);
  const dbReady = await runCommand("docker", ["exec", resolvedEnv.LOCAL_DB_CONTAINER, "pg_isready", "-U", "postgres", "-d", "postgres"]);
  if (dbReady.code !== 0) {
    throw new Error(`Local database container is not ready. ${dbReady.stderr || dbReady.stdout}`.trim());
  }

  const checks = [
    { label: "Studio", url: resolvedEnv.STUDIO_URL, status: 200, retries: 15, delayMs: 1000 },
    { label: "REST", url: `${resolvedEnv.REST_URL}/`, status: 200, retries: 15, delayMs: 1000 }
  ];

  for (const check of checks) {
    const result = await fetchWithRetry({
      url: check.url,
      options: { method: "GET" },
      expectedStatus: check.status,
      retries: check.retries ?? 1,
      delayMs: check.delayMs ?? 0
    });
    if (!result.ok) {
      throw new Error(`${check.label} health check failed with status ${result.status} at ${check.url}`);
    }
    console.log(`PASS ${check.label} ${check.url} -> ${result.status}`);
  }

  console.log("PASS Local database container is ready");
}

export async function runGatewaySuites({ env = getTestingEnv(), suiteCode, moduleCode } = {}) {
  printSection("Gateway");
  const resolvedEnv = await resolveTestingEnv(env);
  const suitesRoot = path.join(repoRoot, "testing", "gateway", "suites");
  const suiteFiles = await listFilesRecursive(suitesRoot, (targetPath) => targetPath.endsWith(".json"));
  if (suiteFiles.length === 0) {
    console.log("No gateway suites configured.");
    return;
  }

  const suites = [];
  for (const filePath of suiteFiles) {
    const suite = await readJson(filePath);
    suite.file_path = filePath;
    suites.push(suite);
  }

  const filtered = suites.filter((suite) => {
    if (suiteCode && suite.suite_code !== suiteCode) return false;
    if (moduleCode && suite.module_code !== moduleCode && suite.module_code !== "shared") return false;
    return true;
  });

  if (filtered.length === 0) {
    console.log("No matching gateway suites found.");
    return;
  }

  for (const suite of filtered) {
    console.log(`Suite ${suite.suite_code}: ${suite.description}`);
    let suiteContext = { ...resolvedEnv };
    if (suite.setup_http) {
      suiteContext = {
        ...suiteContext,
        ...(await runHttpHook({
          hook: suite.setup_http,
          context: suiteContext,
          label: `Gateway suite ${suite.suite_code} HTTP setup`,
        })),
      };
    }
    if (suite.setup_sql || suite.setup_sql_file) {
      suiteContext = {
        ...suiteContext,
        ...(await runSqlHook({
          env: resolvedEnv,
          hook: suite,
          context: suiteContext,
          label: `Gateway suite ${suite.suite_code} setup`,
        })),
      };
    }

    try {
      for (const testCase of suite.cases ?? []) {
        let caseContext = { ...suiteContext };
        if (testCase.setup_http) {
          caseContext = {
            ...caseContext,
            ...(await runHttpHook({
              hook: testCase.setup_http,
              context: caseContext,
              label: `Gateway case ${testCase.case_id} HTTP setup`,
            })),
          };
        }
        if (testCase.setup_sql || testCase.setup_sql_file) {
          caseContext = {
            ...caseContext,
            ...(await runSqlHook({
              env: resolvedEnv,
              hook: testCase,
              context: caseContext,
              label: `Gateway case ${testCase.case_id} setup`,
            })),
          };
        }

        try {
          const resolved = replaceTokens(testCase, caseContext);
          const requestOptions = {
            method: resolved.method ?? "GET",
            headers: resolved.headers ?? {}
          };
          if (resolved.body) {
            requestOptions.body = typeof resolved.body === "string" ? resolved.body : JSON.stringify(resolved.body);
            if (!requestOptions.headers["Content-Type"]) {
              requestOptions.headers["Content-Type"] = "application/json";
            }
          }
          const response = await fetch(resolved.url, requestOptions);
          const responseText = await response.text();
          if (response.status !== resolved.expect_status) {
            throw new Error(`Gateway case ${resolved.case_id} expected ${resolved.expect_status} but got ${response.status} for ${resolved.url}`);
          }
          if (resolved.expect_contains && !responseText.includes(resolved.expect_contains)) {
            throw new Error(`Gateway case ${resolved.case_id} did not include expected text '${resolved.expect_contains}'.`);
          }
          console.log(`PASS ${resolved.case_id} ${resolved.url} -> ${response.status}`);
        } finally {
          if (testCase.teardown_sql || testCase.teardown_sql_file) {
            await runSqlHook({
              env: resolvedEnv,
              hook: { teardown_sql: testCase.teardown_sql, teardown_sql_file: testCase.teardown_sql_file },
              context: caseContext,
              label: `Gateway case ${testCase.case_id} teardown`,
            });
          }
          if (testCase.teardown_http) {
            await runHttpHook({
              hook: testCase.teardown_http,
              context: caseContext,
              label: `Gateway case ${testCase.case_id} HTTP teardown`,
            });
          }
        }
      }
    } finally {
      if (suite.teardown_sql || suite.teardown_sql_file) {
        await runSqlHook({
          env: resolvedEnv,
          hook: { teardown_sql: suite.teardown_sql, teardown_sql_file: suite.teardown_sql_file },
          context: suiteContext,
          label: `Gateway suite ${suite.suite_code} teardown`,
        });
      }
      if (suite.teardown_http) {
        await runHttpHook({
          hook: suite.teardown_http,
          context: suiteContext,
          label: `Gateway suite ${suite.suite_code} HTTP teardown`,
        });
      }
    }
  }
}

export async function runPgTapSuites({ env = getTestingEnv(), moduleCode } = {}) {
  printSection("pgTAP");
  const resolvedEnv = await resolveTestingEnv(env);
  const testsRoot = path.join(repoRoot, "supabase", "tests", "pgtap");
  const testFiles = await listFilesRecursive(testsRoot, (targetPath) => targetPath.endsWith(".sql"));
  const filtered = testFiles.filter((filePath) => {
    if (!moduleCode) return true;
    return filePath.toLowerCase().includes(`\\${moduleCode.toLowerCase()}\\`) || filePath.toLowerCase().includes(`/${moduleCode.toLowerCase()}/`);
  });

  if (filtered.length === 0) {
    console.log("No pgTAP suites matched the requested scope.");
    return;
  }

  for (const filePath of filtered) {
    const sql = await readFile(filePath, "utf8");
    const result = await runCommand("docker", ["exec", "-i", resolvedEnv.LOCAL_DB_CONTAINER, "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-f", "-"], { input: sql });
    if (result.code !== 0) {
      throw new Error(`pgTAP SQL execution failed for ${path.basename(filePath)}\n${result.stderr || result.stdout}`);
    }
    const tap = parseTap(result.stdout);
    if (!tap.ok) {
      throw new Error(`pgTAP assertions failed for ${path.basename(filePath)}\n${result.stdout}`);
    }
    console.log(`PASS ${path.basename(filePath)} -> ${tap.executed}/${tap.planned}`);
  }
}

export async function runLoadSuites({ moduleCode } = {}) {
  printSection("Load");
  const suitesRoot = path.join(repoRoot, "testing", "load", "suites");
  const suiteFiles = await listFilesRecursive(suitesRoot, (targetPath) => targetPath.endsWith(".json"));
  const filtered = suiteFiles.filter((filePath) => {
    if (!moduleCode) return true;
    return filePath.toLowerCase().includes(moduleCode.toLowerCase());
  });
  if (filtered.length === 0) {
    console.log("No load suites configured yet.");
    return;
  }
  throw new Error("Load suite execution is not configured yet. Add explicit pgbench or HTTP load suite definitions before enabling this step.");
}

export async function runCertification({ env = getTestingEnv(), moduleCode } = {}) {
  printSection("Certification");
  const manifestsRoot = path.join(repoRoot, "testing", "manifests", "modules");
  const manifestFiles = await listFilesRecursive(manifestsRoot, (targetPath) => targetPath.endsWith(".json"));
  const filtered = manifestFiles.filter((filePath) => {
    if (!moduleCode) return true;
    return path.basename(filePath, ".json").toLowerCase() === moduleCode.toLowerCase();
  });
  if (filtered.length === 0) {
    throw new Error(`No certification manifest found for module scope '${moduleCode ?? "all"}'.`);
  }

  let sharedSmokeDone = false;
  for (const filePath of filtered) {
    const manifest = await readJson(filePath);
    console.log(`Module ${manifest.module_code}: ${manifest.display_name}`);
    for (const suite of manifest.suite_order ?? []) {
      if (suite.mode === "not_applicable" || suite.mode === "not_configured") {
        console.log(`SKIP ${suite.suite_type} ${suite.suite_code}: ${suite.reason}`);
        continue;
      }
      if (suite.suite_type === "smoke") {
        if (!sharedSmokeDone) {
          await runSmokeSuite({ env });
          sharedSmokeDone = true;
        } else {
          console.log("PASS shared smoke already executed");
        }
        continue;
      }
      if (suite.suite_type === "pgtap") {
        await runPgTapSuites({ env, moduleCode: manifest.module_code });
        continue;
      }
      if (suite.suite_type === "gateway") {
        await runGatewaySuites({ env, moduleCode: manifest.module_code, suiteCode: suite.suite_code });
        continue;
      }
      if (suite.suite_type === "load") {
        await runLoadSuites({ moduleCode: manifest.module_code });
        continue;
      }
      throw new Error(`Unsupported suite type '${suite.suite_type}' in ${path.basename(filePath)}.`);
    }
  }
}

