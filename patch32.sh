#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo "==> $*" >&2; }

RID="${1:-20260203T122312Z}"
REL_DIR="runtime/state/releases"
LEG_DIR="$REL_DIR/legacy"
DEST="$LEG_DIR/bundle_sha256_invalid/release_${RID}"

manifest="$REL_DIR/release_${RID}.json"
bundle="$REL_DIR/release_${RID}.tar.gz"
msig="$REL_DIR/release_${RID}.json.sig.b64"
bsig="$REL_DIR/release_${RID}.tar.gz.sig.b64"
verr="$REL_DIR/release_${RID}.json.validate.err"

note "Target RID=$RID"
note "manifest=$manifest"
note "bundle=$bundle"
note "dest=$DEST"

ls -l "$manifest" || die "missing manifest"
ls -l "$bundle" || note "bundle missing (ok, will skip mv)"
mkdir -p "$LEG_DIR" || true

set -x
mkdir -p "$DEST"

# show filesystem type + mount options (WSL can be weird)
set +x
note "FS diagnostics (dest parent):"
df -T "$REL_DIR" | sed 's/^/   /' >&2 || true
mount | grep -E ' /mnt/| /mnt/c' | head -n 5 | sed 's/^/   /' >&2 || true

# Now move one by one with explicit error messages
move_one(){
  local f="$1"
  [[ -f "$f" ]] || { note "skip missing: $f"; return 0; }
  note "mv -f $f -> $DEST/"
  mv -f "$f" "$DEST/"
}

# Run moves
move_one "$manifest"
move_one "$bundle"
move_one "$msig"
move_one "$bsig"
move_one "$verr"

note "Done. Listing dest:"
find "$DEST" -maxdepth 1 -type f -printf "   %f\n" >&2 || true
