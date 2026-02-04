#!/usr/bin/env bash
# Phase 90 TEST: One-command deterministic proof chain
set -euo pipefail

die(){ echo "FAIL: $*" >&2; exit 1; }

ROOT="."
[ -d "${ROOT}/test" ] || die "missing ./test"
[ -x "${ROOT}/test/83_test_release_bundle.sh" ] || die "missing/executable: test/83_test_release_bundle.sh"
[ -x "${ROOT}/test/84_test_restore_replay.sh" ] || die "missing/executable: test/84_test_restore_replay.sh"
[ -x "${ROOT}/test/86_test_bundle_sha.sh" ] || die "missing/executable: test/86_test_bundle_sha.sh"
[ -x "${ROOT}/test/87_test_compat_contract.sh" ] || die "missing/executable: test/87_test_compat_contract.sh"

RELEASE_ID="$(date -u +%Y%m%dT%H%M%SZ)"
export RELEASE_ID

echo "RELEASE_ID=${RELEASE_ID}"
echo

./test/83_test_release_bundle.sh
./test/84_test_restore_replay.sh
./test/86_test_bundle_sha.sh
./test/87_test_compat_contract.sh
./test/91_test_no_release_minting.sh


manifest="runtime/state/releases/release_${RELEASE_ID}.json"
bundle="runtime/state/releases/release_${RELEASE_ID}.tar.gz"

[ -f "$manifest" ] || die "expected manifest missing: $manifest"
[ -f "$bundle" ] || die "expected bundle missing: $bundle"

echo
echo "✅ Phase 90 TEST PASS (deterministic chain)"
echo "Bundle:   $bundle"
echo "Manifest: $manifest"
