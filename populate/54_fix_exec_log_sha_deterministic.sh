#!/usr/bin/env bash
set -euo pipefail

f="runtime/bin/app_entry"
[ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }

python3 - <<'PY'
from pathlib import Path
import re

p = Path("runtime/bin/app_entry")
s = p.read_text(encoding="utf-8")

# 1) Ensure we have a single variable REQ_SHA = "" at module level (idempotent)
if "REQ_SHA = " not in s:
    # Place after EXEC_LOG init
    m = re.search(r'EXEC_LOG\.parent\.mkdir\(parents=True, exist_ok=True\)\n', s)
    if not m:
        raise SystemExit("ERROR: cannot find EXEC_LOG init line")
    insert_at = m.end()
    s = s[:insert_at] + 'REQ_SHA = ""  # sha256 of parsed request\n' + s[insert_at:]

# 2) Make error() always log REQ_SHA (no payload hashing, no empty)
# Replace any line containing '"request_sha256":' inside error() block.
def replace_in_error(src: str) -> str:
    # Find error() function block roughly
    m = re.search(r'def error\(.*?\):\n(    .*\n)+?    raise SystemExit\(code\)\n', src)
    if not m:
        raise SystemExit("ERROR: cannot find error() block")
    block = m.group(0)
    # Replace request_sha256 line
    block2 = re.sub(
        r'"request_sha256"\s*:\s*[^,]+,',
        '"request_sha256": REQ_SHA,',
        block
    )
    if block == block2:
        raise SystemExit("ERROR: could not replace request_sha256 in error()")
    return src[:m.start()] + block2 + src[m.end():]

s = replace_in_error(s)

# 3) Ensure we set REQ_SHA immediately after request is loaded (both file and argv JSON modes)
# After request is set, inject:
#   global REQ_SHA
#   REQ_SHA = _sha256_text(json.dumps(request, sort_keys=True))
# Do it right after both parse paths converge: after `if not isinstance(request, dict)` check is too late.
# We'll insert immediately after `request = ...` assignments by matching the two patterns.

inject = '\n    global REQ_SHA\n    try:\n        REQ_SHA = _sha256_text(json.dumps(request, sort_keys=True))\n    except Exception:\n        REQ_SHA = ""\n'

# Insert after file load branch: request = load_json(...)
s_new = re.sub(
    r'(request = load_json\(req_path\)\n)',
    r'\1' + inject,
    s,
    count=1
)
s = s_new

# Insert after argv json parse: request = json.loads(...)
s_new = re.sub(
    r'(request = json\.loads\(sys\.argv\[1\]\)\n)',
    r'\1' + inject,
    s,
    count=1
)
s = s_new

# 4) Also ensure PASS events use REQ_SHA (replace request_sha256 computation in PASS appends)
s = re.sub(r'"request_sha256"\s*:\s*_sha256_text\(json\.dumps\(request, sort_keys=True\)\)', '"request_sha256": REQ_SHA', s)

p.write_text(s, encoding="utf-8")
print("✅ fixed request_sha256 to always use REQ_SHA for PASS+FAIL")
PY
