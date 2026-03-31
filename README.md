# payrolleazy supabase cli

This repository is the permanent local testing and certification workspace for the `supabase_payrolleazy` backend.

Current scope:
- checked-in migration chain pulled from `supabase_payrolleazy`
- repeatable local Supabase CLI environment
- reusable smoke, gateway, pgTAP, and certification runners
- module manifests that define certification order
- GitHub Actions workflows for local certification and live deployment

## Local URLs

- Studio: `http://127.0.0.1:54323`
- API gateway: `http://127.0.0.1:54321`
- Mailpit: `http://127.0.0.1:54324`
- Local database: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`

## Core commands

- `npm test`
  Runs the shared smoke, pgTAP, gateway, and manifest-driven certification packs.
- `npm run test:module -- --module F01`
  Runs the manifest-defined certification flow for one module.
- `npm run test:pgtap -- --module F01`
  Runs only the pgTAP pack for one module.
- `npm run test:gateway -- --suite shared-local-health`
  Runs one gateway suite.
- `npm run test:load`
  Reserved for explicit load suites when they are authored.

## Local bootstrap

1. Start the local Supabase stack: `npx supabase start`
2. Reset from checked-in migrations: `npx supabase db reset`
3. Run the certification stack: `npm test`

If you keep a local `.env.test`, the runners will load it automatically. Use `.env.test.example` as the template.

## Required GitHub secrets

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_ID`
- `SUPABASE_DB_PASSWORD`
