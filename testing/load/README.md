# Load Suites

This directory is reserved for explicit module load packs.

Load execution is intentionally opt-in. Do not add placeholder JSON files here, because the runner treats every JSON file as an executable suite. Add a load suite only when:
- the target module implementation is frozen in live `supabase_payrolleazy`
- the module has passed smoke, pgTAP, and gateway certification
- explicit throughput or concurrency expectations are known

Recommended future patterns:
- `pgbench` SQL scripts for database-heavy flows
- HTTP load definitions for gateway-heavy flows
