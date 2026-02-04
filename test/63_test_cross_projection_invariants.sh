#!/usr/bin/env bash
set -euo pipefail

ROOT="."

"$ROOT/runtime/bin/rebuild_projections" >/dev/null

A="$ROOT/runtime/state/projections/executions_summary.json"
B="$ROOT/runtime/state/projections/commands_summary.json"

test -f "$A" || { echo "ERROR: missing $A"; exit 1; }
test -f "$B" || { echo "ERROR: missing $B"; exit 1; }

python3 - <<'PY'
import json, sys

def load(p):
    with open(p,"r",encoding="utf-8") as f:
        return json.load(f)

a=load("runtime/state/projections/executions_summary.json")
b=load("runtime/state/projections/commands_summary.json")

# Invariants
if a["total"] != b["total"]:
    print("FAIL: totals mismatch", a["total"], b["total"]); sys.exit(1)

for name, d in [("executions_summary", a), ("commands_summary", b)]:
    bc = d.get("by_command", {})
    bs = d.get("by_status", {})
    if sum(bc.values()) != d["total"]:
        print(f"FAIL: {name} sum(by_command) != total"); sys.exit(1)
    if sum(bs.values()) != d["total"]:
        print(f"FAIL: {name} sum(by_status) != total"); sys.exit(1)

print("PASS: cross-projection invariants hold, total=", a["total"])
PY

echo "✅ Phase 63 TEST PASS"
