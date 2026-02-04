#!/usr/bin/env bash
# Phase 87 TEST: manifest includes compat contract and matches current host
# Deterministic via RELEASE_ID (does NOT mint new releases)
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }

: "${RELEASE_ID:?ERROR: RELEASE_ID not set}"

bundle="runtime/state/releases/release_${RELEASE_ID}.tar.gz"
manifest="runtime/state/releases/release_${RELEASE_ID}.json"
[ -f "$bundle" ] || die "bundle not found for RELEASE_ID: $bundle"
[ -f "$manifest" ] || die "manifest not found for RELEASE_ID: $manifest"

echo "Using bundle:   $bundle"
echo "Using manifest: $manifest"

python3 - <<'PY' "$manifest"
import json, platform, sys

m = json.load(open(sys.argv[1], "r", encoding="utf-8"))

# required fields
assert isinstance(m.get("schema_version"), int) and m["schema_version"] >= 1, "missing/invalid schema_version"
c = m.get("compat")
assert isinstance(c, dict), "missing compat object"

required = ("os","arch","python","impl","machine")
for k in required:
    assert isinstance(c.get(k), str) and c[k], f"compat missing {k}"

# Canonicalize host for case-insensitive fields to match producer:
host = {
  "os": platform.system().lower(),
  "arch": platform.machine().lower(),
  "python": platform.python_version(),
  "impl": platform.python_implementation().lower(),
  "machine": platform.platform(),
}

# Strict equality for now (including machine)
mism = []
for k in required:
    if c.get(k) != host.get(k):
        mism.append((k, c.get(k), host.get(k)))

if mism:
    print("COMPAT_MISMATCH:")
    for k, exp, act in mism:
        print(f" - {k}: manifest={exp!r} host={act!r}")
    raise SystemExit(2)

print("OK: compat matches host")
PY

echo "✅ Phase 87 TEST PASS (compat contract)"
