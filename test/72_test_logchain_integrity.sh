#!/usr/bin/env bash
set -euo pipefail

# Ensure temp dir exists
mkdir -p test/tmp

# Build chain, verify ok
./runtime/bin/logchain_rebuild
./runtime/bin/logchain_verify
echo "PASS: chain verifies after rebuild"

# Tamper: flip one field in a middle line (without updating hashes) -> verify must fail
CHAIN="runtime/state/logs/executions.chain.jsonl"
TMP="test/tmp/tampered.chain.jsonl"

python3 - <<'PY'
import json, pathlib, sys

src=pathlib.Path("runtime/state/logs/executions.chain.jsonl")
if not src.exists():
    print("ERROR: chain file missing")
    sys.exit(3)

lines=src.read_text(encoding="utf-8").splitlines()
# Need at least 3 lines to tamper safely
if len([l for l in lines if l.strip()]) < 3:
    raise SystemExit("SKIP: not enough lines to tamper (need >=3)")

# choose a middle non-empty line
nonempty=[i for i,l in enumerate(lines) if l.strip()]
mid=nonempty[len(nonempty)//2]

ev=json.loads(lines[mid])
ev["command"]= str(ev.get("command","noop")) + "_TAMPER"
lines[mid]=json.dumps(ev, sort_keys=True)

pathlib.Path("test/tmp/tampered.chain.jsonl").write_text("\n".join(lines)+"\n", encoding="utf-8")
print("OK: wrote tampered chain")
PY

# Run verifier against tampered file by temporarily swapping
mv "$CHAIN" "${CHAIN}.bak"
mv "$TMP" "$CHAIN"

set +e
./runtime/bin/logchain_verify >/dev/null
code=$?
set -e

# restore
mv "$CHAIN" "$TMP"
mv "${CHAIN}.bak" "$CHAIN"

if [ "$code" -eq 0 ]; then
  echo "FAIL: verifier accepted tampered chain"
  exit 1
fi

echo "PASS: verifier rejected tampered chain"
echo "✅ Phase 72 TEST PASS"
