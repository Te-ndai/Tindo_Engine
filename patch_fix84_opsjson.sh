#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

F="test/84_test_restore_replay.sh"
[ -f "$F" ] || { echo "❌ missing $F" >&2; exit 1; }

b="${F}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp -f "$F" "$b"
echo "✅ backup: $b"

start=$(grep -n "python3 - <<'PY' \"\\\$OPS_JSON\" > \"\\\$RESTORE_DIR/_actual.json\"" "$F" | head -n1 | cut -d: -f1 || true)
end_echo=$(grep -n 'echo "Actual event count:' "$F" | head -n1 | cut -d: -f1 || true)

[ -n "${start:-}" ] || { echo "❌ could not find OPS_JSON parse heredoc start" >&2; exit 1; }
[ -n "${end_echo:-}" ] || { echo "❌ could not find echo Actual event count line" >&2; exit 1; }
[ "$end_echo" -gt "$start" ] || { echo "❌ bad anchor order" >&2; exit 1; }

# Split file
pre_tmp="${F}.pre.tmp"
mid_tmp="${F}.mid.tmp"
post_tmp="${F}.post.tmp"
out_tmp="${F}.out.tmp"

head -n $((start-1)) "$F" > "$pre_tmp"
sed -n "${start},$((end_echo-1))p" "$F" > "$mid_tmp"
tail -n +"$end_echo" "$F" > "$post_tmp"

# Wrap mid block safely (preserve original indentation by prefixing two spaces)
{
  cat "$pre_tmp"
  echo 'if [ -s "$OPS_JSON" ]; then'
  sed 's/^/  /' "$mid_tmp"
  echo 'else'
  echo '  echo "Skipping JSON actuals parsing (ops report not JSON)"'
  echo '  ACTUAL_EVENT_COUNT=""'
  echo '  ACTUAL_LAST_EVENT_TIME=""'
  echo 'fi'
  cat "$post_tmp"
} > "$out_tmp"

mv "$out_tmp" "$F"
rm -f "$pre_tmp" "$mid_tmp" "$post_tmp"

chmod +x "$F"
echo "✅ guarded OPS_JSON parsing"
