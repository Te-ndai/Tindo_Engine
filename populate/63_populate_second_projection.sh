#!/usr/bin/env bash
set -euo pipefail

ROOT="."

REG="$ROOT/runtime/schema/projection_registry.json"
test -f "$REG" || { echo "ERROR: registry missing"; exit 1; }
test -f "$ROOT/runtime/core/projections.py" || { echo "ERROR: projections runtime missing"; exit 1; }

# 1) Extend registry with commands_summary
python3 - <<'PY'
import json

p="runtime/schema/projection_registry.json"
d=json.load(open(p,"r",encoding="utf-8"))

# Prevent duplicates
names={x.get("name") for x in d.get("projections", []) if isinstance(x, dict)}
if "commands_summary" not in names:
    d["projections"].append({
        "name": "commands_summary",
        "source_log": "runtime/state/logs/executions.jsonl",
        "output": "runtime/state/projections/commands_summary.json",
        "enabled": True
    })

json.dump(d, open(p,"w",encoding="utf-8"), indent=2, sort_keys=True)
open(p,"a",encoding="utf-8").write("\n")
print("OK: registry updated")
PY

# 2) Patch projections.py: add builder + register it in BUILDERS
# We patch by simple textual insertion. If your file drifted, paste it and I’ll do a safer patch.
python3 - <<'PY'
import re, pathlib

path = pathlib.Path("runtime/core/projections.py")
s = path.read_text(encoding="utf-8")

if "def build_commands_summary" not in s:
    # Insert builder after build_executions_summary
    m = re.search(r"(def build_executions_summary\(.*?\n\s*return out\n)", s, flags=re.S)
    if not m:
        raise SystemExit("ERROR: could not find build_executions_summary block to insert after")

    builder = r'''
def build_commands_summary(source_log: str) -> Dict[str, Any]:
    events = _iter_jsonl(source_log)

    total = 0
    by_command: Dict[str, int] = {}
    by_status: Dict[str, int] = {}
    last_time = None

    for ev in events:
        if not isinstance(ev, dict):
            continue
        if ev.get("event_type") != "execution":
            continue

        total += 1
        cmd = ev.get("command", "UNKNOWN")
        status = ev.get("status", "UNKNOWN")

        by_command[cmd] = by_command.get(cmd, 0) + 1
        by_status[status] = by_status.get(status, 0) + 1
        last_time = ev.get("event_time_utc")

    out = {
        "projection": "commands_summary",
        "source": source_log,
        "total": total,
        "last_event_time_utc": last_time,
        "by_command": by_command,
        "by_status": by_status,
        "last_n": []
    }
    return out
'''
    s = s[:m.end(1)] + builder + s[m.end(1):]

# Register in BUILDERS
if re.search(r'BUILDERS\s*=\s*{[^}]*"commands_summary"', s, flags=re.S) is None:
    s = re.sub(
        r'BUILDERS\s*=\s*{\s*\n\s*"executions_summary"\s*:\s*build_executions_summary,\s*\n\s*}',
        'BUILDERS = {\n    "executions_summary": build_executions_summary,\n    "commands_summary": build_commands_summary,\n}',
        s,
        flags=re.S
    )

path.write_text(s, encoding="utf-8")
print("OK: projections.py patched")
PY

echo "OK: phase 63 populate complete"
