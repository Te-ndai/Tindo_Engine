#!/usr/bin/env bash
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }

fails=0
for m in runtime/state/releases/release_*.json; do
  ./runtime/bin/validate_manifest "$m" >/dev/null 2>&1 || { echo "INVALID_IN_MAIN: $m" >&2; fails=1; }
done

[ "$fails" -eq 0 ] || die "main releases dir contains invalid manifests"
echo "✅ Phase 102 TEST PASS (main releases dir contains only valid manifests)"
