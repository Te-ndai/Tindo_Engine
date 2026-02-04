#!/usr/bin/env bash
set -euo pipefail

ROOT="."
REG="$ROOT/runtime/schema/projection_registry.json"

python3 - <<'PY'
import json
d=json.load(open("runtime/schema/projection_registry.json","r",encoding="utf-8"))
names=[]
for p in d["projections"]:
    if p.get("enabled", True) and p.get("name") != "system_status":
        names.append(p["name"])
print("Deterministic projections:", ", ".join(names))
PY

# Rebuild #1
"$ROOT/runtime/bin/rebuild_projections" >/dev/null

# Snapshot deterministic outputs
python3 - <<'PY'
import json, shutil, os
d=json.load(open("runtime/schema/projection_registry.json","r",encoding="utf-8"))
os.makedirs("runtime/state/cache/det_snap_1", exist_ok=True)
for p in d["projections"]:
    if not p.get("enabled", True): 
        continue
    if p.get("name") == "system_status":
        continue
    out=p["output"]
    if out and os.path.exists(out):
        shutil.copy(out, "runtime/state/cache/det_snap_1/" + os.path.basename(out))
print("OK: snap1")
PY

# Rebuild #2
"$ROOT/runtime/bin/rebuild_projections" >/dev/null

# Snapshot #2 and compare
python3 - <<'PY'
import json, shutil, os, sys, filecmp
d=json.load(open("runtime/schema/projection_registry.json","r",encoding="utf-8"))
os.makedirs("runtime/state/cache/det_snap_2", exist_ok=True)

ok=True
for p in d["projections"]:
    if not p.get("enabled", True): 
        continue
    if p.get("name") == "system_status":
        continue
    out=p["output"]
    if out and os.path.exists(out):
        dst="runtime/state/cache/det_snap_2/" + os.path.basename(out)
        shutil.copy(out, dst)

        a="runtime/state/cache/det_snap_1/" + os.path.basename(out)
        b=dst
        if not os.path.exists(a):
            print("FAIL: missing snap1 for", out); ok=False
        elif not filecmp.cmp(a,b,shallow=False):
            print("FAIL: nondeterministic:", out); ok=False

if not ok:
    sys.exit(1)
print("PASS: deterministic projections stable (system_status excluded)")
PY

echo "✅ Phase 66 TEST PASS"
