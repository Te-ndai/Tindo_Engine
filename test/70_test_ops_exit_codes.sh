#!/usr/bin/env bash
set -euo pipefail

# Baseline rebuild -> should be OK
./runtime/bin/rebuild_projections >/dev/null
./runtime/bin/ops status >/dev/null
echo "PASS: ops status OK baseline"

# Append event to make projections stale
python3 - <<'PY'
import json, hashlib
from datetime import datetime, timezone

t = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
req = {"command":"noop"}
sha = hashlib.sha256(json.dumps(req, sort_keys=True).encode("utf-8")).hexdigest()
ev = {
  "event_type":"execution",
  "event_time_utc": t,
  "command":"noop",
  "status":"PASS",
  "exit_code": 0,
  "request_sha256": sha,
  "response": {"command":"noop","ok": True, "result": None}
}
with open("runtime/state/logs/executions.jsonl","a",encoding="utf-8") as f:
    f.write(json.dumps(ev, sort_keys=True) + "\n")
print("OK: appended new event at", t)
PY

# ops status should exit 10
set +e
./runtime/bin/ops status >/dev/null
code=$?
set -e
if [ "$code" -ne 10 ]; then
  echo "FAIL: expected ops status exit 10, got $code"
  exit 1
fi
echo "PASS: ops status STALE exit code=10"

# ops freshen should exit 0
./runtime/bin/ops freshen >/dev/null
echo "PASS: ops freshen fixed staleness"

echo "✅ Phase 70 TEST PASS"
