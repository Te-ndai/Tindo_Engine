#!/usr/bin/env bash
# Phase 97 BUILD: structure for detached signing + verification tooling
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }
ok(){ echo "OK: $*"; }

[ -d runtime/bin ] || die "missing runtime/bin"
[ -d runtime/schema ] || die "missing runtime/schema"
[ -d test ] || die "missing test"

mkdir -p runtime/state/keys
ok "ensured runtime/state/keys"

# Placeholders (populate will overwrite)
touch runtime/bin/sign_detached
touch runtime/bin/verify_detached
touch runtime/bin/verify_release_signatures
touch test/97_test_detached_signatures.sh

ok "created placeholders"
echo "✅ Phase 97 BUILD PASS"
