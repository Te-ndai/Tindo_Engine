#!/usr/bin/env bash
set -euo pipefail

# Ensure baseline report exists
./runtime/bin/ops report >/dev/null

# Append event to create STALE
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

# Runbook should resolve staleness and exit 0
./runtime/bin/runbook >/dev/null

test -f runtime/state/reports/diagnose.txt || { echo "FAIL: missing diagnose.txt"; exit 1; }
grep -q '^DIAGNOSE ' runtime/state/reports/diagnose.txt || { echo "FAIL: report missing header"; exit 1; }

echo "✅ Phase 82 TEST PASS"
