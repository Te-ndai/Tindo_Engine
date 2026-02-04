#!/usr/bin/env bash
set -euo pipefail
mkdir -p test/tmp

# Ensure status exists
./runtime/bin/ops status >/dev/null || true

# Case A: make stale -> diagnose should WARN with ops freshen action
python3 - <<'PY'
import json, hashlib
from datetime import datetime, timezone
t=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
req={"command":"noop"}
sha=hashlib.sha256(json.dumps(req, sort_keys=True).encode()).hexdigest()
ev={"event_type":"execution","event_time_utc":t,"command":"noop","status":"PASS","exit_code":0,"request_sha256":sha,"response":{"command":"noop","ok":True,"result":None}}
with open("runtime/state/logs/executions.jsonl","a",encoding="utf-8") as f:
    f.write(json.dumps(ev, sort_keys=True)+"\n")
print("OK: appended event", t)
PY

# ops diagnose should exit 10 (WARN)
set +e
./runtime/bin/ops diagnose >/dev/null
code=$?
set -e
if [ "$code" -ne 10 ]; then
  echo "FAIL: expected diagnose WARN exit 10, got $code"
  exit 1
fi
echo "PASS: diagnose warns on stale"

# Case B: tamper checkpoint -> diagnose should FAIL exit 20
CP="runtime/state/logs/executions.chain.checkpoint.json"
cp "$CP" test/tmp/cp.bak
python3 - <<'PY'
import json
p="runtime/state/logs/executions.chain.checkpoint.json"
d=json.load(open(p,"r",encoding="utf-8"))
d["last_line_sha256"]="e"*64
json.dump(d, open(p,"w",encoding="utf-8"), indent=2, sort_keys=True)
open(p,"a",encoding="utf-8").write("\n")
print("OK: tampered checkpoint")
PY

set +e
./runtime/bin/ops diagnose >/dev/null
code=$?
set -e
cp test/tmp/cp.bak "$CP"
if [ "$code" -ne 20 ]; then
  echo "FAIL: expected diagnose FAIL exit 20, got $code"
  exit 1
fi
echo "PASS: diagnose fails on log integrity"

echo "✅ Phase 78 TEST PASS"
