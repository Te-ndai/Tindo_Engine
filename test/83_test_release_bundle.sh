#!/usr/bin/env bash
# Phase 83 TEST: release bundle contains required evidence + manifest core fields
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }

: "${RELEASE_ID:?ERROR: RELEASE_ID not set}"

# Create the deterministic release for this RELEASE_ID
./runtime/bin/release_bundle --release-id "$RELEASE_ID" >/dev/null

bundle="runtime/state/releases/release_${RELEASE_ID}.tar.gz"
manifest="runtime/state/releases/release_${RELEASE_ID}.json"

[ -f "$bundle" ] || die "bundle missing: $bundle"
[ -f "$manifest" ] || die "manifest missing: $manifest"

python3 - <<'PY' "$bundle"
import sys, tarfile
bundle = sys.argv[1]
required = {
  "runtime/state/reports/diagnose.txt",
  "runtime/state/logs/executions.chain.jsonl",
  "runtime/state/logs/executions.chain.checkpoint.json",
  "runtime/state/logs/executions.jsonl",
  "runtime/bin/logchain_verify",
  "runtime/bin/rebuild_projections",
  "runtime/bin/ops",
  "runtime/core/projections.py",
}
with tarfile.open(bundle, "r:gz") as tf:
    names = set(tf.getnames())
missing = sorted(required - names)
if missing:
    print("MISSING:")
    for m in missing:
        print(" -", m)
    raise SystemExit(1)
print("OK: required members present")
PY

./runtime/bin/validate_manifest "$manifest" --release-id "$RELEASE_ID" >/dev/null
echo "OK: manifest validated (schema + invariants)"
