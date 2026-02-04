#!/usr/bin/env bash
set -euo pipefail

note(){ echo "==> $*" >&2; }
die(){ echo "ERROR: $*" >&2; exit 1; }

F="test/98_test_manifest_signing_invariants.sh"
[[ -f "$F" ]] || die "missing: $F"

backup(){
  cp -a "$1" "$1.bak.$(date -u +%Y%m%dT%H%M%SZ)"
}

note "Proving the failing snippet exists (import json,sys,copy + os.environ)…"
grep -nE '^import json,sys,copy$|os\.environ\.get' "$F" | sed 's/^/   /' >&2 || true

# If os.environ is used but import os is not present anywhere in that heredoc block,
# we do the minimal safe insertion after the exact import line.
if grep -q 'os\.environ\.get' "$F"; then
  # If file already has 'import os' anywhere, we still might be missing it in the right heredoc.
  # So we patch by adding it right after the exact line in-place, but only if the next line isn't already import os.
  LINE_NUM="$(grep -n '^import json,sys,copy$' "$F" | cut -d: -f1 | head -n1 || true)"
  [[ -n "$LINE_NUM" ]] || die "could not find exact line: import json,sys,copy"

  NEXT_LINE="$(awk -v n=$((LINE_NUM+1)) 'NR==n{print}' "$F")"
  if echo "$NEXT_LINE" | grep -q '^import os$'; then
    note "import os already present immediately after import json,sys,copy -> no change"
  else
    note "Inserting 'import os' after line $LINE_NUM"
    backup "$F"
    awk -v insert_after="$LINE_NUM" 'NR==insert_after{print; print "import os"; next} {print}' "$F" > "$F.tmp"
    mv "$F.tmp" "$F"
    chmod +x "$F" || true
  fi
else
  die "os.environ.get not found; refusing to patch blindly"
fi

note "Proof: show imports around the patched area"
nl -ba "$F" | sed -n "$((LINE_NUM-2)),$((LINE_NUM+5))p" | sed 's/^/   /' >&2

note "Run Phase 98 test only (fast proof)…"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh >/dev/null
./test/98_test_manifest_signing_invariants.sh

note "✅ patch28.sh complete (Phase 98 now executes)"
