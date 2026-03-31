# pgTAP Suites

This directory contains database-native certification packs executed inside the local Supabase Postgres container.

Conventions:
- create one folder per module
- keep files numerically ordered
- use `create extension if not exists pgtap with schema extensions;`
- wrap each file in `begin; ... rollback;` so the suite is side-effect free
- focus on schema, contract, grants, and function behavior that can be proven inside Postgres
