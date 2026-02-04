#!/usr/bin/env bash
set -euo pipefail

FAIL=0

# strip_comments prints only non-comment, non-empty lines
strip_comments() {
  # Remove everything after an unescaped # (good enough for shell scripts here)
  # Then drop blank lines
  sed -E 's/[[:space:]]+#.*$//' "$1" | sed -E '/^[[:space:]]*$/d'
}

for f in test/*.sh; do
  [ -f "$f" ] || continue

  CONTENT="$(strip_comments "$f")"

  # Forbidden writes inside tests:
  # - redirections into runtime/bin, runtime/core, runtime/schema
  if printf "%s\n" "$CONTENT" | grep -nE '(^|[[:space:]])(cat|printf|echo)[[:space:]]+>[[:space:]]*runtime/(bin|core|schema)/' >/dev/null; then
    echo "FAIL: $f writes into runtime/bin|core|schema"
    printf "%s\n" "$CONTENT" | grep -nE '(^|[[:space:]])(cat|printf|echo)[[:space:]]+>[[:space:]]*runtime/(bin|core|schema)/' | head -n 20
    FAIL=1
  fi

  # Heredoc writing into runtime/bin|core|schema
  if printf "%s\n" "$CONTENT" | grep -nE '>[[:space:]]*runtime/(bin|core|schema)/' >/dev/null; then
    # If it's a write into runtime, it's forbidden regardless of how produced
    echo "FAIL: $f writes into runtime/bin|core|schema (redirection detected)"
    printf "%s\n" "$CONTENT" | grep -nE '>[[:space:]]*runtime/(bin|core|schema)/' | head -n 20
    FAIL=1
  fi

  # Tests should not install tooling in runtime/bin
  if printf "%s\n" "$CONTENT" | grep -nE '(^|[[:space:]])chmod[[:space:]]+\+x[[:space:]]+runtime/bin/' >/dev/null; then
    echo "FAIL: $f chmods runtime/bin (tests should not install tooling)"
    printf "%s\n" "$CONTENT" | grep -nE '(^|[[:space:]])chmod[[:space:]]+\+x[[:space:]]+runtime/bin/' | head -n 20
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "PASS: test hygiene ok"
echo "✅ Phase 73 TEST PASS"
