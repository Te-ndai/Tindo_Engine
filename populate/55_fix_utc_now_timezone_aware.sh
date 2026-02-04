#!/usr/bin/env bash
set -euo pipefail

f="runtime/bin/app_entry"
[ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re

p = Path("runtime/bin/app_entry")
s = p.read_text(encoding="utf-8")

# Ensure datetime.timezone is available (it is via datetime module)
# Replace the body of _utc_now() function.
pattern = r'def _utc_now\(\) -> str:\n(    .*\n)+?'
m = re.search(pattern, s)
if not m:
    raise SystemExit("ERROR: _utc_now() function not found")

new_func = (
    'def _utc_now() -> str:\n'
    '    # timezone-aware UTC\n'
    '    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00","Z")\n'
)
s2 = s[:m.start()] + new_func + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("✅ patched _utc_now() to timezone-aware UTC")
PY
