#!/usr/bin/env bash
set -euo pipefail

need_exec() {
  local p="$1"
  test -f "$p" || { echo "FAIL: missing file $p"; exit 1; }
  test -x "$p" || { echo "FAIL: not executable $p"; exit 1; }
}

need_file() {
  local p="$1"
  test -f "$p" || { echo "FAIL: missing file $p"; exit 1; }
}

need_exec runtime/bin/ops
need_exec runtime/bin/rebuild_projections
need_exec runtime/bin/make_fresh
need_exec runtime/bin/logchain_init
need_exec runtime/bin/logchain_append
need_exec runtime/bin/logchain_verify

need_file runtime/schema/projection_registry.json
need_file runtime/schema/projection_payload_contracts.json
need_file runtime/core/projections.py

# Registry contains projections
python3 - <<'PY'
import json, sys
reg=json.load(open("runtime/schema/projection_registry.json","r",encoding="utf-8"))
names=set(p.get("name") for p in reg.get("projections",[]) if isinstance(p,dict))
need={"executions_summary","commands_summary","system_status","diagnose"}
missing=sorted(need - names)
if missing:
    print("FAIL: registry missing projections:", missing)
    sys.exit(1)
print("PASS: registry projections present")
PY

# Payload contracts contain required
python3 - <<'PY'
import json, sys
pc=json.load(open("runtime/schema/projection_payload_contracts.json","r",encoding="utf-8"))
contracts=pc.get("contracts",{})
need={"system_status","diagnose"}
missing=[n for n in need if n not in contracts]
if missing:
    print("FAIL: payload contracts missing:", missing)
    sys.exit(1)
print("PASS: payload contracts present")
PY

# BUILDERS contains required
python3 - <<'PY'
import sys, re, pathlib
s=pathlib.Path("runtime/core/projections.py").read_text(encoding="utf-8")
# crude but effective: ensure BUILDERS map contains the keys
need=["executions_summary","commands_summary","system_status","diagnose"]
for n in need:
    if f'"{n}":' not in s:
        print("FAIL: BUILDERS missing", n)
        sys.exit(1)
print("PASS: BUILDERS keys present")
PY

echo "✅ Phase 79 TEST PASS"
