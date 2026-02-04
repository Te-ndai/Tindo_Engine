#!/usr/bin/env bash
set -euo pipefail

# 1) Update payload contract (system_status)
python3 - <<'PY'
import json
p="runtime/schema/projection_payload_contracts.json"
d=json.load(open(p,"r",encoding="utf-8"))
c=d["contracts"]["system_status"]

# Make the contract explicit and future-proof
c["required_fields"] = ["ok","checked_at_utc","projections","errors"]
c["field_types"] = {
    "ok": "int",
    "checked_at_utc": "string",
    "projections": "list",
    "errors": "list"
}
# Add a marker so validator knows to apply extra row checks
c["row_contract_version"] = 1

json.dump(d, open(p,"w",encoding="utf-8"), indent=2, sort_keys=True)
open(p,"a",encoding="utf-8").write("\n")
print("OK: updated system_status payload contract strict marker")
PY

# 2) Patch validator in runtime/core/projections.py to enforce system_status rows
python3 - <<'PY'
import pathlib, re

p=pathlib.Path("runtime/core/projections.py")
s=p.read_text(encoding="utf-8")

if "_validate_system_status_rows" not in s:
    helper = r'''

def _validate_system_status_rows(data: Dict[str, Any]) -> None:
    rows = data.get("projections")
    if not isinstance(rows, list):
        raise ProjectionError("system_status.projections must be a list")

    for i, row in enumerate(rows):
        if not isinstance(row, dict):
            raise ProjectionError(f"system_status.projections[{i}] must be an object")

        if "name" not in row or not isinstance(row["name"], str):
            raise ProjectionError(f"system_status.projections[{i}].name missing/invalid")
        if "status" not in row or not isinstance(row["status"], str):
            raise ProjectionError(f"system_status.projections[{i}].status missing/invalid")

        status = row["status"]
        if status in ("OK", "STALE"):
            for k in ("output_mtime_utc","last_event_time_utc","log_last_event_time_utc","stale"):
                if k not in row:
                    raise ProjectionError(f"system_status.projections[{i}] missing {k}")
            if not isinstance(row["output_mtime_utc"], str):
                raise ProjectionError(f"system_status.projections[{i}].output_mtime_utc invalid")
            if not isinstance(row["last_event_time_utc"], str):
                raise ProjectionError(f"system_status.projections[{i}].last_event_time_utc invalid")
            if not isinstance(row["log_last_event_time_utc"], str):
                raise ProjectionError(f"system_status.projections[{i}].log_last_event_time_utc invalid")
            if row["stale"] not in (0,1):
                raise ProjectionError(f"system_status.projections[{i}].stale must be 0/1")
'''
    # Insert helper near validate_projection_output
    s = re.sub(r'(def validate_projection_output\(.*?\n)', r'\1' + helper + "\n", s, count=1, flags=re.S)

# Hook it inside validate_projection_output right after payload validation
hook = "    # Optional last_n item validation"
if hook in s and "_validate_system_status_rows" not in s.split(hook)[0]:
    # find a stable place: after payload required/type validation and before last_n checks
    s = s.replace(
        hook,
        '    # Extra row validation for system_status\n'
        '    if name == "system_status":\n'
        '        _validate_system_status_rows(data)\n\n'
        + hook
    )

p.write_text(s, encoding="utf-8")
print("OK: patched runtime validator for system_status rows")
PY

echo "OK: phase 68 populate complete"
