#!/usr/bin/env bash
set -euo pipefail

note(){ echo "==> $*" >&2; }
die(){ echo "ERROR: $*" >&2; exit 1; }

backup(){
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp -a "$f" "$f.bak.$(date -u +%Y%m%dT%H%M%SZ)"
}

require_file(){ [[ -f "$1" ]] || die "Missing required file: $1"; }

require_file "runtime/bin/attach_release_signatures"
require_file "runtime/bin/release_bundle"
require_file "runtime/bin/validate_manifest"
require_file "test/90_test_all_deterministic.sh"
require_file "test/97_test_detached_signatures.sh"
require_file "test/91_test_no_release_minting.sh"

# --- Inspect current offending literals (proof)
note "Inspecting current signing_alg literals in producers…"
grep -nE 'signing_alg' runtime/bin/attach_release_signatures runtime/bin/release_bundle | sed 's/^/   /' >&2 || true

# --- Fix attach_release_signatures if proven wrong
if grep -q 'd\["signing_alg"\][[:space:]]*=[[:space:]]*"openssl-rsa-sha256"' runtime/bin/attach_release_signatures; then
  note "attach_release_signatures proven wrong -> rewriting constant to rsa-sha256-b64"
  backup runtime/bin/attach_release_signatures
  sed -i -E \
    's/d\["signing_alg"\][[:space:]]*=[[:space:]]*"openssl-rsa-sha256"/d["signing_alg"] = "rsa-sha256-b64"/g' \
    runtime/bin/attach_release_signatures
  chmod +x runtime/bin/attach_release_signatures
else
  note "attach_release_signatures constant already ok (or different form) -> no change"
fi

# --- Fix release_bundle if it writes openssl-rsa-sha256 anywhere
if grep -q '"signing_alg"[[:space:]]*:[[:space:]]*"openssl-rsa-sha256"' runtime/bin/release_bundle \
 || grep -q 'd\["signing_alg"\][[:space:]]*=[[:space:]]*"openssl-rsa-sha256"' runtime/bin/release_bundle; then
  note "release_bundle proven wrong -> rewriting openssl-rsa-sha256 to rsa-sha256-b64"
  backup runtime/bin/release_bundle
  sed -i -E \
    's/"signing_alg"[[:space:]]*:[[:space:]]*"openssl-rsa-sha256"/"signing_alg": "rsa-sha256-b64"/g;
     s/d\["signing_alg"\][[:space:]]*=[[:space:]]*"openssl-rsa-sha256"/d["signing_alg"]="rsa-sha256-b64"/g' \
    runtime/bin/release_bundle
  chmod +x runtime/bin/release_bundle
else
  note "release_bundle has no openssl-rsa-sha256 literal -> no change"
fi

# Keep empty string default for unsigned manifests (allowed)
# (No rewrite needed unless you decide unsigned must omit signing fields.)

# --- Fix populate generator so it doesn't reintroduce the bad label
if [[ -f populate/97_populate_detached_signing.sh ]]; then
  if grep -q 'd\["signing_alg"\][[:space:]]*=[[:space:]]*"openssl-rsa-sha256"' populate/97_populate_detached_signing.sh; then
    note "populate/97_populate_detached_signing.sh proven wrong -> rewriting generator constant"
    backup populate/97_populate_detached_signing.sh
    sed -i -E \
      's/d\["signing_alg"\][[:space:]]*=[[:space:]]*"openssl-rsa-sha256"/d["signing_alg"]="rsa-sha256-b64"/g' \
      populate/97_populate_detached_signing.sh
  else
    note "populate/97_populate_detached_signing.sh ok (or no literal) -> no change"
  fi
fi

note "Re-inspecting producer literals after patch…"
grep -nE 'signing_alg' runtime/bin/attach_release_signatures runtime/bin/release_bundle | sed 's/^/   /' >&2 || true

# --- Run golden proof chain
note "Running golden proof chain after fixing producers…"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh
./test/97_test_detached_signatures.sh
./test/91_test_no_release_minting.sh

note "✅ patch24.sh complete: producer constants fixed + proof chain PASS"
