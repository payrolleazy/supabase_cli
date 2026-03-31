import { getTestingEnv, parseArgs } from "./lib/core.mjs";
import { runGatewaySuites } from "./lib/suites.mjs";

const args = parseArgs();
const env = getTestingEnv();
await runGatewaySuites({ env, suiteCode: args.suite, moduleCode: args.module });
