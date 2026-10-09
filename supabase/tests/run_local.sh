#!/usr/bin/env bash
# Applique stub Supabase + migrations + seed + tests sur une base locale jetable.
# Usage : PGHOST=... PGPORT=... PGUSER=postgres ./tests/run_local.sh
set -euo pipefail
cd "$(dirname "$0")/.."
dropdb --if-exists methe_test && createdb methe_test
run() { psql -X -q -v ON_ERROR_STOP=1 -d methe_test -f "$1"; }
run tests/supabase_stub.sql
for f in migrations/*.sql; do echo "→ $f"; run "$f"; done
echo "→ seed.sql"; run seed.sql
echo "→ tests"; run tests/test_schema.sql; run tests/test_deposits.sql; run tests/test_withdrawals.sql; run tests/test_draws.sql; run tests/test_bets.sql; run tests/test_risk.sql; run tests/test_support.sql; run tests/test_login.sql
echo "→ contrôles d'intégrité"; run tests/check_invariants.sql
