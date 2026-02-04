#!/usr/bin/env bash
set -euo pipefail

note(){ echo "==> $*" >&2; }
die(){ echo "ERROR: $*" >&2; exit 1; }

backup(){
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp -a "$f" "$f.bak.$(date -u +%Y%m%dT%H%M%SZ)"
}

F="test/98_test_manifest_signing_invariants.sh"
[[ -f "$F" ]] || die "missing: $F"

note "Inspecting Phase 98 test for os.environ usage without import…"
grep -nE 'os\.environ|^import ' "$F" | sed 's/^/   /' >&2 || true

# Confirm python block has "import os" missing.
# We patch the specific heredoc python that reads os.environ.get("MUT_MODE").
if grep -q 'os\.environ\.get' "$F" && ! awk '
  BEGIN{inpy=0; hasos=0}
  /python3 - .*<<'\''PY'\''/{inpy=1; hasos=0}
  inpy && /^import /{ if($0 ~ /import os/){hasos=1} }
  inpy && /^PY$/{ if(hasos==0){ print "MISSING_OS"; exit 0 } inpy=0 }
  END{ }
' "$F" | grep -q 'MISSING_OS'; then
  note "Proven: python heredoc uses os.environ but lacks import os -> patching"
  backup "$F"

  # Insert "import os" right after the first "import json,sys,copy" line in that heredoc.
  # If that exact line differs, we fail rather than guess.
  if grep -q '^import json,sys,copy$' "$F"; then
    sed -i 's/^import json,sys,copy$/import json,sys,copy\nimport os/' "$F"
  else
    note "Could not find exact line 'import json,sys,copy' to patch safely."
    note "Showing python heredoc block for manual confirmation:"
    nl -ba "$F" | sed -n '30,120p' >&2
    die "Refusing to guess-edit; adjust patch target."
  fi
else
  note "Either no os.environ usage, or import os already present -> no change"
fi

note "Re-run Phase 98 test only (fast proof)…"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh >/dev/null
./test/98_test_manifest_signing_invariants.sh

note "Phase 98 passed. Re-run full chain…"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh
./test/97_test_detached_signatures.sh
./test/91_test_no_release_minting.sh

note "✅ patch27.sh complete"
