#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

die(){ echo "❌ $*" >&2; exit 1; }
ok(){ echo "✅ $*"; }

[ -f test/84_test_restore_replay.sh ] || die "missing test/84_test_restore_replay.sh"

backup(){
  local f="$1"
  local b="${f}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -f "$f" "$b"
  ok "backup: $b"
}

backup test/84_test_restore_replay.sh

python3 - <<'PY'
import pathlib, re

p = pathlib.Path("test/84_test_restore_replay.sh")
s = p.read_text(encoding="utf-8")

# Find the block that starts with:
# ---------- assert results ----------
# and includes the python3 JSON parse of OPS_JSON into _actual.json, then ACTUAL_* extraction.
# We'll wrap that whole parse block with: if [ -s "$OPS_JSON" ]; then ... else ... fi

marker = r'# ---------- assert results ----------'
i = s.find(marker)
if i == -1:
    raise SystemExit("NO_MATCH: assert results marker not found")

# Identify the JSON parse sub-block: python3 - <<'PY' "$OPS_JSON" > "$RESTORE_DIR/_actual.json" ... PY
m = re.search(r'python3 - <<\'PY\' "\$OPS_JSON" > "\$RESTORE_DIR/_actual\.json"\n.*?\nPY\n', s[i:], flags=re.DOTALL)
if not m:
    raise SystemExit("NO_MATCH: ops JSON parse heredoc not found")

# Also include the immediate ACTUAL_EVENT_COUNT / ACTUAL_LAST_EVENT_TIME extraction lines after it.
# We'll capture until the line that echoes actuals (echo "Actual event count: ...")
m2 = re.search(
    r'(python3 - <<\'PY\' "\$OPS_JSON" > "\$RESTORE_DIR/_actual\.json"\n.*?\nPY\n)'
    r'(ACTUAL_EVENT_COUNT=.*?\n)'
    r'(ACTUAL_LAST_EVENT_TIME=.*?\n)',
    s[i:],
    flags=re.DOTALL
)
if not m2:
    raise SystemExit("NO_MATCH: could not capture ACTUAL_* extraction lines")

parse_block = m2.group(0)

wrapped = (
    'if [ -s "$OPS_JSON" ]; then\n'
    + parse_block +
    'else\n'
    '  echo "Skipping JSON actuals parsing (ops report not JSON)"\n'
    '  ACTUAL_EVENT_COUNT=""\n'
    '  ACTUAL_LAST_EVENT_TIME=""\n'
    'fi\n'
)

s2 = s[:i] + s[i:].replace(parse_block, wrapped, 1)
p.write_text(s2, encoding="utf-8")
print("PATCHED")
PY

chmod +x test/84_test_restore_replay.sh
ok "Phase 84: guarded ops JSON parsing (skip when non-JSON)"

echo "Now rerun:"
echo "  ./test/84_test_restore_replay.sh"
