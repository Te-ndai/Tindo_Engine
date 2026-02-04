#!/usr/bin/env bash
set -euo pipefail

ROOT="."

REG="$ROOT/runtime/schema/projection_registry.json"
PAY="$ROOT/runtime/schema/projection_payload_contracts.json"
test -f "$REG" || { echo "ERROR: registry missing"; exit 1; }
test -f "$PAY" || { echo "ERROR: payload contracts missing"; exit 1; }
test -f "$ROOT/runtime/core/projections.py" || { echo "ERROR: projections runtime missing"; exit 1; }

# 1) Add system_status to registry
python3 - <<'PY'
import json

p="runtime/schema/projection_registry.json"
d=json.load(open(p,"r",encoding="utf-8"))
names={x.get("name") for x in d.get("projections", []) if isinstance(x, dict)}
if "system_status" not in names:
    d["projections"].append({
        "name": "system_status",
        "source_log": "",  # not log-based
        "output": "runtime/state/projections/system_status.json",
        "enabled": True
    })
json.dump(d, open(p,"w",encoding="utf-8"), indent=2, sort_keys=True)
open(p,"a",encoding="utf-8").write("\n")
print("OK: registry updated with system_status")
PY

# 2) Add payload contract for system_status
python3 - <<'PY'
import json

p="runtime/schema/projection_payload_contracts.json"
d=json.load(open(p,"r",encoding="utf-8"))
c=d.setdefault("contracts", {})
if "system_status" not in c:
    c["system_status"] = {
        "required_fields": ["ok", "checked_at_utc", "projections", "errors"],
        "field_types": {
            "ok": "int",            # we will store as 0/1 for strict typing simplicity
            "checked_at_utc": "string",
            "projections": "list",
            "errors": "list"
        }
    }
json.dump(d, open(p,"w",encoding="utf-8"), indent=2, sort_keys=True)
open(p,"a",encoding="utf-8").write("\n")
print("OK: payload contracts updated with system_status")
PY

# 3) Patch projections.py: add builder + register it
python3 - <<'PY'
import pathlib, re

path = pathlib.Path("runtime/core/projections.py")
s = path.read_text(encoding="utf-8")

if "def build_system_status" not in s:
    # Insert builder before BUILDERS definition
    m = re.search(r"\nBUILDERS\s*=\s*{", s)
    if not m:
        raise SystemExit("ERROR: could not find BUILDERS block")

    builder = r'''

def build_system_status(_: str) -> Dict[str, Any]:
    # Live status (allowed to use current time)
    from datetime import datetime, timezone

    checked_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # We will validate other projections by attempting to read their output files.
    reg = load_registry()
    envelope = load_envelope_contract()
    payloads = load_payload_contracts()

    proj_rows = []
    errors = []
    overall_ok = 1

    for spec in reg["projections"]:
        if not isinstance(spec, dict):
            overall_ok = 0
            errors.append("registry contains non-object projection spec")
            continue

        name = spec.get("name", "UNKNOWN")
        enabled = spec.get("enabled", True)
        out = spec.get("output")

        if not enabled:
            proj_rows.append({"name": name, "status": "SKIPPED"})
            continue

        # system_status checks itself only for existence after build
        if not isinstance(out, str) or not out:
            proj_rows.append({"name": name, "status": "FAIL"})
            overall_ok = 0
            errors.append(f"{name}: missing output path in registry")
            continue

        abs_out = os.path.join(ROOT, out)
        if not os.path.exists(abs_out):
            proj_rows.append({"name": name, "status": "FAIL"})
            overall_ok = 0
            errors.append(f"{name}: output missing")
            continue

        try:
            data = _read_json(abs_out)
            if not isinstance(data, dict):
                raise ProjectionError("output not object")
            # Validate against contracts
            validate_projection_output(data, envelope, payloads)
            proj_rows.append({"name": name, "status": "OK"})
        except Exception as e:
            proj_rows.append({"name": name, "status": "FAIL"})
            overall_ok = 0
            errors.append(f"{name}: {type(e).__name__}: {e}")

    return {
        "projection": "system_status",
        "source": "",
        "total": 0,
        "last_event_time_utc": "",
        "ok": overall_ok,
        "checked_at_utc": checked_at,
        "projections": proj_rows,
        "errors": errors
    }
'''
    s = s[:m.start()] + builder + s[m.start():]

# Register in BUILDERS
if re.search(r'BUILDERS\s*=\s*{[^}]*"system_status"', s, flags=re.S) is None:
    s = re.sub(
        r'BUILDERS\s*=\s*{',
        'BUILDERS = {\n    "system_status": build_system_status,',
        s,
        count=1
    )

path.write_text(s, encoding="utf-8")
print("OK: projections.py patched with system_status")
PY

echo "OK: phase 65 populate complete"
