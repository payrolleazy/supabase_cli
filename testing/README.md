# Testing Stack

This directory contains the permanent reusable certification assets for the `supabase_payrolleazy` backend.

The stack is split into four layers:
- `manifests/modules`
  Defines module-by-module certification order and which suites are required.
- `gateway/suites`
  JSON suites for API and gateway request/response verification.
- `load/suites`
  Reserved for explicit load definitions once pgbench or HTTP load packs are authored.
- `supabase/tests/pgtap`
  SQL-first pgTAP proof packs that validate schema and backend contracts inside Postgres.

## Routine usage

1. `npx supabase start`
2. `npx supabase db reset`
3. `npm test`

## Module usage

Run one module certification pack:

```bash
npm run test:module -- --module F01
```

Run one layer only:

```bash
npm run test:pgtap -- --module F01
npm run test:gateway -- --suite shared-local-health
```

## Coverage status

Initial coverage in this repository:
- `F01` certification manifest
- `F01` pgTAP baseline pack
- shared local gateway health suite

Every new module should add:
- one module manifest
- one or more pgTAP packs
- gateway suites where applicable
- load suites when the module reaches performance certification
