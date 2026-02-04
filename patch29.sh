#!/usr/bin/env bash
set -euo pipefail

note(){ echo "==> $*" >&2; }
die(){ echo "ERROR: $*" >&2; exit 1; }

F="runtime/bin/attach_release_signatures"
[[ -f "$F" ]] || die "missing: $F"

backup(){ cp -a "$1" "$1.bak.$(date -u +%Y%m%dT%H%M%SZ)"; }

note "Proving current bundle_path resolution logic (show lines mentioning bundle_path/bundle_abs)…"
grep -nE 'bundle_path|bundle_abs|os\.path\.isabs|join\(mdir' "$F" | sed 's/^/   /' >&2 || true

# We patch by rewriting the specific block that sets bundle_abs.
# We will only proceed if we can find the exact old lines we wrote.
if grep -q 'bundle_abs = bundle_path if os.path.isabs(bundle_path) else os.path.normpath(os.path.join(mdir, bundle_path))' "$F"; then
  note "Found old join(mdir, bundle_path) logic -> patching to repo-root aware resolution"
  backup "$F"

  # Replace that single line with a safer resolution block.
  # Insert a small block in-place.
  perl -0777 -pe 's/bundle_abs = bundle_path if os\.path\.isabs\(bundle_path\) else os\.path\.normpath\(os\.path\.join\(mdir, bundle_path\)\)/# Resolve bundle path deterministically:\n    # - absolute stays absolute\n    # - repo-relative (contains \/ or \\\\) resolved from current working dir (repo root)\n    # - basename-only treated as sibling of manifest\n    if os.path.isabs(bundle_path):\n        bundle_abs = bundle_path\n    elif (\"/\" in bundle_path) or (\"\\\\\\\\\" in bundle_path):\n        bundle_abs = os.path.normpath(os.path.join(os.getcwd(), bundle_path))\n    else:\n        bundle_abs = os.path.normpath(os.path.join(mdir, bundle_path))/s' \
    "$F" > "$F.tmp"

  mv "$F.tmp" "$F"
  chmod +x "$F"
else
  note "Did not find expected line to patch; refusing to guess-edit."
  note "Show a larger window so you can choose exact patch target:"
  nl -ba "$F" | sed -n '1,180p' >&2
  die "attach_release_signatures patch target not found"
fi

note "Sanity check: re-grep bundle_abs block"
grep -nE 'bundle_abs|os\.getcwd' "$F" | sed 's/^/   /' >&2 || true

note "Re-run Phase 97 only (fast proof, no full chain)…"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh >/dev/null
./test/97_test_detached_signatures.sh
note "✅ Phase 97 PASS"

note "Re-run golden proof trio…"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh
./test/97_test_detached_signatures.sh
./test/91_test_no_release_minting.sh

note "✅ patch29.sh complete"
