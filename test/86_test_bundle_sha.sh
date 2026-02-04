#!/usr/bin/env bash
# Phase 86 TEST (hardened for Phase 97): verify sha256 matches manifest; do NOT mutate manifest.
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }

: "${RELEASE_ID:?ERROR: RELEASE_ID not set}"

bundle="runtime/state/releases/release_${RELEASE_ID}.tar.gz"
manifest="runtime/state/releases/release_${RELEASE_ID}.json"

[ -f "$bundle" ] || die "bundle missing: $bundle"
[ -f "$manifest" ] || die "manifest missing: $manifest"

echo "Using bundle:   $bundle"
echo "Using manifest: $manifest"

python3 - <<'PY' "$bundle" "$manifest"
import json, sys, hashlib, tarfile

bundle, manifest = sys.argv[1], sys.argv[2]

def sha256_file(p):
    h=hashlib.sha256()
    with open(p,"rb") as f:
        for b in iter(lambda: f.read(1024*1024), b""):
            h.update(b)
    return h.hexdigest()

m=json.load(open(manifest,"r",encoding="utf-8"))
exp=m.get("bundle_sha256","")
act=sha256_file(bundle)

if not exp:
    raise SystemExit("FAIL: manifest bundle_sha256 is empty (should be filled by release_bundle now)")
if exp != act:
    raise SystemExit(f"FAIL: bundle sha mismatch: expected={exp} actual={act}")

# sanity: embedded manifest exists
with tarfile.open(bundle, "r:gz") as tf:
    names=set(tf.getnames())
if m.get("bundle_path","").endswith(".tar.gz"):
    embedded = manifest  # we store the sibling manifest file itself into the tar
    # tar stores relative paths; manifest is runtime/state/releases/release_<RID>.json
    if embedded not in names:
        raise SystemExit(f"FAIL: embedded manifest missing in tarball: {embedded}")

print("OK: bundle sha verified and embedded manifest present")
PY

echo "✅ Phase 86 TEST PASS (bundle sha verified; no mutation)"
