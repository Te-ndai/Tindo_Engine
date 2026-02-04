#!/usr/bin/env bash
set -euo pipefail

f="test/02_test.sh"
[ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }

if grep -q 'Command Registry Tests' "$f"; then
  echo "OK: command registry checks already present."
  exit 0
fi

# Insert checks before the final PASS writer:
# We insert just before the line that starts with 'write_result "PASS"'
tmp="$(mktemp)"
awk '
  BEGIN{inserted=0}
  /^write_result "PASS"/ && inserted==0 {
    print ""
    print "# -----------------------------"
    print "# Phase 0.5 — Command Registry Tests"
    print "# -----------------------------"
    print "[ -f \"runtime/schema/command_registry.json\" ] || fail \"missing runtime/schema/command_registry.json\""
    print "[ -s \"runtime/schema/command_registry.json\" ] || fail \"command_registry.json empty\""
    print "[ -f \"runtime/core/executor.py\" ] || fail \"missing runtime/core/executor.py\""
    print "grep -q '\"contract\"[[:space:]]*:[[:space:]]*\"command_registry\"' runtime/schema/command_registry.json || fail \"command_registry missing contract tag\""
    print "grep -q '\"commands\"' runtime/schema/command_registry.json || fail \"command_registry missing commands\""
    print "add_check \"command registry contract + executor stub exist\""
    print "pass \"command registry contract + executor.py OK\""
    inserted=1
  }
  {print}
' "$f" > "$tmp"
mv "$tmp" "$f"

chmod +x "$f"
echo "OK: inserted command registry checks into test/02_test.sh"
