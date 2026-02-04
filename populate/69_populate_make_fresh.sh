#!/usr/bin/env bash
set -euo pipefail

ROOT="."

test -f "$ROOT/runtime/bin/rebuild_projections" || { echo "ERROR: rebuild_projections missing"; exit 1; }

cat > "$ROOT/runtime/bin/make_fresh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

# Operator command: rebuild only what is stale, then re-check health.

# 1) Build status first (may mark stale)
./runtime/bin/rebuild_projections system_status >/dev/null

STATUS_FILE="runtime/state/projections/system_status.json"
test -f "$STATUS_FILE" || { echo "ERROR: system_status missing"; exit 1; }

# 2) Extract stale projection names (excluding system_status)
STALE=$(
python3 - <<'PY'
import json
d=json.load(open("runtime/state/projections/system_status.json","r",encoding="utf-8"))
names=[]
for row in d.get("projections", []):
    if isinstance(row, dict) and row.get("status") == "STALE":
        n=row.get("name")
        if n and n != "system_status":
            names.append(n)
print("\n".join(names))
PY
)

# 3) Rebuild stale projections only
if [ -n "${STALE}" ]; then
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    ./runtime/bin/rebuild_projections "$name" >/dev/null
  done <<< "${STALE}"
fi

# 4) Rebuild status again
./runtime/bin/rebuild_projections system_status >/dev/null

# 5) Fail if any FAIL or STALE remains among enabled projections
python3 - <<'PY'
import json, sys
d=json.load(open("runtime/state/projections/system_status.json","r",encoding="utf-8"))
bad=[]
for row in d.get("projections", []):
    if not isinstance(row, dict): 
        continue
    st=row.get("status")
    if st in ("FAIL","STALE"):
        bad.append((row.get("name"), st))
if bad:
    print("FAIL: still unhealthy:", bad)
    sys.exit(1)
print("OK: system fresh")
PY

echo "OK: make_fresh complete"
SH

chmod +x "$ROOT/runtime/bin/make_fresh"

echo "OK: phase 69 populate complete"
