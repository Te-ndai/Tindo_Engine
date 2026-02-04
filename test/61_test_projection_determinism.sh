#!/usr/bin/env bash
set -euo pipefail

ROOT="."
OUT="$ROOT/runtime/state/projections/executions_summary.json"
TMP1="$ROOT/runtime/state/cache/_proj_tmp_1.json"
TMP2="$ROOT/runtime/state/cache/_proj_tmp_2.json"

test -x "$ROOT/runtime/bin/rebuild_projections" || { echo "ERROR: rebuild_projections not executable"; exit 1; }
mkdir -p "$ROOT/runtime/state/cache"

# Rebuild #1
"$ROOT/runtime/bin/rebuild_projections" >/dev/null
test -f "$OUT" || { echo "ERROR: projection output missing"; exit 1; }
cp "$OUT" "$TMP1"

# Rebuild #2
"$ROOT/runtime/bin/rebuild_projections" >/dev/null
cp "$OUT" "$TMP2"

# Determinism check (byte-identical)
if ! cmp -s "$TMP1" "$TMP2"; then
  echo "FAIL: projection output is not deterministic"
  echo "Diff:"
  diff -u "$TMP1" "$TMP2" || true
  exit 1
fi

echo "PASS: projection rebuild is deterministic"

# Shape check (minimal)
python3 - <<'PY'
import json, sys
p="runtime/state/projections/executions_summary.json"
with open(p,"r",encoding="utf-8") as f:
    d=json.load(f)

req=["projection","source","total","last_event_time_utc","last_n"]
for k in req:
    if k not in d:
        print("FAIL: missing", k); sys.exit(1)

if not isinstance(d["last_n"], list):
    print("FAIL: last_n not list"); sys.exit(1)

print("PASS: projection shape ok, total=", d["total"])
PY

echo "✅ Phase 61 TEST PASS"
