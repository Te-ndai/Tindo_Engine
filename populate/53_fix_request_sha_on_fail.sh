#!/usr/bin/env bash
set -euo pipefail

f="runtime/bin/app_entry"
[ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }

python3 - <<'PY'
from pathlib import Path
p = Path("runtime/bin/app_entry")
s = p.read_text(encoding="utf-8")

# Avoid double patching
if "REQ_SHA" in s:
    print("OK: request sha fix already applied.")
    raise SystemExit(0)

# 1) Introduce REQ_SHA global after EXEC_LOG init block
marker = 'EXEC_LOG.parent.mkdir(parents=True, exist_ok=True)\n'
ins = marker + '\nREQ_SHA = None  # set after request parse\n'
if marker not in s:
    raise SystemExit("ERROR: cannot find EXEC_LOG init marker")
s = s.replace(marker, ins)

# 2) Modify error() logging line to use REQ_SHA fallback
old = '"request_sha256": _sha256_text(json.dumps(payload, sort_keys=True)),'
new = '"request_sha256": (REQ_SHA or _sha256_text(json.dumps(request, sort_keys=True)) if \"request\" in globals() else \"\"),'
if old not in s:
    raise SystemExit("ERROR: cannot find error() request_sha256 line")
s = s.replace(old, new)

# 3) Set REQ_SHA right after request is validated as dict
# Find the point after: if not isinstance(request, dict): error(...)
needle = 'if not isinstance(request, dict):\n        error("request must be an object", 2)\n'
if needle not in s:
    raise SystemExit("ERROR: cannot find request dict validation block")
s = s.replace(needle, needle + '\n    global REQ_SHA\n    REQ_SHA = _sha256_text(json.dumps(request, sort_keys=True))\n')

p.write_text(s, encoding="utf-8")
print("✅ patched FAIL logging to use request sha")
PY
