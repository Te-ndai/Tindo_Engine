#!/usr/bin/env bash
# Phase 95 BUILD: create CI wiring structure (no content injection)
set -euo pipefail

die(){ echo "FAIL: $*" >&2; exit 1; }
ok(){ echo "OK: $*"; }

[ -d build ] || die "missing ./build"
[ -d populate ] || die "missing ./populate"
[ -d test ] || die "missing ./test"
[ -d runtime ] || die "missing ./runtime"

mkdir -p .github/workflows
ok "created .github/workflows"

# Create placeholder files if missing (populate will overwrite with real contents)
touch .github/workflows/ci.yml
ok "ensured .github/workflows/ci.yml exists"

# Optional: a README note for CI
touch .github/workflows/README.md
ok "ensured .github/workflows/README.md exists"

echo "✅ Phase 95 BUILD PASS"
