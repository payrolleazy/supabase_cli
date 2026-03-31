import { getTestingEnv, parseArgs } from "./lib/core.mjs";
import { runCertification } from "./lib/suites.mjs";

const args = parseArgs();
const env = getTestingEnv();
await runCertification({ env, moduleCode: args.module });
