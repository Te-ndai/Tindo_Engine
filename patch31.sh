#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo "==> $*" >&2; }

MODE="dry-run"  # dry-run | apply
ROOT="$(pwd)"
REL_DIR="runtime/state/releases"
LEG_DIR="$REL_DIR/legacy"
REP_DIR="runtime/state/reports"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="$REP_DIR/phase102_hygiene_${TS}.txt"
LATEST="$REP_DIR/phase102_hygiene_latest.txt"

usage(){
  cat >&2 <<EOF
usage: ./patch102_hygiene.sh [--dry-run] [--apply]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --apply) MODE="apply"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -d "$REL_DIR" ]] || die "missing: $REL_DIR"
[[ -x runtime/bin/validate_manifest ]] || die "missing executable: runtime/bin/validate_manifest"
mkdir -p "$LEG_DIR" "$REP_DIR"

# trap to show line number on unexpected exit
trap 'echo "ERROR: hygiene aborted at line $LINENO" >&2' ERR

classify_reason(){
  # input: full validator stderr on stdin
  local msg
  msg="$(cat)"
  if echo "$msg" | grep -q 'bundle_sha256 must be 64-char lowercase hex'; then
    echo "bundle_sha256_invalid"
  elif echo "$msg" | grep -q 'signing_alg must be rsa-sha256-b64'; then
    echo "signing_alg_invalid"
  elif echo "$msg" | grep -q 'declared manifest signature missing'; then
    echo "signature_missing"
  elif echo "$msg" | grep -q 'declared bundle signature missing'; then
    echo "signature_missing"
  else
    echo "manifest_invalid_other"
  fi
}

move_if_exists(){
  local f="$1" dest="$2"
  [[ -f "$f" ]] && mv -f "$f" "$dest/"
}

{
  echo "PHASE 102 HYGIENE"
  echo "timestamp_utc=$TS"
  echo "mode=$MODE"
  echo "root=$ROOT"
  echo "scan_dir=$REL_DIR"
  echo
  echo "RID | status | reason_code | detail | moved_to"
  echo "----|--------|------------|--------|--------"
} > "$REPORT"

count_total=0
count_ok=0
count_quarantine=0
count_moved=0

shopt -s nullglob
for manifest in "$REL_DIR"/release_*.json; do
  [[ "$manifest" == *"/legacy/"* ]] && continue

  base="$(basename "$manifest")"
  rid="${base#release_}"; rid="${rid%.json}"

  bundle="$REL_DIR/release_${rid}.tar.gz"
  msig="$REL_DIR/release_${rid}.json.sig.b64"
  bsig="$REL_DIR/release_${rid}.tar.gz.sig.b64"
  verr="$REL_DIR/release_${rid}.json.validate.err"

  count_total=$((count_total+1))

  status="OK"
  reason_code="-"
  detail="-"
  moved_to="-"

  if ! runtime/bin/validate_manifest "$manifest" >/dev/null 2>"$verr"; then
    status="QUARANTINE"
    detail="$(tr '\n' ' ' < "$verr" | sed -E 's/[[:space:]]+/ /g')"
    reason_code="$(printf "%s" "$detail" | classify_reason)"
  else
    rm -f "$verr" || true
  fi

  if [[ "$status" == "OK" && ! -f "$bundle" ]]; then
    status="QUARANTINE"
    reason_code="bundle_missing"
    detail="bundle missing: $(basename "$bundle")"
  fi

  if [[ "$status" == "OK" ]]; then
    echo "$rid | OK | - | - | -" >> "$REPORT"
    count_ok=$((count_ok+1))
    continue
  fi

  count_quarantine=$((count_quarantine+1))
  dest="$LEG_DIR/$reason_code/release_${rid}"
  moved_to="$dest"

  # keep detail shortish in table but still informative
  short_detail="$(echo "$detail" | cut -c1-180)"
  echo "$rid | QUARANTINE | $reason_code | $short_detail | $dest" >> "$REPORT"

  if [[ "$MODE" == "dry-run" ]]; then
    continue
  fi

  note "moving RID=$rid -> $dest"
  mkdir -p "$dest"
  move_if_exists "$manifest" "$dest"
  move_if_exists "$bundle" "$dest"
  move_if_exists "$msig" "$dest"
  move_if_exists "$bsig" "$dest"
  move_if_exists "$verr" "$dest"
  count_moved=$((count_moved+1))
done

{
  echo
  echo "SUMMARY"
  echo "total_manifests=$count_total"
  echo "ok_kept=$count_ok"
  echo "quarantined=$count_quarantine"
  echo "moved=$count_moved"
} >> "$REPORT"

cp -f "$REPORT" "$LATEST"

note "Wrote report: $REPORT"
note "Wrote latest: $LATEST"
note "Done. total=$count_total ok=$count_ok quarantined=$count_quarantine moved=$count_moved"
