#!/usr/bin/env bash
set -euo pipefail

# Patch runtime/core/projections.py: add in-process chain verify + add log_integrity row
python3 - <<'PY'
import pathlib, re

p = pathlib.Path("runtime/core/projections.py")
s = p.read_text(encoding="utf-8")

# Add helper verifier if missing
if "def _verify_chain_file(" not in s:
    helper = r'''

def _verify_chain_file(path: str) -> Tuple[bool, str]:
    import hashlib
    if not os.path.exists(path):
        return (False, "chain file missing")
    prev = "0"*64
    n = 0
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                ev = json.loads(line)
                got_prev = ev.get("prev_sha256")
                got_h = ev.get("line_sha256")
                if got_prev != prev:
                    return (False, f"prev mismatch at line {n+1}")
                ev2 = dict(ev)
                ev2.pop("prev_sha256", None)
                ev2.pop("line_sha256", None)
                payload = json.dumps(ev2, sort_keys=True, separators=(",",":")).encode("utf-8")
                h = hashlib.sha256(prev.encode("utf-8") + payload).hexdigest()
                if got_h != h:
                    return (False, f"hash mismatch at line {n+1}")
                prev = h
                n += 1
    except Exception as e:
        return (False, f"exception: {type(e).__name__}: {e}")
    return (True, f"ok lines={n}")
'''
    # Insert before BUILDERS
    s = re.sub(r'\nBUILDERS\s*=\s*{', helper + r'\n\nBUILDERS = {', s, count=1)

# Update _validate_system_status_rows to allow log_integrity row
# Insert special-case after status extraction
if 'if row["name"] == "log_integrity"' not in s:
    s = s.replace(
        '        status = row["status"]',
        '        status = row["status"]\n\n        if row["name"] == "log_integrity":\n            # Special synthetic row; only requires status and optional details\n            if "details" in row and not isinstance(row["details"], str):\n                raise ProjectionError(f"system_status.projections[{i}].details invalid")\n            continue'
    )

# Inject log_integrity row into build_system_status at start (after lists init)
if '"name": "log_integrity"' not in s:
    s = s.replace(
        '    proj_rows: List[Dict[str, Any]] = []\n    errors: List[str] = []\n    overall_ok = 1\n',
        '    proj_rows: List[Dict[str, Any]] = []\n    errors: List[str] = []\n    overall_ok = 1\n\n    # Log integrity check (gates everything)\n    chain_path = os.path.join(ROOT, "runtime", "state", "logs", "executions.chain.jsonl")\n    ok_chain, detail = _verify_chain_file(chain_path)\n    if not ok_chain:\n        overall_ok = 0\n        proj_rows.append({"name": "log_integrity", "status": "FAIL", "details": detail})\n    else:\n        proj_rows.append({"name": "log_integrity", "status": "OK", "details": detail})\n'
    )

# Ensure make_fresh gates on log_integrity by rewriting the script
p.write_text(s, encoding="utf-8")
print("OK: patched projections.py with log integrity integration")
PY

cat > runtime/bin/make_fresh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

# 1) Build status first
./runtime/bin/rebuild_projections system_status >/dev/null

STATUS_FILE="runtime/state/projections/system_status.json"
test -f "$STATUS_FILE" || { echo "ERROR: system_status missing"; exit 1; }

# 2) Gate on log_integrity
python3 - <<'PY'
import json, sys
d=json.load(open("runtime/state/projections/system_status.json","r",encoding="utf-8"))
rows={r.get("name"): r for r in d.get("projections",[]) if isinstance(r,dict)}
li=rows.get("log_integrity")
if not li or li.get("status") != "OK":
    print("FAIL: log integrity not OK:", li)
    sys.exit(20)
PY

# 3) Extract stale projection names (excluding system_status)
STALE=$(
python3 - <<'PY'
import json
d=json.load(open("runtime/state/projections/system_status.json","r",encoding="utf-8"))
names=[]
for row in d.get("projections", []):
    if isinstance(row, dict) and row.get("status") == "STALE":
        n=row.get("name")
        if n and n not in ("system_status","log_integrity"):
            names.append(n)
print("\n".join(names))
PY
)

# 4) Rebuild stale projections only
if [ -n "${STALE}" ]; then
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    ./runtime/bin/rebuild_projections "$name" >/dev/null
  done <<< "${STALE}"
fi

# 5) Rebuild status again
./runtime/bin/rebuild_projections system_status >/dev/null

# 6) Fail if any FAIL or STALE remains
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
chmod +x runtime/bin/make_fresh

echo "OK: phase 74 populate complete"
