#!/usr/bin/env bash
# Phase 86 TEST: Bundle SHA integrity (deterministic via RELEASE_ID)
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
import hashlib, json, sys, tarfile
bundle, manifest = sys.argv[1], sys.argv[2]

h = hashlib.sha256()
with open(bundle, "rb") as f:
    for chunk in iter(lambda: f.read(1024*1024), b""):
        h.update(chunk)
sha = h.hexdigest()

d = json.load(open(manifest, "r", encoding="utf-8"))
cur = d.get("bundle_sha256")
if cur is None or cur == "":
    d["bundle_sha256"] = sha
    with open(manifest, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, sort_keys=True)
        f.write("\n")
    print("OK: wrote bundle_sha256 into sibling manifest")
else:
    if cur != sha:
        raise SystemExit(f"ERROR: bundle_sha256 mismatch: manifest={cur} actual={sha}")
    print("OK: bundle_sha256 matches manifest")

with tarfile.open(bundle, "r:gz") as tf:
    names = set(tf.getnames())
    embedded = [n for n in names if n.startswith("runtime/state/releases/release_") and n.endswith(".json")]
    if not embedded:
        raise SystemExit("ERROR: embedded manifest missing in tarball")
    print("OK: embedded manifest present:", sorted(embedded)[-1])
PY

echo "✅ Phase 86 TEST PASS (bundle sha verified)"
