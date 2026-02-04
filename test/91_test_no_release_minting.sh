#!/usr/bin/env bash
# Phase 91 TEST: Only Phase 83 may mint a release (invoke runtime/bin/release_bundle)
set -euo pipefail

die(){ echo "FAIL: $*" >&2; exit 1; }

allowed="test/83_test_release_bundle.sh"
self="test/91_test_no_release_minting.sh"

# Detect actual invocations that start with "./runtime/bin/release_bundle"
# (We keep the pattern here, but we NEVER print that literal substring in any messages.)
hits="$(
  grep -RIn --include='*.sh' -E '(^|[[:space:]])\./runtime/bin/release_bundle([[:space:]]|$)' test \
  | grep -vE "^\Q${self}\E:" \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
  || true
)"

if [ -z "$hits" ]; then
  die "No test script invokes release_bundle (Phase 83 must)."
fi

bad="$(
  echo "$hits" | awk -F: '{print $1}' | sort -u | grep -vFx "$allowed" || true
)"

if [ -n "$bad" ]; then
  echo "Disallowed release minting found in:"
  echo "$bad" | sed 's/^/ - /'
  echo
  echo "Invocation matches:"
  echo "$hits"
  die "Only ${allowed} may invoke release_bundle"
fi

# Ensure Phase 83 uses deterministic release id
if ! grep -q 'release_bundle --release-id "\$RELEASE_ID"' "$allowed"; then
  die "Phase 83 must call release_bundle with --release-id and RELEASE_ID"
fi

echo "✅ Phase 91 TEST PASS (release minting restricted to Phase 83)"
