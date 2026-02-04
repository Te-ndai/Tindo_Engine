#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

die(){ echo "❌ $*" >&2; exit 1; }
ok(){ echo "✅ $*"; }

F="test/84_test_restore_replay.sh"
[ -f "$F" ] || die "missing $F"

backup(){
  local b="${F}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -f "$F" "$b"
  ok "backup: $b"
}

backup

python3 - <<'PY'
from pathlib import Path

p = Path("test/84_test_restore_replay.sh")
lines = p.read_text(encoding="utf-8").splitlines(True)

needle_start = 'python3 - <<\'PY\' "$OPS_JSON" > "$RESTORE_DIR/_actual.json"'
needle_echo  = 'echo "Actual event count:'

i_start = None
i_echo = None

for i, ln in enumerate(lines):
    if needle_start in ln:
        i_start = i
        break

if i_start is None:
    raise SystemExit("NO_MATCH: cannot find ops actuals parse heredoc start")

for j in range(i_start+1, len(lines)):
    if needle_echo in lines[j]:
        i_echo = j
        break

if i_echo is None:
    raise SystemExit("NO_MATCH: cannot find 'echo \"Actual event count\"' after parse block")

# Determine indentation at the start line (preserve style)
start_line = lines[i_start]
indent = start_line[:len(start_line) - len(start_line.lstrip(" \t"))]
inner_indent = indent + "  "  # +2 spaces

block = lines[i_start:i_echo]  # parse+extraction block (up to before echo actuals)

# If already guarded, do nothing
if i_start > 0 and "if [ -s \"$OPS_JSON\" ]; then" in lines[i_start-1]:
    print("ALREADY_GUARDED")
    raise SystemExit(0)

wrapped = []
wrapped.append(f'{indent}if [ -s "$OPS_JSON" ]; then\n')
for ln in block:
    wrapped.append(inner_indent + ln.lstrip(" \t"))
wrapped.append(f'{indent}else\n')
wrapped.append(f'{inner_indent}echo "Skipping JSON actuals parsing (ops report not JSON)"\n')
wrapped.append(f'{inner_indent}ACTUAL_EVENT_COUNT=""\n')
wrapped.append(f'{inner_indent}ACTUAL_LAST_EVENT_TIME=""\n')
wrapped.append(f'{indent}fi\n')

new_lines = lines[:i_start] + wrapped + lines[i_echo:]

p.write_text("".join(new_lines), encoding="utf-8")
print("PATCHED")
PY

# sanity: guard exists and parse line is now below it (not necessarily with exact spaces)
grep -q 'if \[ -s "\$OPS_JSON" \]; then' "$F" || die "guard not inserted"
grep -q "python3 - <<'PY' \"\\\$OPS_JSON\" > \"\\\$RESTORE_DIR/_actual.json\"" "$F" || die "parse line missing after patch"

ok "Phase 84: guarded JSON actuals parsing (no crash on non-JSON ops output)"
echo "Now run:"
echo "  ./test/84_test_restore_replay.sh"
