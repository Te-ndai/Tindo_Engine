#!/usr/bin/env bash
set -euo pipefail

cat > test/73_test_hygiene.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

FAIL=0

# Forbidden writes inside tests
# - redirections into runtime/bin, runtime/core, runtime/schema
# - cat > runtime/...
# - heredocs writing into runtime/...
# - chmod +x runtime/bin/... (tests should not be installing tools)
for f in test/*.sh; do
  [ -f "$f" ] || continue

  # Allowlist: tests may read runtime/, execute runtime/bin/, and write test/tmp/
  if grep -nE '(^|\s)(cat|printf|echo)\s+>\s*runtime/(bin|core|schema)/' "$f" >/dev/null; then
    echo "FAIL: $f writes into runtime/bin|core|schema"
    grep -nE '(^|\s)(cat|printf|echo)\s+>\s*runtime/(bin|core|schema)/' "$f" | head -n 20
    FAIL=1
  fi

  if grep -nE '<<'\''SH'\''\s*$' "$f" >/dev/null; then
    # If a test contains a heredoc named SH, check if it's used to write runtime files
    if grep -nE '>\s*runtime/(bin|core|schema)/' "$f" >/dev/null; then
      echo "FAIL: $f uses heredoc to write runtime/bin|core|schema"
      grep -nE '>\s*runtime/(bin|core|schema)/' "$f" | head -n 20
      FAIL=1
    fi
  fi

  if grep -nE 'chmod\s+\+x\s+runtime/bin/' "$f" >/dev/null; then
    echo "FAIL: $f chmods runtime/bin (tests should not install tooling)"
    grep -nE 'chmod\s+\+x\s+runtime/bin/' "$f" | head -n 20
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: test hygiene ok"
echo "✅ Phase 73 TEST PASS"
SH

chmod +x test/73_test_hygiene.sh

echo "OK: phase 73 populate complete"
