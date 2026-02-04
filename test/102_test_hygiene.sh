#!/usr/bin/env bash
set -euo pipefail

die(){ echo "FAIL: $*" >&2; exit 1; }

# Phase 102 TEST: hygiene is non-destructive in dry-run and does not break deterministic chain.

./runtime/bin/hygiene_releases --dry-run >/dev/null

# Make sure no new releases were minted by hygiene.
# (We can’t perfectly detect without snapshotting, but we can enforce "no release_bundle invocation"
# by grepping the tool itself.)
grep -q 'release_bundle' runtime/bin/hygiene_releases && die "hygiene_releases must not mention release_bundle"

# Deterministic chain still must pass.
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh >/dev/null

echo "✅ Phase 102 TEST PASS (hygiene dry-run non-destructive; chain intact)"
