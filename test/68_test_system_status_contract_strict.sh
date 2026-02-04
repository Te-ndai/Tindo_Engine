#!/usr/bin/env bash
set -euo pipefail

ROOT="."
PAY="$ROOT/runtime/schema/projection_payload_contracts.json"
BACK="$ROOT/test/tmp/_pay68_backup.json"
mkdir -p "$ROOT/test/tmp"

cp "$PAY" "$BACK"
cleanup(){ cp "$BACK" "$PAY" || true; }
trap cleanup EXIT

# Add bogus required field to system_status payload contract
python3 - <<'PY'
import json
p="runtime/schema/projection_payload_contracts.json"
d=json.load(open(p,"r",encoding="utf-8"))
c=d["contracts"]["system_status"]
req=c.get("required_fields", [])
if "bogus_field" not in req:
    req.append("bogus_field")
c["required_fields"]=req
json.dump(d, open(p,"w",encoding="utf-8"), indent=2, sort_keys=True)
open(p,"a",encoding="utf-8").write("\n")
print("OK: injected bogus_field")
PY

if "$ROOT/runtime/bin/rebuild_projections" system_status >/dev/null 2>&1; then
  echo "FAIL: system_status rebuild succeeded despite bogus contract"
  exit 1
fi

echo "PASS: strict contract rejected invalid system_status output"
echo "✅ Phase 68 TEST PASS"
