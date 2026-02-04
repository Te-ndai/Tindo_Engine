#!/usr/bin/env bash
# Phase 86 TEST: bundle SHA matches sibling manifest (container integrity)
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

bundle_sha_actual="$(python3 - <<'PY' "$bundle"
import hashlib, sys
p=sys.argv[1]
h=hashlib.sha256()
with open(p,"rb") as f:
    for b in iter(lambda: f.read(1024*1024), b""):
        h.update(b)
print(h.hexdigest())
PY
)"

bundle_sha_expected="$(python3 - <<'PY' "$manifest"
import json, sys
d=json.load(open(sys.argv[1],"r",encoding="utf-8"))
v=d.get("bundle_sha256","")
print(v if isinstance(v,str) else "")
PY
)"
[ -n "$bundle_sha_expected" ] || die "manifest missing bundle_sha256"

echo "bundle_sha256 expected: $bundle_sha_expected"
echo "bundle_sha256 actual:   $bundle_sha_actual"
[ "$bundle_sha_actual" = "$bundle_sha_expected" ] || die "bundle sha mismatch"

# Sanity: embedded manifest exists (content may be pre-hash; that's OK)
embedded="$(tar -tzf "$bundle" | grep -E '^runtime/state/releases/release_[0-9]{8}T[0-9]{6}Z\.json$' | tail -n 1 || true)"
[ -n "$embedded" ] || die "bundle missing embedded manifest entry"
echo "OK: embedded manifest present: $embedded"

echo "✅ Phase 86 TEST PASS (bundle sha verified)"
