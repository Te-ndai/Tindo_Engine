#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

F="test/84_test_restore_replay.sh"
[ -f "$F" ] || { echo "❌ missing $F" >&2; exit 1; }

B="${F}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp -f "$F" "$B"
echo "✅ backup: $B"

# Find start: line that mentions OPS_JSON and _actual.json (works even if spacing changed)
start="$(grep -nE 'OPS_JSON.*_actual\.json|_actual\.json.*OPS_JSON' "$F" | head -n1 | cut -d: -f1 || true)"
end_echo="$(grep -n 'echo "Actual event count' "$F" | head -n1 | cut -d: -f1 || true)"

[ -n "${start:-}" ] || { echo "❌ could not find start of actuals parse block (OPS_JSON + _actual.json)" >&2; exit 1; }
[ -n "${end_echo:-}" ] || { echo "❌ could not find echo Actual event count" >&2; exit 1; }
[ "$end_echo" -gt "$start" ] || { echo "❌ bad anchor order" >&2; exit 1; }

pre="${F}.pre.tmp"
mid="${F}.mid.tmp"
post="${F}.post.tmp"
out="${F}.out.tmp"

head -n $((start-1)) "$F" > "$pre"
sed -n "${start},$((end_echo-1))p" "$F" > "$mid"
tail -n +"$end_echo" "$F" > "$post"

{
  cat "$pre"
  echo 'if [ -s "$OPS_JSON" ]; then'
  sed 's/^/  /' "$mid"
  echo 'else'
  echo '  echo "Skipping JSON actuals parsing (ops report not JSON)"'
  echo '  ACTUAL_EVENT_COUNT=""'
  echo '  ACTUAL_LAST_EVENT_TIME=""'
  echo 'fi'
  cat "$post"
} > "$out"

mv "$out" "$F"
rm -f "$pre" "$mid" "$post"
chmod +x "$F"

echo "✅ guarded ops JSON parsing"
