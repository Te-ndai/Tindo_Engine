#!/usr/bin/env bash
# Phase 95 POPULATE v2: GitHub Actions workflow with 2 jobs:
# 1) deterministic proof chain (Phase 90)
# 2) manifest portability report (portable vs host-bound vs invalid)
set -euo pipefail

die(){ echo "FAIL: $*" >&2; exit 1; }
ok(){ echo "OK: $*"; }

[ -d .github/workflows ] || die "missing .github/workflows (run build/95_build_ci_wiring.sh first)"
[ -x test/90_test_all_deterministic.sh ] || die "missing executable: test/90_test_all_deterministic.sh"
[ -x runtime/bin/validate_manifest ] || die "missing executable: runtime/bin/validate_manifest"

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

  manifest-portability-report:
    runs-on: ubuntu-latest
    timeout-minutes: 5

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Ensure validator executable
        run: |
          chmod +x runtime/bin/validate_manifest || true

      - name: Report portability of all manifests in runtime/state/releases
        run: |
          python3 - <<'PY'
          import glob, json, os, platform, re, subprocess, sys

          def canon_host():
              return {
                  "os": platform.system().lower(),
                  "arch": platform.machine().lower(),
                  "python": platform.python_version(),
                  "impl": platform.python_implementation().lower(),
                  "machine": platform.platform(),
              }

          host = canon_host()
          manifests = sorted(glob.glob("runtime/state/releases/release_*.json"))

          if not manifests:
              print("No manifests found in runtime/state/releases (nothing to report).")
              sys.exit(0)

          portable = []
          host_bound = []
          invalid = []

          def rid_from_path(p):
              m = re.search(r"release_(\d{8}T\d{6}Z)\.json$", p)
              return m.group(1) if m else ""

          for mpath in manifests:
              rid = rid_from_path(mpath)
              cmd = ["./runtime/bin/validate_manifest", mpath]
              if rid:
                  cmd += ["--release-id", rid]

              try:
                  subprocess.check_output(cmd, stderr=subprocess.STDOUT)
              except subprocess.CalledProcessError as e:
                  invalid.append((mpath, e.output.decode("utf-8", errors="replace").strip()))
                  continue

              try:
                  doc = json.load(open(mpath, "r", encoding="utf-8"))
              except Exception as e:
                  invalid.append((mpath, f"ERROR: cannot read json: {e}"))
                  continue

              compat = doc.get("compat") or {}
              if compat == host:
                  portable.append(mpath)
              else:
                  host_bound.append((mpath, compat))

          print("=== Manifest portability report ===")
          print("Host:", host)
          print()

          def show_list(title, items):
              print(f"{title} ({len(items)}):")
              if not items:
                  print("  - (none)")
              else:
                  for x in items:
                      if isinstance(x, tuple):
                          print("  -", x[0])
                      else:
                          print("  -", x)
              print()

          show_list("PORTABLE (compat matches this runner)", portable)
          show_list("HOST-BOUND (valid but compat mismatch)", host_bound)
          show_list("INVALID (schema/invariants failed)", invalid)

          if host_bound:
              print("Details: HOST-BOUND compat values (first 10)")
              for p, c in host_bound[:10]:
                  print(" -", p)
                  print("   compat:", c)
              print()

          if invalid:
              print("Details: INVALID errors (first 10)")
              for p, err in invalid[:10]:
                  print(" -", p)
                  print("   error:", err.splitlines()[:6])
              print()

          print("Summary:",
                f"portable={len(portable)}",
                f"host_bound={len(host_bound)}",
                f"invalid={len(invalid)}")
          PY
YML

ok "wrote .github/workflows/ci.yml (v2 with portability job)"

cat > .github/workflows/README.md <<'MD'
# CI

This repository's CI has two jobs:

1) **deterministic-proof**
   - Runs `test/90_test_all_deterministic.sh` to mint exactly one release and prove it end-to-end.

2) **manifest-portability-report**
   - Validates all release manifests in `runtime/state/releases/` using `runtime/bin/validate_manifest`.
   - Reports which manifests are:
     - **PORTABLE** (compat matches current runner)
     - **HOST-BOUND** (valid, but compat mismatch)
     - **INVALID** (schema/invariants failed)
MD
ok "wrote .github/workflows/README.md"

echo "✅ Phase 95 POPULATE v2 PASS"
