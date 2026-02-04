#!/usr/bin/env bash
set -euo pipefail

ROOT="."

PAY="$ROOT/runtime/schema/projection_payload_contracts.json"
BACK="$ROOT/test/tmp/_payload_backup.json"

mkdir -p "$ROOT/test/tmp"

test -f "$PAY" || { echo "ERROR: payload contracts missing"; exit 1; }

cp "$PAY" "$BACK"
cleanup(){ cp "$BACK" "$PAY" || true; }
trap cleanup EXIT

# Remove commands_summary payload contract -> rebuild must FAIL
python3 - <<'PY'
import json
p="runtime/schema/projection_payload_contracts.json"
d=json.load(open(p,"r",encoding="utf-8"))
d["contracts"].pop("commands_summary", None)
json.dump(d, open(p,"w",encoding="utf-8"), indent=2, sort_keys=True)
open(p,"a",encoding="utf-8").write("\n")
print("OK: removed commands_summary payload contract")
PY

if "$ROOT/runtime/bin/rebuild_projections" >/dev/null 2>&1; then
  echo "FAIL: rebuild succeeded without commands_summary payload contract"
  exit 1
fi

echo "PASS: rebuild failed as expected when payload contract missing"

echo "✅ Phase 64 TEST PASS"
