#!/usr/bin/env bash
set -euo pipefail

ROOT="."

"$ROOT/runtime/bin/rebuild_projections" >/dev/null

S="$ROOT/runtime/state/projections/system_status.json"
test -f "$S" || { echo "ERROR: system_status missing"; exit 1; }

python3 - <<'PY'
import json, sys

d=json.load(open("runtime/state/projections/system_status.json","r",encoding="utf-8"))

# Required fields
for k in ["projection","ok","checked_at_utc","projections","errors"]:
    if k not in d:
        print("FAIL: missing", k); sys.exit(1)

if d["projection"] != "system_status":
    print("FAIL: projection name wrong"); sys.exit(1)

if d["ok"] not in (0,1):
    print("FAIL: ok must be 0/1"); sys.exit(1)

if not isinstance(d["projections"], list):
    print("FAIL: projections must be list"); sys.exit(1)

# Must include rows for at least the projections we know exist
names=set([x.get("name") for x in d["projections"] if isinstance(x, dict)])
for must in ["executions_summary","commands_summary","system_status"]:
    if must not in names:
        print("FAIL: missing projection row:", must); sys.exit(1)

# If ok==1 then errors must be empty and all enabled projections must be OK or SKIPPED
if d["ok"] == 1:
    if d["errors"]:
        print("FAIL: ok=1 but errors not empty"); sys.exit(1)
    bad=[x for x in d["projections"] if isinstance(x, dict) and x.get("status")=="FAIL"]
    if bad:
        print("FAIL: ok=1 but some projections FAIL"); sys.exit(1)

print("PASS: system_status sane, ok=", d["ok"])
PY

echo "✅ Phase 65 TEST PASS"
