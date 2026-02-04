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
