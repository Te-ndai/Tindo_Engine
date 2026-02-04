#!/usr/bin/env bash
set -euo pipefail
mkdir -p test/tmp

# Ensure checkpoint exists (init if missing)
if [ ! -f runtime/state/logs/executions.chain.checkpoint.json ]; then
  rm -f runtime/state/logs/executions.chain.jsonl
  ./runtime/bin/logchain_init >/dev/null
fi

# Also ensure chain is up to date with source
./runtime/bin/logchain_append >/dev/null || true

# Baseline: status OK
./runtime/bin/ops status >/dev/null

# Tamper checkpoint: flip last_line_sha256
CP="runtime/state/logs/executions.chain.checkpoint.json"
cp "$CP" test/tmp/cp.bak

python3 - <<'PY'
import json
p="runtime/state/logs/executions.chain.checkpoint.json"
d=json.load(open(p,"r",encoding="utf-8"))
d["last_line_sha256"]="f"*64
json.dump(d, open(p,"w",encoding="utf-8"), indent=2, sort_keys=True)
open(p,"a",encoding="utf-8").write("\n")
print("OK: tampered checkpoint")
PY

# ops status must FAIL (exit 20)
set +e
./runtime/bin/ops status >/dev/null
code=$?
set -e
if [ "$code" -ne 20 ]; then
  echo "FAIL: expected ops status 20 when checkpoint tampered, got $code"
  cp test/tmp/cp.bak "$CP"
  exit 1
fi
echo "PASS: ops status fails when checkpoint tampered"

# Restore checkpoint and verify OK
cp test/tmp/cp.bak "$CP"
./runtime/bin/ops status >/dev/null

echo "✅ Phase 76 TEST PASS"
