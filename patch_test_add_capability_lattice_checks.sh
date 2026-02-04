#!/usr/bin/env bash
set -euo pipefail

f="test/02_test.sh"
[ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }

# Only append once
if grep -q 'Capability Lattice Tests' "$f"; then
  echo "OK: capability lattice checks already present."
  exit 0
fi

cat >> "$f" <<'EOF'

# -----------------------------
# Phase 0.4 — Capability Lattice Tests
# -----------------------------
[ -f "runtime/schema/capability_lattice.json" ] || fail "missing runtime/schema/capability_lattice.json"
[ -s "runtime/schema/capability_lattice.json" ] || fail "capability_lattice.json is empty"
[ -f "runtime/core/capability.py" ] || fail "missing runtime/core/capability.py"
pass "capability lattice contract + capability.py exist"

# Quick structural checks (no jq)
grep -q '"contract"[[:space:]]*:[[:space:]]*"capability_lattice"' runtime/schema/capability_lattice.json || fail "capability_lattice.json missing contract tag"
grep -q '"meet_table"' runtime/schema/capability_lattice.json || fail "capability_lattice.json missing meet_table"
grep -q '"execution_valid_iff_meet_not_bottom"' runtime/schema/capability_lattice.json || fail "capability_lattice.json missing rule flag"
pass "capability lattice schema markers present"
EOF

echo "OK: appended capability lattice checks to test/02_test.sh"
