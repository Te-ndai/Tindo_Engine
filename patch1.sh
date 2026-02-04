#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

die(){ echo "❌ $*" >&2; exit 1; }
ok(){ echo "✅ $*"; }

[ -f test/84_test_restore_replay.sh ] || die "missing test/84_test_restore_replay.sh"
[ -f test/83_test_release_bundle.sh ] || die "missing test/83_test_release_bundle.sh"

backup(){
  local f="$1"
  local b="${f}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -f "$f" "$b"
  ok "backup: $b"
}

backup test/84_test_restore_replay.sh

# 1) Normalize RELEASE_GLOB (safe)
if grep -q '^RELEASE_GLOB=' test/84_test_restore_replay.sh; then
  sed -i 's#^RELEASE_GLOB=".*"#RELEASE_GLOB="runtime/state/releases/release_*.tar.gz"#' test/84_test_restore_replay.sh
  ok "Phase 84: normalized RELEASE_GLOB"
fi

# 2) Remove stale comment block mentioning app_entry (keep the file honest)
# Delete lines that explicitly reference app_entry in narrative comments.
sed -i '/supports subcommands via app_entry/d' test/84_test_restore_replay.sh

# 3) Remove any functional app_entry wiring if still present
sed -i '/require_file "\$RESTORE_DIR\/runtime\/bin\/app_entry"/d' test/84_test_restore_replay.sh
sed -i '/chmod \+x "\$RESTORE_DIR\/runtime\/bin\/app_entry"/d' test/84_test_restore_replay.sh
sed -i '/^APP="\$RESTORE_DIR\/runtime\/bin\/app_entry"$/d' test/84_test_restore_replay.sh

# 4) Ensure runtime/bin is required
if ! grep -q 'require_dir "\$RESTORE_DIR/runtime/bin"' test/84_test_restore_replay.sh; then
  sed -i '0,/require_dir "\$RESTORE_DIR\/runtime"/s//require_dir "\$RESTORE_DIR\/runtime"\nrequire_dir "\$RESTORE_DIR\/runtime\/bin"/' test/84_test_restore_replay.sh
  ok "Phase 84: ensured require_dir runtime/bin"
fi

# 5) Replace "$APP ..." calls if any remain
sed -i 's/"\$APP"[[:space:]]\+logchain_verify[[:space:]]\+--root[[:space:]]\+"\$RESTORE_DIR\/runtime"/"\$LOGCHAIN_VERIFY" --root "\$RESTORE_DIR\/runtime"/' test/84_test_restore_replay.sh || true
sed -i 's/"\$APP"[[:space:]]\+rebuild_projections[[:space:]]\+--root[[:space:]]\+"\$RESTORE_DIR\/runtime"/"\$REBUILD_PROJECTIONS" --root "\$RESTORE_DIR\/runtime"/' test/84_test_restore_replay.sh || true
sed -i 's/"\$APP"[[:space:]]\+ops[[:space:]]\+report[[:space:]]\+--root[[:space:]]\+"\$RESTORE_DIR\/runtime"[[:space:]]\+--format[[:space:]]\+json/"\$OPS" report --root "\$RESTORE_DIR\/runtime" --format json/' test/84_test_restore_replay.sh || true

# 6) Inject bindings if missing (right before first logchain_verify run)
if ! grep -q 'LOGCHAIN_VERIFY="\$BIN/logchain_verify"' test/84_test_restore_replay.sh; then
  awk '
    BEGIN{inserted=0}
    {
      if(!inserted && $0 ~ /echo "Running: logchain_verify"/){
        print "BIN=\"$RESTORE_DIR/runtime/bin\""
        print ""
        print "LOGCHAIN_VERIFY=\"$BIN/logchain_verify\""
        print "REBUILD_PROJECTIONS=\"$BIN/rebuild_projections\""
        print "OPS=\"$BIN/ops\""
        print ""
        print "require_file \"$LOGCHAIN_VERIFY\""
        print "require_file \"$REBUILD_PROJECTIONS\""
        print "require_file \"$OPS\""
        print ""
        print "chmod +x \"$LOGCHAIN_VERIFY\" \"$REBUILD_PROJECTIONS\" \"$OPS\" || true"
        print ""
        inserted=1
      }
      print $0
    }
  ' test/84_test_restore_replay.sh > test/84_test_restore_replay.sh.tmp
  mv test/84_test_restore_replay.sh.tmp test/84_test_restore_replay.sh
  ok "Phase 84: injected command bindings"
else
  ok "Phase 84: command bindings already present"
fi

chmod +x test/84_test_restore_replay.sh

# Validation: only fail on functional app_entry usage
if grep -q 'runtime/bin/app_entry' test/84_test_restore_replay.sh; then
  die "Phase 84: still references runtime/bin/app_entry"
fi
if grep -q '^APP=' test/84_test_restore_replay.sh; then
  die "Phase 84: still defines APP"
fi
if grep -q '"\$APP"' test/84_test_restore_replay.sh; then
  die "Phase 84: still invokes \$APP"
fi

grep -q 'LOGCHAIN_VERIFY="\$BIN/logchain_verify"' test/84_test_restore_replay.sh || die "Phase 84: LOGCHAIN_VERIFY not set"
grep -q '"\$OPS" report' test/84_test_restore_replay.sh || die "Phase 84: ops report call not found"
ok "Phase 84: validation OK"

# --- Phase 83 hardening (same as before) ---
backup test/83_test_release_bundle.sh

if ! grep -q 'missing logchain_verify in bundle' test/83_test_release_bundle.sh; then
  awk '
    {
      if($0 ~ /echo "✅ Phase 83 TEST PASS"/){
        print ""
        print "# Operational release must include replay-critical commands"
        print "tar -tzf \"$bundle\" | grep -q '\''^runtime/bin/logchain_verify$'\'' || { echo \"FAIL: missing logchain_verify in bundle\"; exit 1; }"
        print "tar -tzf \"$bundle\" | grep -q '\''^runtime/bin/rebuild_projections$'\'' || { echo \"FAIL: missing rebuild_projections in bundle\"; exit 1; }"
        print "tar -tzf \"$bundle\" | grep -q '\''^runtime/bin/ops$'\'' || { echo \"FAIL: missing ops in bundle\"; exit 1; }"
        print ""
      }
      print $0
    }
  ' test/83_test_release_bundle.sh > test/83_test_release_bundle.sh.tmp
  mv test/83_test_release_bundle.sh.tmp test/83_test_release_bundle.sh
  ok "Phase 83: added operational asserts"
else
  ok "Phase 83: operational asserts already present"
fi

chmod +x test/83_test_release_bundle.sh

ok "Patch complete."
echo "Run:"
echo "  ./test/84_test_restore_replay.sh"
