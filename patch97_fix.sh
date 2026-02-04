#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

die(){ echo "FAIL: $*" >&2; exit 1; }
ok(){ echo "OK: $*"; }

ts="$(date -u +%Y%m%dT%H%M%SZ)"
bakdir=".tmp/patch97_fix_${ts}"
mkdir -p "$bakdir"

backup(){
  local f="$1"
  [ -f "$f" ] || return 0
  mkdir -p "$bakdir/$(dirname "$f")"
  cp -f "$f" "$bakdir/$f"
  ok "backup: $f -> $bakdir/$f"
}

[ -d runtime/bin ] || die "missing runtime/bin"
[ -d test ] || die "missing test"
[ -x runtime/bin/validate_manifest ] || die "missing runtime/bin/validate_manifest (Phase 93)"
[ -x runtime/bin/sign_detached ] || die "missing runtime/bin/sign_detached (Phase 97)"
[ -x runtime/bin/verify_release_signatures ] || die "missing runtime/bin/verify_release_signatures (Phase 97)"

backup runtime/bin/attach_release_signatures
backup test/97_test_detached_signatures.sh

# ------------------------------------------------------------
# 1) Add runtime/bin/attach_release_signatures
#    This does NOT mint. It signs an existing release_<RID>.json and .tar.gz.
#    It updates manifest metadata BEFORE signing (one-time), then signs both files.
# ------------------------------------------------------------
cat > runtime/bin/attach_release_signatures <<'BASH'
#!/usr/bin/env bash
# Attach detached signatures to an existing release (manifest + tarball) without minting.
# Mutates the manifest ONCE to add signature metadata, then signs the final manifest bytes.
set -euo pipefail
die(){ echo "ERROR: $*" >&2; exit 1; }

MANIFEST=""
KEY=""
PUB=""
while [ $# -gt 0 ]; do
  case "$1" in
    --manifest) shift; MANIFEST="${1:-}"; shift ;;
    --key)      shift; KEY="${1:-}"; shift ;;
    --pub)      shift; PUB="${1:-}"; shift ;;
    -h|--help)
      echo "usage: attach_release_signatures --manifest release_<RID>.json --key priv.pem --pub pub.pem" >&2
      exit 2
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

[ -n "$MANIFEST" ] || die "missing --manifest"
[ -n "$KEY" ] || die "missing --key"
[ -n "$PUB" ] || die "missing --pub"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"
[ -f "$KEY" ] || die "key not found: $KEY"
[ -f "$PUB" ] || die "pub not found: $PUB"

bundle="$(python3 - <<'PY' "$MANIFEST"
import json,sys
m=json.load(open(sys.argv[1],"r",encoding="utf-8"))
print(m.get("bundle_path",""))
PY
)"
[ -n "$bundle" ] || die "manifest missing bundle_path"
[ -f "$bundle" ] || die "bundle not found at bundle_path: $bundle"

msig="${MANIFEST}.sig.b64"
bsig="${bundle}.sig.b64"
fp="$(sha256sum "$PUB" | awk '{print $1}')"

# 1) Update manifest with signature metadata BEFORE signing it.
python3 - <<'PY' "$MANIFEST" "$fp" "$msig" "$bsig"
import json, sys
mp, fp, msig, bsig = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d=json.load(open(mp,"r",encoding="utf-8"))

# If it's already signed, refuse (signatures would become meaningless if we mutate afterwards)
if d.get("manifest_sig_b64_path") or d.get("bundle_sig_b64_path") or d.get("signing_pub_fingerprint_sha256"):
    raise SystemExit("ERROR: manifest already has signing metadata; refusing to mutate")

d["signing_alg"] = "openssl-rsa-sha256"
d["signing_pub_fingerprint_sha256"] = fp
d["manifest_sig_b64_path"] = msig
d["bundle_sig_b64_path"] = bsig

json.dump(d, open(mp,"w",encoding="utf-8"), indent=2, sort_keys=True)
open(mp,"a",encoding="utf-8").write("\n")
print("OK: manifest updated with signing metadata (pre-sign)")
PY

# 2) Sign final manifest bytes and tarball bytes (detached)
./runtime/bin/sign_detached --key "$KEY" --in "$MANIFEST" --out "$msig" >/dev/null
./runtime/bin/sign_detached --key "$KEY" --in "$bundle"   --out "$bsig" >/dev/null

# 3) Validate manifest invariants after attach
rid="$(python3 - <<'PY' "$MANIFEST"
import json,sys
m=json.load(open(sys.argv[1],"r",encoding="utf-8"))
print(m.get("release_id",""))
PY
)"
if [ -n "$rid" ]; then
  ./runtime/bin/validate_manifest "$MANIFEST" --release-id "$rid" >/dev/null
else
  ./runtime/bin/validate_manifest "$MANIFEST" >/dev/null
fi

echo "OK: attached signatures:"
echo " - $msig"
echo " - $bsig"
BASH
chmod +x runtime/bin/attach_release_signatures
ok "wrote runtime/bin/attach_release_signatures"

# ------------------------------------------------------------
# 2) Rewrite test/97_test_detached_signatures.sh
#    MUST NOT mint. Uses the release created by Phase 90 (Phase 83 inside it).
# ------------------------------------------------------------
cat > test/97_test_detached_signatures.sh <<'T97'
#!/usr/bin/env bash
# Phase 97 TEST: sign + verify an EXISTING release (no minting; Phase 91 compatible)
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }

: "${RELEASE_ID:?ERROR: RELEASE_ID not set}"

manifest="runtime/state/releases/release_${RELEASE_ID}.json"
bundle="runtime/state/releases/release_${RELEASE_ID}.tar.gz"

[ -f "$manifest" ] || die "missing manifest (mint via Phase 90 first): $manifest"
[ -f "$bundle" ] || die "missing bundle (mint via Phase 90 first): $bundle"

tmp=".tmp/phase97_keys_${RELEASE_ID}"
mkdir -p "$tmp"
priv="$tmp/release_signing_key.pem"
pub="$tmp/release_signing_pub.pem"

# Generate RSA keypair
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$priv" >/dev/null 2>&1 || die "openssl genpkey failed"
openssl pkey -in "$priv" -pubout -out "$pub" >/dev/null 2>&1 || die "openssl pubout failed"

# Attach signatures WITHOUT minting
./runtime/bin/attach_release_signatures --manifest "$manifest" --key "$priv" --pub "$pub" >/dev/null

# Verify signatures
./runtime/bin/verify_release_signatures --pub "$pub" --manifest "$manifest" >/dev/null

echo "✅ Phase 97 TEST PASS (detached signatures attached + verified; no minting)"
T97
chmod +x test/97_test_detached_signatures.sh
ok "rewrote test/97_test_detached_signatures.sh (no minting)"

ok "patch97_fix complete"
echo "Backups: $bakdir"
echo "Next run:"
echo '  RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"'
echo '  ./test/90_test_all_deterministic.sh'
echo '  ./test/97_test_detached_signatures.sh'
echo '  ./test/91_test_no_release_minting.sh'
