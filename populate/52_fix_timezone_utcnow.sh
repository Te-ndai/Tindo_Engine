#!/usr/bin/env bash
set -euo pipefail

f="runtime/bin/app_entry"
[ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }

# Replace the _utc_now() function body deterministically.
python3 - <<'PY'
from pathlib import Path
p = Path("runtime/bin/app_entry")
s = p.read_text(encoding="utf-8")

old = 'return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"'
new = 'return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00","Z")'

if old not in s:
    raise SystemExit("ERROR: expected utcnow() line not found; aborting to avoid corrupting file.")

s = s.replace(old, new)
p.write_text(s, encoding="utf-8")
print("✅ patched _utc_now() to timezone-aware UTC")
PY
