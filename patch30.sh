#!/usr/bin/env bash
set -euo pipefail

note(){ echo "==> $*" >&2; }
die(){ echo "ERROR: $*" >&2; exit 1; }

F="runtime/bin/attach_release_signatures"
[[ -f "$F" ]] || die "missing: $F"

backup(){ cp -a "$1" "$1.bak.$(date -u +%Y%m%dT%H%M%SZ)"; }

note "Proving current ordering: validate after attach occurs before signing…"
grep -nE 'validate_manifest|sign_detached' "$F" | sed 's/^/   /' >&2 || true

# Patch by editing the python code in-place using a very targeted transform:
# - remove the early validation block ("manifest failed validation after attach")
# - add a validation block AFTER both sign_detached calls (before verify_release_signatures)

python3 - <<'PY'
import re,sys
path="runtime/bin/attach_release_signatures"
s=open(path,'r',encoding='utf-8').read()

# 1) Remove the early validation block (the one that errors "manifest failed validation after attach")
pat_early = re.compile(
    r'\n\s*# Re-validate after attach.*?\n\s*rc, out, err = run\(\["\./runtime/bin/validate_manifest", mpath\]\)\n\s*if rc != 0:\n\s*return die\(f"manifest failed validation after attach:\\n\{err\.strip\(\)\}"\)\n',
    re.DOTALL
)
s2, n = pat_early.subn("\n", s)
if n != 1:
    print("EARLY_VALIDATION_BLOCK_NOT_FOUND_OR_NOT_UNIQUE", file=sys.stderr)
    sys.exit(2)

# 2) Insert validation block after the two sign_detached calls.
# Find the second sign_detached call (bundle signing) and insert right after it.
insert_after = r'run\(\["\./runtime/bin/sign_detached", "--key", args\.key, "--in", bundle_abs, "--out", bundle_sig_abs\]\)\n\s*if rc != 0:\n\s*return die\(f"sign_detached bundle failed:\\n\{err\.strip\(\)\}"\)\n'
m = re.search(insert_after, s2)
if not m:
    print("BUNDLE_SIGN_BLOCK_NOT_FOUND", file=sys.stderr)
    sys.exit(3)

val_block = """
    # Validate final manifest (now that declared signature files exist)
    rc, out, err = run(["./runtime/bin/validate_manifest", mpath])
    if rc != 0:
        return die(f"manifest failed validation after signing:\\n{err.strip()}")
"""

s3 = s2[:m.end()] + val_block + s2[m.end():]

open(path,'w',encoding='utf-8').write(s3)
PY

note "Patch applied. Re-check ordering (validate_manifest should appear after sign_detached now)…"
grep -nE 'validate_manifest|sign_detached' "$F" | sed 's/^/   /' >&2 || true

note "Fast proof: mint (Phase 90) then Phase 97…"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh >/dev/null
./test/97_test_detached_signatures.sh

note "✅ patch30.sh complete (Phase 97 should now pass)"
