#!/usr/bin/env bash
set -u  # NOTE: no -e; we handle errors per-RID

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

usage(){ echo "usage: ./patch102_hygiene.sh [--dry-run] [--apply]" >&2; }

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
mkdir -p "$LEG_DIR" "$REP_DIR" || die "cannot create legacy/report dirs"

classify_reason(){
  local msg; msg="$(cat)"
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

mv_one(){
  local src="$1" destdir="$2"
  [[ -f "$src" ]] || return 0
  mv -f "$src" "$destdir/" 2>/tmp/hygiene_mv_err.txt
  return $?
}

{
  echo "PHASE 102 HYGIENE"
  echo "timestamp_utc=$TS"
  echo "mode=$MODE"
  echo "root=$ROOT"
  echo "scan_dir=$REL_DIR"
  echo
  echo "RID | status | reason_code | detail | moved_to | move_errors"
  echo "----|--------|------------|--------|----------|-----------"
} > "$REPORT"

count_total=0
count_ok=0
count_quarantine=0
count_moved=0
count_errors=0
count_skipped=0

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
  move_errors="-"

  # Validate (authoritative)
  if ! runtime/bin/validate_manifest "$manifest" >/dev/null 2>"$verr"; then
    status="QUARANTINE"
    detail="$(tr '\n' ' ' < "$verr" | sed -E 's/[[:space:]]+/ /g')"
    reason_code="$(printf "%s" "$detail" | classify_reason)"
  else
    rm -f "$verr" >/dev/null 2>&1 || true
  fi

  # Bundle existence rule
  if [[ "$status" == "OK" && ! -f "$bundle" ]]; then
    status="QUARANTINE"
    reason_code="bundle_missing"
    detail="bundle missing: $(basename "$bundle")"
  fi

  if [[ "$status" == "OK" ]]; then
    echo "$rid | OK | - | - | - | -" >> "$REPORT"
    count_ok=$((count_ok+1))
    continue
  fi

  count_quarantine=$((count_quarantine+1))
  dest="$LEG_DIR/$reason_code/release_${rid}"
  moved_to="$dest"

  short_detail="$(echo "$detail" | cut -c1-180)"

  if [[ "$MODE" == "dry-run" ]]; then
    echo "$rid | QUARANTINE | $reason_code | $short_detail | $dest | -" >> "$REPORT"
    continue
  fi

  # Apply mode: move, but never abort the whole run
  mkdir -p "$dest" 2>/tmp/hygiene_mkdir_err.txt || {
    move_errors="mkdir_failed:$(tr '\n' ' ' < /tmp/hygiene_mkdir_err.txt | cut -c1-160)"
    echo "$rid | QUARANTINE | $reason_code | $short_detail | $dest | $move_errors" >> "$REPORT"
    count_errors=$((count_errors+1))
    continue
  }

  # Move each file; collect any errors
  errs=""
  for f in "$manifest" "$bundle" "$msig" "$bsig" "$verr"; do
    if [[ -f "$f" ]]; then
      if ! mv_one "$f" "$dest"; then
        emsg="$(tr '\n' ' ' < /tmp/hygiene_mv_err.txt | sed -E 's/[[:space:]]+/ /g' | cut -c1-160)"
        errs="${errs} mv_failed($(basename "$f")):${emsg};"
      fi
    fi
  done

  if [[ -n "$errs" ]]; then
    move_errors="$(echo "$errs" | cut -c1-220)"
    echo "$rid | QUARANTINE | $reason_code | $short_detail | $dest | $move_errors" >> "$REPORT"
    count_errors=$((count_errors+1))
    continue
  fi

  echo "$rid | QUARANTINE | $reason_code | $short_detail | $dest | -" >> "$REPORT"
  count_moved=$((count_moved+1))
done

{
  echo
  echo "SUMMARY"
  echo "total_manifests=$count_total"
  echo "ok_kept=$count_ok"
  echo "quarantined=$count_quarantine"
  echo "moved=$count_moved"
  echo "errors=$count_errors"
} >> "$REPORT"

cp -f "$REPORT" "$LATEST" >/dev/null 2>&1 || true

note "Wrote report: $REPORT"
note "Wrote latest: $LATEST"
note "Done. total=$count_total ok=$count_ok quarantined=$count_quarantine moved=$count_moved errors=$count_errors"
