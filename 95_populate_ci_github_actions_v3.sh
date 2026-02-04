cat > populate/95_populate_ci_github_actions_v3.sh <<'SH'
#!/usr/bin/env bash
# Phase 95 POPULATE v3: GitHub Actions workflow with 2 jobs + portability report artifact.
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
          python3 - <<'PY' > portability_report.txt
          import glob, json, platform, re, subprocess, sys

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

          portable, host_bound, invalid = [], [], []

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

              doc = json.load(open(mpath, "r", encoding="utf-8"))
              compat = doc.get("compat") or {}
              if compat == host:
                  portable.append(mpath)
              else:
                  host_bound.append((mpath, compat))

          print("=== Manifest portability report ===")
          print("Host:", host)
          print()
          print(f"PORTABLE ({len(portable)}):")
          for p in portable or ["(none)"]:
              print(" -", p)
          print()
          print(f"HOST-BOUND ({len(host_bound)}):")
          if not host_bound:
              print(" - (none)")
          else:
              for p, _ in host_bound:
                  print(" -", p)
          print()
          print(f"INVALID ({len(invalid)}):")
          if not invalid:
              print(" - (none)")
          else:
              for p, err in invalid:
                  print(" -", p)
                  print("   error:", "\\n".join(err.splitlines()[:6]))
          print()
          print("Summary:",
                f"portable={len(portable)}",
                f"host_bound={len(host_bound)}",
                f"invalid={len(invalid)}")
          PY
          cat portability_report.txt

      - name: Upload portability report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: portability-report
          path: portability_report.txt
          if-no-files-found: warn
YML

ok "wrote .github/workflows/ci.yml (v3 with portability report artifact)"

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
   - Uploads `portability_report.txt` as a workflow artifact.
MD

ok "wrote .github/workflows/README.md"
echo "✅ Phase 95 POPULATE v3 PASS"
SH

chmod +x populate/95_populate_ci_github_actions_v3.sh
