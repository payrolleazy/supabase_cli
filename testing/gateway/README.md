# Gateway Suites

Gateway suites are JSON files that drive the reusable HTTP runner in `scripts/testing/run-gateway.mjs`.

Each suite should define:
- `suite_code`
- `module_code`
- `description`
- `cases`

Each case should define:
- `case_id`
- `method`
- `url`
- `expect_status`

Optional fields:
- `headers`
- `body`
- `expect_contains`
- `setup_sql`
- `setup_sql_file`
- `teardown_sql`
- `teardown_sql_file`

Hook behavior:
- suite-level setup hooks run once before the suite begins
- case-level setup hooks run before the specific HTTP case
- case-level teardown hooks run after the specific HTTP case
- suite-level teardown hooks run after the suite finishes
- SQL hooks must return either no rows or a single JSON object tail that can be merged into token context

Token usage:
- Use `{{API_URL}}`, `{{REST_URL}}`, `{{FUNCTIONS_URL}}`, and `{{STUDIO_URL}}` when you want the runner to inject the current local environment values.
- SQL hook output can also provide additional tokens for later request bodies, headers, or URLs.

Local DB container:
- the runner now resolves the active local `supabase_db_*` container from the single primary local instance when the old fixed container name is not valid
