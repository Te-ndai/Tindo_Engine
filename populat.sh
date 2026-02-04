cat > populate/86_populate_bundle_sha.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

cat > note/PHASE_86_BUNDLE_SHA.md <<'MD'
# PHASE 86 — Bundle SHA Verification

Goal:
- Make releases tamper-evident at the bundle level.
- Prove that the tarball bytes match the `bundle_sha256` recorded in the manifest.

Deliverables:
- `test/86_test_bundle_sha.sh`: verifies:
  1) latest release tarball exists
  2) its sha256 matches the sibling manifest `bundle_sha256`
  3) the manifest embedded inside the tarball matches the sibling manifest hash too

Why:
- Prevents "same name, different bytes" and establishes the release as operational evidence.
MD

cat > test/86_test_bundle_sha.sh <<'SH'
#!/usr/bin/env bash
# test/86_test_bundle_sha.sh
# Phase 86 TEST: bundle sha256 matches manifest (and embedded manifest agrees)
set -euo pipefail

die(){ echo "FAIL: $*" >&2; exit 1; }

./runtime/bin/release_bundle >/dev/null

bundle="$(ls -1t runtime/state/releases/release_*.tar.gz 2>/dev/null | head -n 1 || true)"
manifest="$(ls -1t runtime/state/releases/release_*.json 2>/dev/null | head -n 1 || true)"

[ -n "$bundle" ] || die "no release tarball found"
[ -n "$manifest" ] || die "no release manifest found"
[ -f "$bundle" ] || die "bundle path not a file: $bundle"
[ -f "$manifest" ] || die "manifest path not a file: $manifest"

echo "Using bundle:   $bundle"
echo "Using manifest: $manifest"

# Compute sha256 of tarball bytes
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

# Read expected sha from sibling manifest
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

# Read embedded manifest json inside the tarball (release_*.json)
embedded_manifest="$(tar -tzf "$bundle" | grep -E '^runtime/state/releases/release_[0-9TZ]+\.json$' | tail -n 1 || true)"
[ -n "$embedded_manifest" ] || die "no embedded manifest found inside bundle"

embedded_sha="$(tar -xOzf "$bundle" "$embedded_manifest" | python3 - <<'PY'
import json, sys
data=sys.stdin.read()
d=json.loads(data)
v=d.get("bundle_sha256","")
print(v if isinstance(v,str) else "")
PY
)"

[ -n "$embedded_sha" ] || die "embedded manifest missing bundle_sha256"
echo "bundle_sha256 embedded: $embedded_sha"

[ "$embedded_sha" = "$bundle_sha_expected" ] || die "embedded manifest sha differs from sibling manifest sha"

echo "✅ Phase 86 TEST PASS (bundle sha verified)"
SH

chmod +x test/86_test_bundle_sha.sh

echo "OK: Phase 86 POPULATE wrote:"
echo " - note/PHASE_86_BUNDLE_SHA.md"
echo " - test/86_test_bundle_sha.sh"
EOF

chmod +x populate/86_populate_bundle_sha.sh
./populate/86_populate_bundle_sha.sh
