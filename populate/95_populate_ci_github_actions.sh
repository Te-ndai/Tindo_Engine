#!/usr/bin/env bash
# Phase 95 POPULATE: GitHub Actions workflow that runs the deterministic proof chain
set -euo pipefail

die(){ echo "FAIL: $*" >&2; exit 1; }
ok(){ echo "OK: $*"; }

[ -d .github/workflows ] || die "missing .github/workflows (run build/95_build_ci_wiring.sh first)"
[ -x test/90_test_all_deterministic.sh ] || die "missing executable: test/90_test_all_deterministic.sh"

cat > .github/workflows/ci.yml <<'YML'
name: ci

on:
  push:
  pull_request:
  workflow_dispatch:

jobs:
  deterministic-proof:
    runs-on: ubuntu-latest
    timeout-minutes: 10

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Ensure scripts executable
        run: |
          chmod +x test/*.sh runtime/bin/* build/*.sh populate/*.sh || true

      - name: Run deterministic proof chain (Phase 90)
        env:
          FACTORY_VERSION: "ci"
          RUNTIME_VERSION: "ci"
        run: |
          ./test/90_test_all_deterministic.sh

      - name: Upload release artifacts (latest) for inspection
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: runtime-releases
          path: runtime/state/releases
          if-no-files-found: warn
YML
ok "wrote .github/workflows/ci.yml"

cat > .github/workflows/README.md <<'MD'
# CI

This repository's CI runs a single deterministic proof chain:

- `test/90_test_all_deterministic.sh`

That chain mints exactly one release (Phase 83), restores + replays it (Phase 84/88), verifies bundle sha (Phase 86),
checks compat (Phase 87), and enforces that only Phase 83 can mint releases (Phase 91).
MD
ok "wrote .github/workflows/README.md"

echo "✅ Phase 95 POPULATE PASS"
