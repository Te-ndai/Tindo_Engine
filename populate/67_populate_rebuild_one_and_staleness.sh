#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import pathlib, re

p = pathlib.Path("runtime/core/projections.py")
s = p.read_text(encoding="utf-8")

# 1) Add rebuild_one if not present
if "def rebuild_one(" not in s:
    insert_point = re.search(r"\ndef rebuild_all\(", s)
    if not insert_point:
        raise SystemExit("ERROR: rebuild_all not found")

    block = r'''

def rebuild_one(name: str) -> Dict[str, Any]:
    reg = load_registry()
    envelope = load_envelope_contract()
    payloads = load_payload_contracts()

    found = None
    for spec in reg["projections"]:
        if isinstance(spec, dict) and spec.get("name") == name:
            found = spec
            break
    if found is None:
        raise ProjectionError(f"unknown projection: {name}")

    n, status = rebuild_projection(found, envelope, payloads)
    return {"ok": True, "name": n, "status": status}
'''
    s = s[:insert_point.start()] + block + s[insert_point.start():]

# 2) Extend main() to support rebuild_one
if 'cmd == "rebuild_one"' not in s:
    s = s.replace(
        'if cmd == "rebuild_all":',
        'if cmd == "rebuild_all":'
    )
    # Insert a new elif after rebuild_all branch
    s = re.sub(
        r'(if cmd == "rebuild_all":\n\s+out = rebuild_all\(\)\n\s+print\(json\.dumps\(out, indent=2, sort_keys=True\)\)\n\s+return 0\n)',
        r'\1        elif cmd == "rebuild_one":\n            if len(args) < 2:\n                print("usage: projections.py rebuild_one <name>")\n                return 2\n            out = rebuild_one(args[1])\n            print(json.dumps(out, indent=2, sort_keys=True))\n            return 0\n',
        s,
        flags=re.S
    )

# 3) Patch system_status to include stale detection and file mtime
# We'll minimally inject logic inside the existing try block where it reads data.
# Add helper to get mtime utc string
if "def _mtime_utc(" not in s:
    helper = r'''

def _mtime_utc(path: str) -> str:
    from datetime import datetime, timezone
    ts = os.path.getmtime(path)
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
'''
    # place helper near other helpers (after _write_json_deterministic)
    s = re.sub(r'(def _write_json_deterministic\(.*?\n\s*os\.replace\(tmp, path\)\n)', r'\1' + helper, s, flags=re.S)

# Replace the proj_rows.append OK with richer row
# Find the line: proj_rows.append({"name": name, "status": "OK"})
target = 'proj_rows.append({"name": name, "status": "OK"})'
if target in s and '"stale"' not in s:
    s = s.replace(
        target,
        'last_evt = data.get("last_event_time_utc","")\n'
        '            mtime = _mtime_utc(abs_out)\n'
        '            # Stale if output mtime is older than last_event_time_utc (lex compare works for Zulu ISO)\n'
        '            stale = 1 if (last_evt and mtime < last_evt) else 0\n'
        '            if stale:\n'
        '                overall_ok = 0\n'
        '                proj_rows.append({"name": name, "status": "STALE", "output_mtime_utc": mtime, "last_event_time_utc": last_evt, "stale": 1})\n'
        '            else:\n'
        '                proj_rows.append({"name": name, "status": "OK", "output_mtime_utc": mtime, "last_event_time_utc": last_evt, "stale": 0})'
    )

p.write_text(s, encoding="utf-8")
print("OK: patched rebuild_one + staleness checks")
PY

# Update runtime/bin/rebuild_projections to allow optional arg
cat > runtime/bin/rebuild_projections <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "" ]; then
  python3 -m runtime.core.projections rebuild_all >/dev/null
  echo "OK: projections rebuilt (registry-driven)"
else
  python3 -m runtime.core.projections rebuild_one "$1" >/dev/null
  echo "OK: projection rebuilt: $1"
fi
SH
chmod +x runtime/bin/rebuild_projections

echo "OK: phase 67 populate complete"
