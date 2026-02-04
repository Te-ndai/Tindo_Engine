#!/usr/bin/env bash
set -euo pipefail

f="test/02_test.sh"
[ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }

# Replace fail() so it writes a FAIL result log before exiting.
# Also replace the PASS log block to use phase 0.3 and only write at the very end.

# 1) Inject a write_result() helper and override fail()
if ! grep -q 'write_result' "$f"; then
  awk '
    BEGIN{done=0}
    /^fail\(\)/ && done==0 {
      print "write_result() {"
      print "  local status=\"$1\""
      print "  local msg=\"$2\""
      print "  local ts"
      print "  ts=\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
      print "  cat > logs/test.results.json <<EOF"
      print "{"
      print "  \"phase\": \"0.3\","
      print "  \"action\": \"TEST\","
      print "  \"timestamp_utc\": \"$ts\","
      print "  \"status\": \"$status\","
      print "  \"message\": \"$msg\""
      print "}"
      print "EOF"
      print "}"
      print ""
      print "fail() {"
      print "  echo \"FAIL: $*\" >&2;"
      print "  write_result \"FAIL\" \"$*\""
      print "  exit 1;"
      print "}"
      done=1
      next
    }
    {print}
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
fi

# 2) Remove/neutralize the old PASS log writer block (the one that hardcodes phase 0.2 and status PASS)
# We do this by deleting the block that starts with "# Write logs/test.results.json" up to the end of that heredoc.
sed -i '/# Write logs\/test\.results\.json/,/EOF/d' "$f" || true

# 3) Append a single PASS writer at end
if ! grep -q 'write_result "PASS"' "$f"; then
  cat >> "$f" <<'EOF'

# Final: only if we reach here, test passed.
write_result "PASS" "all checks passed"
echo "✅ TEST PASS"
echo "Wrote: logs/test.results.json"
EOF
fi

echo "OK: test/02_test.sh patched to write truthful results."
