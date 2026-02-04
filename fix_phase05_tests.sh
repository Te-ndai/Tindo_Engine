#!/usr/bin/env bash
set -euo pipefail

f="test/02_test.sh"
[ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }

# 1) Set phase marker to 0.5 in write_result JSON
sed -i 's/"phase": "0\.4"/"phase": "0.5"/g' "$f"

# 2) Replace the broken Phase 0.5 block completely (lines from marker to end)
# We match from the Phase 0.5 header to end-of-file and replace.
perl -0777 -i -pe 's/# -----------------------------\n# Phase 0\.5 — Command Registry Tests\n# -----------------------------.*\z/# -----------------------------\n# Phase 0.5 — Command Registry Tests\n# -----------------------------\n[ -f "runtime\/schema\/command_registry.json" ] || fail "missing runtime\/schema\/command_registry.json"\n[ -s "runtime\/schema\/command_registry.json" ] || fail "command_registry.json empty"\n[ -f "runtime\/core\/executor.py" ] || fail "missing runtime\/core\/executor.py"\n\ngrep -qE "\"contract\"[[:space:]]*:[[:space:]]*\"command_registry\"" runtime\/schema\/command_registry.json || fail "command_registry missing contract tag"\ngrep -qE "\"commands\"" runtime\/schema\/command_registry.json || fail "command_registry missing commands"\n\nadd_check "command registry contract + executor stub exist"\npass "command registry contract + executor.py OK"\n\nwrite_result "PASS" "all checks passed"\necho "✅ Phase 0.5 TEST PASS"\necho "Wrote: logs\/test.results.json"\n/s' "$f"

chmod +x "$f"
echo "OK: fixed Phase 0.5 command registry checks + bumped phase to 0.5"
