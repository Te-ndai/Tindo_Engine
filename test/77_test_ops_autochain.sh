#!/usr/bin/env bash
set -euo pipefail

# Ensure chain initialized
if [ ! -f runtime/state/logs/executions.chain.checkpoint.json ]; then
  rm -f runtime/state/logs/executions.chain.jsonl
  ./runtime/bin/logchain_init >/dev/null
fi

# Baseline rebuild
./runtime/bin/rebuild_projections >/dev/null

# Append event to executions.jsonl ONLY (no manual logchain_append)
python3 - <<'PY'
import json, hashlib
from datetime import datetime, timezone

t = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
req={"command":"noop"}
sha=hashlib.sha256(json.dumps(req, sort_keys=True).encode()).hexdigest()
ev={
  "event_type":"execution",
  "event_time_utc":t,
  "command":"noop",
  "status":"PASS",
  "exit_code":0,
  "request_sha256":sha,
  "response":{"command":"noop","ok":True,"result":None}
}
with open("runtime/state/logs/executions.jsonl","a",encoding="utf-8") as f:
    f.write(json.dumps(ev, sort_keys=True)+"\n")
print("OK: appended event", t)
PY

# ops status should not FAIL due to chain mismatch; should be STALE (10)
set +e
./runtime/bin/ops status >/dev/null
code=$?
set -e
if [ "$code" -ne 10 ]; then
  echo "FAIL: expected ops status 10 (stale) after append, got $code"
  exit 1
fi
echo "PASS: ops autochained and returned STALE"

# ops freshen should restore OK
./runtime/bin/ops freshen >/dev/null
echo "✅ Phase 77 TEST PASS"
