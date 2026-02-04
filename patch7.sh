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

# 1) Force ops report to run from restored bundle root (cwd-sensitive script)
# Replace any ops report invocation line to ensure it is (cd "$RESTORE_DIR" && "$OPS" report ...)
# and drop unsupported flags like --format/--json.
sed -i \
  -e 's#"\$OPS" report --root "\$RESTORE_DIR/runtime" --format json#(cd "$RESTORE_DIR" && "$OPS" report)#g' \
  -e 's#"\$OPS" report --root "\$RESTORE_DIR/runtime" --json#(cd "$RESTORE_DIR" && "$OPS" report)#g' \
  -e 's#"\$OPS" report --root "\$RESTORE_DIR/runtime"#(cd "$RESTORE_DIR" && "$OPS" report)#g' \
  "$F"

# 2) Replace the entire "assert results" parse-from-OPS_JSON block with log-derived actuals.
# We replace lines between:
#   '# ---------- assert results ----------'
# and the line right before:
#   '# Minimal operational assertions'
start=$(grep -n '^# ---------- assert results ----------$' "$F" | head -n1 | cut -d: -f1 || true)
end=$(grep -n '^# Minimal operational assertions' "$F" | head -n1 | cut -d: -f1 || true)

[ -n "${start:-}" ] || die "could not find assert results marker"
[ -n "${end:-}" ] || die "could not find Minimal operational assertions marker"
[ "$end" -gt "$start" ] || die "bad marker order"

tmp="${F}.tmp.$(date -u +%Y%m%dT%H%M%SZ)"

# Write file up to start marker, then inject new block, then append from end marker onward.
head -n "$start" "$F" > "$tmp"

cat >> "$tmp" <<'BLOCK'
# NOTE: ops/report is a disk-writer, not a JSON emitter.
# Actuals are derived from restored logs (append-only truth).

CHAIN_PATH="$RESTORE_DIR/runtime/state/logs/executions.chain.jsonl"
require_file "$CHAIN_PATH"

ACTUAL_EVENT_COUNT="$(wc -l < "$CHAIN_PATH" | tr -d ' ')"

ACTUAL_LAST_EVENT_TIME="$(python3 - <<'PY' "$CHAIN_PATH"
import json, sys
path=sys.argv[1]
last=""
with open(path,"r",encoding="utf-8",errors="replace") as f:
    for line in f:
        line=line.strip()
        if line: last=line
if not last:
    print("")
    raise SystemExit(0)
try:
    obj=json.loads(last)
except Exception:
    print("")
    raise SystemExit(0)
# try common keys
for k in ("event_time_utc","event_time","timestamp_utc","time_utc"):
    v=obj.get(k)
    if isinstance(v,str) and v:
        print(v)
        raise SystemExit(0)
print("")
PY
)"

echo "Actual event count: ${ACTUAL_EVENT_COUNT:-<unknown>}"
echo "Actual last_event_time_utc: ${ACTUAL_LAST_EVENT_TIME:-<unknown>}"

# If expected values exist, enforce equality.
if [ -n "${EXPECTED_EVENT_COUNT:-}" ]; then
  [ -n "${ACTUAL_EVENT_COUNT:-}" ] || die "manifest specifies expected_event_count but actual event_count is empty"
  [ "$ACTUAL_EVENT_COUNT" = "$EXPECTED_EVENT_COUNT" ] || die "event_count mismatch: expected=$EXPECTED_EVENT_COUNT actual=$ACTUAL_EVENT_COUNT"
fi

if [ -n "${EXPECTED_LAST_EVENT_TIME:-}" ]; then
  [ -n "${ACTUAL_LAST_EVENT_TIME:-}" ] || die "manifest specifies expected_last_event_time_utc but actual last_event_time_utc is empty"
  [ "$ACTUAL_LAST_EVENT_TIME" = "$EXPECTED_LAST_EVENT_TIME" ] || die "last_event_time_utc mismatch: expected=$EXPECTED_LAST_EVENT_TIME actual=$ACTUAL_LAST_EVENT_TIME"
fi
BLOCK

# Append the rest of the file starting from the "Minimal operational assertions" marker
tail -n +"$end" "$F" >> "$tmp"

mv "$tmp" "$F"
chmod +x "$F"

ok "Phase 84: removed OPS_JSON parsing; derive actuals from executions.chain.jsonl (truth source)"
echo "Now run:"
echo "  ./test/84_test_restore_replay.sh"
