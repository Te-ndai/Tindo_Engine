#!/usr/bin/env bash
set -euo pipefail

ROOT=""

# Baseline rebuild
./runtime/bin/rebuild_projections >/dev/null

# Append a new execution event to make projections stale
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

# Confirm stale (status-only rebuild)
./runtime/bin/rebuild_projections system_status >/dev/null

python3 - <<'PY'
import json, sys
d=json.load(open("runtime/state/projections/system_status.json","r",encoding="utf-8"))
rows={r["name"]:r for r in d["projections"] if isinstance(r,dict) and "name" in r}
for n in ("executions_summary","commands_summary"):
    if rows.get(n,{}).get("status") != "STALE":
        print("FAIL: expected", n, "STALE"); sys.exit(1)
print("OK: stale confirmed")
PY

# Run make_fresh -> should clear stale
./runtime/bin/make_fresh >/dev/null

python3 - <<'PY'
import json, sys
d=json.load(open("runtime/state/projections/system_status.json","r",encoding="utf-8"))
bad=[r for r in d["projections"] if isinstance(r,dict) and r.get("status") in ("FAIL","STALE")]
if bad:
    print("FAIL: still unhealthy", bad); sys.exit(1)
print("PASS: make_fresh cleared stale")
PY

echo "✅ Phase 69 TEST PASS"
