#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
ok(){ echo "OK: $*"; }

[ -d runtime ] || die "missing ./runtime"
[ -d test ] || die "missing ./test"
mkdir -p .tmp

backup_dir=".tmp/patch19_backup_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir"

backup(){
  local f="$1"
  if [ -f "$f" ]; then
    mkdir -p "$backup_dir/$(dirname "$f")"
    cp -a "$f" "$backup_dir/$f"
    ok "backup: $f -> $backup_dir/$f"
  fi
}

backup test/90_test_all_deterministic.sh
if [ -f runtime/bin/validate_manifest.sh ]; then
  backup runtime/bin/validate_manifest.sh
fi

# 1) Kill the obsolete validate_manifest.sh (or at least fix CRLF + warn)
if [ -f runtime/bin/validate_manifest.sh ]; then
  # Normalize CRLF so it doesn't error if someone runs it
  sed -i 's/\r$//' runtime/bin/validate_manifest.sh || true
  chmod +x runtime/bin/validate_manifest.sh || true
  ok "normalized CRLF on runtime/bin/validate_manifest.sh (obsolete; use runtime/bin/validate_manifest)"
fi

# 2) Clean Phase 90: remove any stray pasted instruction lines that start with "./runtime/bin/validate_manifest "
# Also normalize CRLF just in case.
sed -i 's/\r$//' test/90_test_all_deterministic.sh

# Delete lines that are exactly (or start with) the printed instruction you saw
# We remove any line that begins with optional spaces then ./runtime/bin/validate_manifest then a space then runtime/state/releases/release_<RID>.json
sed -i '/^[[:space:]]*\.\/runtime\/bin\/validate_manifest[[:space:]]\+runtime\/state\/releases\/release_<RID>\.json/d' test/90_test_all_deterministic.sh

# Additionally remove any accidental “example command” line that begins with "./runtime/bin/validate_manifest runtime/state/releases/release_"
# (These do NOT belong in a test harness.)
sed -i '/^[[:space:]]*\.\/runtime\/bin\/validate_manifest[[:space:]]\+runtime\/state\/releases\/release_/d' test/90_test_all_deterministic.sh

ok "cleaned test/90_test_all_deterministic.sh stray instruction lines"

echo "OK: patch19 complete"
echo "Backups in: $backup_dir"
echo
echo "Now run:"
echo "  ./test/90_test_all_deterministic.sh"
echo "And use:"
echo "  ./runtime/bin/validate_manifest <manifest.json> --release-id <RID>"
