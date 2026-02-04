#!/usr/bin/env bash
# Phase 87 TEST: manifest includes compat contract and matches current host
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }

./runtime/bin/release_bundle >/dev/null

bundle="$(ls -1t runtime/state/releases/release_*.tar.gz 2>/dev/null | head -n 1 || true)"
manifest="$(ls -1t runtime/state/releases/release_*.json 2>/dev/null | head -n 1 || true)"
[ -n "$bundle" ] || die "no release tarball found"
[ -n "$manifest" ] || die "no release manifest found"
[ -f "$bundle" ] || die "bundle not a file: $bundle"
[ -f "$manifest" ] || die "manifest not a file: $manifest"

echo "Using bundle:   $bundle"
echo "Using manifest: $manifest"

python3 - <<'PY' "$manifest"
import json, platform, sys

m=json.load(open(sys.argv[1],"r",encoding="utf-8"))

# required fields
assert isinstance(m.get("schema_version"), int) and m["schema_version"] >= 1, "missing/invalid schema_version"
c=m.get("compat")
assert isinstance(c, dict), "missing compat object"

required=("os","arch","python","impl","machine")
for k in required:
    assert isinstance(c.get(k), str) and c[k], f"compat missing {k}"

host={
  "os": platform.system(),
  "arch": platform.machine(),
  "python": platform.python_version(),
  "impl": platform.python_implementation(),
  "machine": platform.platform(),
}

# strict equality for now (you can relax later if needed)
mism=[]
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
