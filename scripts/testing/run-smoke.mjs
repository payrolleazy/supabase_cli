import { getTestingEnv, parseArgs } from "./lib/core.mjs";
import { runSmokeSuite } from "./lib/suites.mjs";

const args = parseArgs();
const env = getTestingEnv();
await runSmokeSuite({ env, ...args });
