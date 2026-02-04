#!/usr/bin/env bash
set -euo pipefail

./runtime/bin/ops report >/dev/null

test -f runtime/state/reports/diagnose.txt || { echo "FAIL: missing diagnose.txt"; exit 1; }
test -f runtime/state/reports/diagnose.json || { echo "FAIL: missing diagnose.json"; exit 1; }

grep -q '^DIAGNOSE ' runtime/state/reports/diagnose.txt || { echo "FAIL: diagnose.txt missing header"; exit 1; }
grep -q '^\[' runtime/state/reports/diagnose.txt || { echo "FAIL: diagnose.txt missing findings"; exit 1; }

echo "✅ Phase 80 TEST PASS"
