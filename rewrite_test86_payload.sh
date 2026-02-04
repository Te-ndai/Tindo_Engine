#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

OUT="test/86_test_bundle_sha.sh"
[ -f "$OUT" ] || { echo "❌ missing $OUT" >&2; exit 1; }

B="${OUT}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp -f "$OUT" "$B"
echo "✅ backup: $B"

cat > "$OUT" <<'SH'
#!/usr/bin/env bash
# Phase 86 TEST: verify bundle_sha256 (container) and payload_sha256 (content set)
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }

./runtime/bin/release_bundle >/dev/null

bundle="$(ls -1t runtime/state/releases/release_*.tar.gz 2>/dev/null | head -n 1 || true)"
manifest="$(ls -1t runtime/state/releases/release_*.json 2>/dev/null | head -n 1 || true)"
[ -n "$bundle" ] || die "no release tarball found"
[ -n "$manifest" ] || die "no release manifest found"

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
print(d.get("bundle_sha256","") or "")
PY
)"
[ -n "$bundle_sha_expected" ] || die "manifest missing bundle_sha256"
echo "bundle_sha256 expected: $bundle_sha_expected"
echo "bundle_sha256 actual:   $bundle_sha_actual"
[ "$bundle_sha_actual" = "$bundle_sha_expected" ] || die "bundle sha mismatch"

# Find embedded manifest
embedded_manifest="$(tar -tzf "$bundle" | grep -E '^runtime/state/releases/release_[0-9]{8}T[0-9]{6}Z\.json$' | tail -n 1 || true)"
[ -n "$embedded_manifest" ] || die "no embedded manifest found in bundle"
echo "Using embedded manifest: $embedded_manifest"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
emb="$tmpdir/embedded.json"
tar -xOzf "$bundle" "$embedded_manifest" > "$emb" || die "failed to extract embedded manifest"

payload_expected="$(python3 - <<'PY' "$emb"
import json, sys
d=json.load(open(sys.argv[1],"r",encoding="utf-8"))
v=d.get("payload_sha256","") or ""
print(v)
PY
)"
[ -n "$payload_expected" ] || die "embedded manifest missing payload_sha256"
echo "payload_sha256 embedded: $payload_expected"

# Recompute payload hash from tar members excluding embedded manifest itself
payload_actual="$(python3 - <<'PY' "$bundle" "$embedded_manifest"
import hashlib, tarfile, sys
bundle=sys.argv[1]
skip=sys.argv[2]

h=hashlib.sha256()
with tarfile.open(bundle, "r:gz") as tf:
    names=sorted(n for n in tf.getnames() if n != skip)
    for name in names:
        ti=tf.getmember(name)
        if ti.isdir():  # directories are in tar listing; ignore (your payload hash is file-bytes based)
            continue
        f=tf.extractfile(ti)
        if f is None:
            continue
        h.update(name.encode("utf-8") + b"\0")
        while True:
            b=f.read(1024*1024)
            if not b: break
            h.update(b)
print(h.hexdigest())
PY
)"
echo "payload_sha256 actual:   $payload_actual"

[ "$payload_actual" = "$payload_expected" ] || die "payload sha mismatch"

echo "✅ Phase 86 TEST PASS (bundle + payload integrity verified)"
SH

chmod +x "$OUT"
echo "✅ rewrote: $OUT"
echo "Run:"
echo "  ./test/86_test_bundle_sha.sh"
