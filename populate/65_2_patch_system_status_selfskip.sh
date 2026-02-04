#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import pathlib

p = pathlib.Path("runtime/core/projections.py")
lines = p.read_text(encoding="utf-8").splitlines()

# Find build_system_status block and then the loop
def_idx = None
for i,l in enumerate(lines):
    if l.strip().startswith("def build_system_status"):
        def_idx = i
        break
if def_idx is None:
    raise SystemExit("ERROR: build_system_status not found")

loop_idx = None
for i in range(def_idx, min(def_idx+200, len(lines))):
    if 'for spec in reg["projections"]' in lines[i]:
        loop_idx = i
        break
if loop_idx is None:
    raise SystemExit("ERROR: loop not found inside build_system_status")

# Find the line where name is assigned within that loop
name_idx = None
for i in range(loop_idx, min(loop_idx+80, len(lines))):
    if 'name = spec.get("name", "UNKNOWN")' in lines[i].replace("'", '"'):
        name_idx = i
        break
if name_idx is None:
    # fallback: any line that contains name = spec.get(
    for i in range(loop_idx, min(loop_idx+80, len(lines))):
        if "name = spec.get(" in lines[i]:
            name_idx = i
            break
if name_idx is None:
    raise SystemExit("ERROR: name assignment not found inside loop")

# Detect if already patched
needle = 'if name == "system_status":'
for i in range(loop_idx, min(loop_idx+120, len(lines))):
    if needle in lines[i]:
        print("OK: already patched")
        raise SystemExit(0)

indent = lines[name_idx][:len(lines[name_idx]) - len(lines[name_idx].lstrip())]
insert = [
    "",
    f"{indent}# system_status must not depend on its own prior output",
    f'{indent}if name == "system_status":',
    f'{indent}    proj_rows.append({{"name": name, "status": "OK"}})',
    f"{indent}    continue",
    ""
]

# Insert immediately after the name assignment line
lines[name_idx+1:name_idx+1] = insert

p.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("OK: patched system_status self-skip")
PY
