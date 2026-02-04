#!/usr/bin/env bash
set -euo pipefail

note(){ echo "==> $*" >&2; }
die(){ echo "ERROR: $*" >&2; exit 1; }

F="runtime/bin/attach_release_signatures"
[[ -f "$F" ]] || die "missing: $F"

backup(){ cp -a "$1" "$1.bak.$(date -u +%Y%m%dT%H%M%SZ)"; }

OLD='bundle_abs = bundle_path if os.path.isabs(bundle_path) else os.path.normpath(os.path.join(mdir, bundle_path))'

note "Proving target line exists…"
grep -nF "$OLD" "$F" | sed 's/^/   /' >&2 || true

COUNT="$(grep -cF "$OLD" "$F" || true)"
[[ "$COUNT" == "1" ]] || die "Expected exactly 1 occurrence of target line, found: $COUNT"

note "Backing up $F"
backup "$F"

note "Patching bundle_abs resolution deterministically…"
python3 - <<'PY'
import io,sys
path="runtime/bin/attach_release_signatures"
OLD='bundle_abs = bundle_path if os.path.isabs(bundle_path) else os.path.normpath(os.path.join(mdir, bundle_path))'
NEW="""# Resolve bundle path deterministically:
    # - absolute stays absolute
    # - repo-relative (contains / or \\\\) resolved from current working dir (repo root)
    # - basename-only treated as sibling of manifest
    if os.path.isabs(bundle_path):
        bundle_abs = bundle_path
    elif ("/" in bundle_path) or ("\\\\" in bundle_path):
        bundle_abs = os.path.normpath(os.path.join(os.getcwd(), bundle_path))
    else:
        bundle_abs = os.path.normpath(os.path.join(mdir, bundle_path))"""

with open(path,"r",encoding="utf-8") as f:
    s=f.read()

if s.count(OLD)!=1:
    raise SystemExit(f"Refusing to patch: expected 1 occurrence, found {s.count(OLD)}")

s2=s.replace(OLD, NEW)

with open(path,"w",encoding="utf-8") as f:
    f.write(s2)
PY

chmod +x "$F"

note "Re-verify patched block is present…"
grep -nE 'repo-relative|os\.getcwd\(\)|bundle_abs' "$F" | sed 's/^/   /' >&2 || true

note "Fast proof: Phase 97 only (after mint from Phase 90)…"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh >/dev/null
./test/97_test_detached_signatures.sh

note "Now full proof trio…"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh
./test/97_test_detached_signatures.sh
./test/91_test_no_release_minting.sh

note "✅ patch29b.sh complete"
