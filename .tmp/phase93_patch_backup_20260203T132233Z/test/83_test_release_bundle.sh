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

python3 - <<'PY' "$manifest" "$RELEASE_ID"
import json, sys

manifest_path = sys.argv[1]
rid = sys.argv[2]

d = json.load(open(manifest_path, "r", encoding="utf-8"))

# Identity / determinism
assert d.get("release_id") == rid, f"release_id mismatch: manifest={d.get('release_id')!r} expected={rid!r}"
expected_bundle = f"runtime/state/releases/release_{rid}.tar.gz"
assert d.get("bundle_path") == expected_bundle, f"bundle_path mismatch: manifest={d.get('bundle_path')!r} expected={expected_bundle!r}"

# Schema basics
assert "schema_version" in d, "missing schema_version"

# Compat contract (canonical in producer)
c = d.get("compat")
assert isinstance(c, dict), "missing/invalid compat"
for k in ("os","arch","python","impl","machine"):
    assert isinstance(c.get(k), str) and c[k], f"compat missing {k}"
assert c["os"] == c["os"].lower(), "compat.os must be lowercase"
assert c["arch"] == c["arch"].lower(), "compat.arch must be lowercase"
assert c["impl"] == c["impl"].lower(), "compat.impl must be lowercase"

# Expectations (pre-86 sha allowed empty)
assert isinstance(d.get("expected_event_count"), int), "missing/invalid expected_event_count"
assert isinstance(d.get("expected_last_event_time_utc"), str), "missing/invalid expected_last_event_time_utc"
assert isinstance(d.get("bundle_sha256"), str), "missing/invalid bundle_sha256 key"

print("OK: manifest contract present + deterministic identity validated")
PY
