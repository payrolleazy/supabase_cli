import { getTestingEnv, parseArgs } from "./lib/core.mjs";
import { runPgTapSuites } from "./lib/suites.mjs";

const args = parseArgs();
const env = getTestingEnv();
await runPgTapSuites({ env, moduleCode: args.module });
