import { parseArgs } from "./lib/core.mjs";
import { runLoadSuites } from "./lib/suites.mjs";

const args = parseArgs();
await runLoadSuites({ moduleCode: args.module });
