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

Use `{{API_URL}}`, `{{REST_URL}}`, `{{FUNCTIONS_URL}}`, and `{{STUDIO_URL}}` tokens when you want the runner to inject the current local environment values.
