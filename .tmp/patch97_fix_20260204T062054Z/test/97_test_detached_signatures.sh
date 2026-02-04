#!/usr/bin/env bash
# Phase 97 TEST: detached signatures exist and verify (manifest + tarball)
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }

: "${RELEASE_ID:?ERROR: RELEASE_ID not set}"

tmp=".tmp/phase97_keys_${RELEASE_ID}"
mkdir -p "$tmp"

priv="$tmp/release_signing_key.pem"
pub="$tmp/release_signing_pub.pem"

# Generate RSA keypair
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$priv" >/dev/null 2>&1 || die "openssl genpkey failed"
openssl pkey -in "$priv" -pubout -out "$pub" >/dev/null 2>&1 || die "openssl pubout failed"

# Mint signed release
SIGNING_KEY_PATH="$priv" SIGNING_PUB_PATH="$pub" \
  ./runtime/bin/release_bundle --release-id "$RELEASE_ID" >/dev/null

bundle="runtime/state/releases/release_${RELEASE_ID}.tar.gz"
manifest="runtime/state/releases/release_${RELEASE_ID}.json"

[ -f "$bundle" ] || die "missing bundle: $bundle"
[ -f "$manifest" ] || die "missing manifest: $manifest"
[ -f "${bundle}.sig.b64" ] || die "missing bundle signature: ${bundle}.sig.b64"
[ -f "${manifest}.sig.b64" ] || die "missing manifest signature: ${manifest}.sig.b64"

# Verify signatures
./runtime/bin/verify_release_signatures --pub "$pub" --manifest "$manifest" >/dev/null

echo "✅ Phase 97 TEST PASS (detached signatures verified)"
