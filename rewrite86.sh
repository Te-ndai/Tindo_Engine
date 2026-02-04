#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

ROOT="$(pwd)"
cd "$ROOT/.."

OUT="test/86_test_bundle_sha.sh"
[ -f "$OUT" ] || { echo "❌ missing $OUT" >&2; exit 1; }

B="${OUT}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp -f "$OUT" "$B"
echo "✅ backup: $B"

cat > "$OUT" <<'SH'
#!/usr/bin/env bash
# test/86_test_bundle_sha.sh
# Phase 86 TEST: bundle sha256 matches manifest AND embedded manifest agrees
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

# ---- embedded manifest ----
# List all manifest-like entries inside tarball for diagnostics.
echo "Scanning embedded manifest candidates..."
candidates="$(tar -tzf "$bundle" | grep -E '(^|/)release_[0-9]{8}T[0-9]{6}Z\.json$' || true)"

[ -n "$candidates" ] || {
  echo "---- bundle listing (first 120) ----"
  tar -tzf "$bundle" | sed -n '1,120p'
  die "no embedded release_*.json found in bundle"
}

echo "Candidates:"
echo "$candidates" | sed -n '1,50p'

# Prefer the one under runtime/state/releases if present; otherwise take the last candidate.
embedded_manifest="$(echo "$candidates" | grep -F 'runtime/state/releases/' | tail -n 1 || true)"
if [ -z "$embedded_manifest" ]; then
  embedded_manifest="$(echo "$candidates" | tail -n 1)"
fi

echo "Using embedded manifest: $embedded_manifest"

embedded_json="$(tar -xOzf "$bundle" "$embedded_manifest" 2>/dev/null || true)"
[ -n "$embedded_json" ] || {
  echo "---- tar extract failed or empty ----"
  echo "embedded_manifest=$embedded_manifest"
  echo "Try listing exact entry:"
  tar -tzf "$bundle" | grep -nF "$embedded_manifest" || true
  die "could not extract embedded manifest bytes"
}

embedded_sha="$(python3 - <<'PY'
import json, sys
data=sys.stdin.read()
d=json.loads(data)
v=d.get("bundle_sha256","")
print(v if isinstance(v,str) else "")
PY
<<<"$embedded_json")"

[ -n "$embedded_sha" ] || die "embedded manifest missing bundle_sha256"
echo "bundle_sha256 embedded: $embedded_sha"

[ "$embedded_sha" = "$bundle_sha_expected" ] || die "embedded manifest sha differs from sibling manifest sha"

echo "✅ Phase 86 TEST PASS (bundle sha verified + embedded manifest agrees)"
SH

chmod +x "$OUT"
echo "✅ rewrote: $OUT"
echo "Run:"
echo "  ./test/86_test_bundle_sha.sh"
