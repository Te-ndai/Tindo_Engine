#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import pathlib, re

p = pathlib.Path("runtime/core/projections.py")
s = p.read_text(encoding="utf-8")

# Insert a self-skip right after name/enabled extraction inside the loop
pattern = r'(for spec in reg\["projections"\]:\n\s+.*\n\s+name = spec\.get\("name", "UNKNOWN"\)\n\s+enabled = spec\.get\("enabled", True\)\n\s+out = spec\.get\("output"\)\n)'
m = re.search(pattern, s)
if not m:
    raise SystemExit("ERROR: could not find insertion point in build_system_status loop")

insertion = m.group(1) + "\n        # system_status must not depend on its own prior output\n        if name == \"system_status\":\n            proj_rows.append({\"name\": name, \"status\": \"OK\"})\n            continue\n"

s2 = s[:m.start(1)] + insertion + s[m.end(1):]
p.write_text(s2, encoding="utf-8")
print("OK: patched system_status self-check")
PY
