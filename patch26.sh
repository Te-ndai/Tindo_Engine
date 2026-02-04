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

require_file "runtime/bin/validate_manifest"
require_file "test/83_test_release_bundle.sh"
require_file "test/90_test_all_deterministic.sh"
require_file "test/97_test_detached_signatures.sh"
require_file "test/91_test_no_release_minting.sh"

note "Inspecting validate_manifest 'present' logic (proof)…"
grep -nE 'present\s*=|signing_fields\s*=' runtime/bin/validate_manifest | sed 's/^/   /' >&2 || true

# We patch ONLY the definition of `present` so that empty strings are treated as absent.
# Current buggy pattern in your rewritten validator:
#   present = [k for k in signing_fields if k in m and m[k] is not None]
#
# Correct:
#   present = [k for k in signing_fields if k in m and m[k] not in (None, "")]
#
# This is the minimal change that fixes Phase 83 without touching producers.

if grep -qE 'present\s*=\s*\[k for k in signing_fields if k in m and m\[k\] is not None\]' runtime/bin/validate_manifest; then
  note "validate_manifest present-logic proven buggy (counts empty strings as present) -> patching that single line"
  backup runtime/bin/validate_manifest
  sed -i -E \
    's/present\s*=\s*\[k for k in signing_fields if k in m and m\[k\] is not None\]/present = [k for k in signing_fields if k in m and m[k] not in (None, "")]/' \
    runtime/bin/validate_manifest
else
  note "Could not match the exact buggy present-line. Showing surrounding code so you can confirm manually:"
  nl -ba runtime/bin/validate_manifest | sed -n '55,105p' >&2
  die "validate_manifest present-line did not match expected pattern; refusing to guess-edit."
fi

note "Re-check validate_manifest present logic after patch…"
grep -nE 'present\s*=' runtime/bin/validate_manifest | sed 's/^/   /' >&2 || true

# Fast proof: Phase 83 only (this is where you fail)
note "Running Phase 83 only (should now pass)…"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
bash -x ./test/83_test_release_bundle.sh 2>&1 | tee /tmp/trace83_after_patch26.txt

note "Phase 83 passed. Now running golden proof chain…"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh
./test/97_test_detached_signatures.sh
./test/91_test_no_release_minting.sh

note "✅ patch26.sh complete"
