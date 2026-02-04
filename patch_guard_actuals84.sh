#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

F="test/84_test_restore_replay.sh"
[ -f "$F" ] || { echo "❌ missing $F" >&2; exit 1; }

B="${F}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp -f "$F" "$B"
echo "✅ backup: $B"

start="$(grep -nF "python3 - <<'PY' \"\$OPS_JSON\" > \"\$RESTORE_DIR/_actual.json\"" "$F" | head -n1 | cut -d: -f1 || true)"
end_last="$(grep -n '^ACTUAL_LAST_EVENT_TIME=' "$F" | head -n1 | cut -d: -f1 || true)"

[ -n "${start:-}" ] || { echo "❌ could not find start heredoc for _actual.json parsing" >&2; exit 1; }
[ -n "${end_last:-}" ] || { echo "❌ could not find ACTUAL_LAST_EVENT_TIME assignment" >&2; exit 1; }
[ "$end_last" -ge "$start" ] || { echo "❌ bad anchor order" >&2; exit 1; }

# Include the ACTUAL_LAST_EVENT_TIME line itself in the guarded block
end="$end_last"

pre="${F}.pre.tmp"
mid="${F}.mid.tmp"
post="${F}.post.tmp"
out="${F}.out.tmp"

head -n $((start-1)) "$F" > "$pre"
sed -n "${start},${end}p" "$F" > "$mid"
tail -n +"$((end+1))" "$F" > "$post"

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

echo "✅ guarded _actual.json parsing behind OPS_JSON non-empty check"
echo "Now run:"
echo "  ./test/84_test_restore_replay.sh"
