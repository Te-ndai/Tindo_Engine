#!/usr/bin/env bash
set -euo pipefail

mkdir -p test/tmp

# Ensure chain exists and is valid
./runtime/bin/logchain_rebuild >/dev/null
./runtime/bin/logchain_verify >/dev/null

# status should be OK
./runtime/bin/ops status >/dev/null

# Tamper chain (flip one field)
CHAIN="runtime/state/logs/executions.chain.jsonl"
cp "$CHAIN" test/tmp/chain.bak

python3 - <<'PY'
import json, pathlib
p=pathlib.Path("runtime/state/logs/executions.chain.jsonl")
lines=p.read_text(encoding="utf-8").splitlines()
nonempty=[i for i,l in enumerate(lines) if l.strip()]
mid=nonempty[len(nonempty)//2]
ev=json.loads(lines[mid])
ev["command"]=str(ev.get("command","noop"))+"_TAMPER2"
lines[mid]=json.dumps(ev, sort_keys=True)
p.write_text("\n".join(lines)+"\n", encoding="utf-8")
print("OK: tampered chain")
PY

# ops status should FAIL (exit 20)
set +e
./runtime/bin/ops status >/dev/null
code=$?
set -e
if [ "$code" -ne 20 ]; then
  echo "FAIL: expected ops status exit 20 under tamper, got $code"
  exit 1
fi
echo "PASS: ops status fails under tamper"

# ops freshen should also FAIL (exit 20)
set +e
./runtime/bin/ops freshen >/dev/null
code=$?
set -e
if [ "$code" -ne 20 ]; then
  echo "FAIL: expected ops freshen exit 20 under tamper, got $code"
  exit 1
fi
echo "PASS: ops freshen gated by log integrity"

# Restore chain
cp test/tmp/chain.bak "$CHAIN"

# status should be OK again
./runtime/bin/ops status >/dev/null
echo "✅ Phase 74 TEST PASS"
