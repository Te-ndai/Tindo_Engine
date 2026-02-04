#!/usr/bin/env bash
set -euo pipefail

ROOT="."
LOG="$ROOT/runtime/state/logs/executions.jsonl"

# Ensure clean baseline
"$ROOT/runtime/bin/rebuild_projections" >/dev/null

# Append a new execution event (valid shape)
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

# Rebuild ONLY system_status (do not rebuild projections) -> should detect stale
"$ROOT/runtime/bin/rebuild_projections" system_status >/dev/null

python3 - <<'PY'
import json, sys
d=json.load(open("runtime/state/projections/system_status.json","r",encoding="utf-8"))

rows={r["name"]: r for r in d["projections"] if isinstance(r, dict) and "name" in r}

# Expect stale on deterministic projections
for name in ["executions_summary","commands_summary"]:
    r=rows.get(name)
    if not r:
        print("FAIL: missing row", name); sys.exit(1)
    if r.get("status") != "STALE":
        print("FAIL:", name, "expected STALE got", r.get("status")); sys.exit(1)

print("PASS: staleness detected")
PY

echo "✅ Phase 67 TEST PASS"
