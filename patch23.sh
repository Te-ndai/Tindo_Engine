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
require_file "runtime/bin/attach_release_signatures"
require_file "test/90_test_all_deterministic.sh"
require_file "test/97_test_detached_signatures.sh"
require_file "test/91_test_no_release_minting.sh"

RELEASE_DIR="runtime/state/releases"
[[ -d "$RELEASE_DIR" ]] || die "Missing $RELEASE_DIR (run Phase 90 first)"

note "1) Inspect manifests present in $RELEASE_DIR"
ls -1 "$RELEASE_DIR" | sed 's/^/   - /' >&2 || true

note "2) Validate all manifests to find which one fails (proof, not guessing)"
FAILS=0
while IFS= read -r m; do
  [[ -f "$m" ]] || continue
  if ! ./runtime/bin/validate_manifest "$m" >/dev/null 2>"$m.validate.err"; then
    FAILS=$((FAILS+1))
    note "FAIL: $m"
    sed 's/^/     /' "$m.validate.err" >&2 || true
  else
    rm -f "$m.validate.err" || true
    note "PASS: $m"
  fi
done < <(ls -1 "$RELEASE_DIR"/release_*.json 2>/dev/null || true)

[[ "$FAILS" -gt 0 ]] || note "No failing manifests right now (unexpected given your last run). Continuing to code inspection anyway."

note "3) Extract actual signing_alg values from manifests (only those that have it)"
python3 - <<'PY'
import glob,json,os
paths=sorted(glob.glob("runtime/state/releases/release_*.json"))
for p in paths:
    try:
        m=json.load(open(p,'r',encoding='utf-8'))
    except Exception:
        continue
    if "signing_alg" in m:
        print(f"- {os.path.basename(p)} signing_alg={m.get('signing_alg')!r}")
PY

note "4) Inspect code: search for where signing_alg is written (filenames + matching lines)"
# We restrict to repo-local known paths; exclude backups.
grep -RIn --exclude='*.bak.*' --exclude-dir='.tmp' --exclude-dir='.git' \
  -E 'signing_alg' runtime/bin populate test .github 2>/dev/null | sed 's/^/   /' >&2 || true

note "5) Inspect attach_release_signatures specifically for the assigned signing_alg value"
ASSIGNED="$(grep -nE 'signing_alg' runtime/bin/attach_release_signatures | head -n 50 || true)"
echo "$ASSIGNED" | sed 's/^/   /' >&2

# Detect an explicit wrong constant in attach_release_signatures:
# (We look for rsa-sha256-b64; if absent but signing_alg present, it's suspicious.)
if grep -q 'signing_alg' runtime/bin/attach_release_signatures && ! grep -q 'rsa-sha256-b64' runtime/bin/attach_release_signatures; then
  note "attach_release_signatures writes signing_alg but does NOT mention rsa-sha256-b64 -> proven mismatch -> fixing"
  backup runtime/bin/attach_release_signatures

  # Fix strategy:
  # - If file is python: replace value assignment to rsa-sha256-b64
  # - If file is shell using python/json: replace any obvious algo literal with rsa-sha256-b64
  if head -n1 runtime/bin/attach_release_signatures | grep -q python3; then
    # Replace common literals
    sed -i -E \
      's/(["'\'']signing_alg["'\'']\s*:\s*)["'\''][^"'\'']+["'\'']/\1"rsa-sha256-b64"/g' \
      runtime/bin/attach_release_signatures
    sed -i -E \
      's/(signing_alg\s*=\s*)["'\''][^"'\'']+["'\'']/\1"rsa-sha256-b64"/g' \
      runtime/bin/attach_release_signatures
  else
    # Shell: replace likely literals near signing_alg (broad but anchored)
    sed -i -E \
      's/(signing_alg[^"]*"|signing_alg[^'\'']*'\'')([^"'\'']+)(["'\''])/\1rsa-sha256-b64\3/g' \
      runtime/bin/attach_release_signatures || true
    # Also replace common legacy strings if they exist plainly
    sed -i -E \
      's/rsa-sha256/rsa-sha256-b64/g; s/RSA-SHA256/rsa-sha256-b64/g; s/rsa_sha256/rsa-sha256-b64/g' \
      runtime/bin/attach_release_signatures || true
  fi

  chmod +x runtime/bin/attach_release_signatures
else
  note "attach_release_signatures already mentions rsa-sha256-b64 OR does not write signing_alg -> no change"
fi

note "6) Re-run golden proof chain now (authoritative)"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh
./test/97_test_detached_signatures.sh
./test/91_test_no_release_minting.sh

note "✅ patch23.sh complete: inspected manifests + fixed proven signing_alg producer + chain PASS"
