# CI

This repository's CI has two jobs:

1) **deterministic-proof**
   - Runs `test/90_test_all_deterministic.sh` to mint exactly one release and prove it end-to-end.

2) **manifest-portability-report**
   - Validates all release manifests in `runtime/state/releases/` using `runtime/bin/validate_manifest`.
   - **Phase 96 (Option C) 3-tier portability policy:**
     - **PORTABLE_STRICT**: compat matches host on `{os, arch, python, impl, machine}`
     - **PORTABLE_RELAXED**: compat matches host on `{os, arch, python, impl}` (machine ignored)
     - **HOST_BOUND**: mismatch on any of `{os, arch, python, impl}`
     - **INVALID**: schema/invariants failed
   - Uploads `portability_report.txt` as a workflow artifact.
