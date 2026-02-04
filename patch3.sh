#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

die(){ echo "❌ $*" >&2; exit 1; }
ok(){ echo "✅ $*"; }

[ -f test/84_test_restore_replay.sh ] || die "missing test/84_test_restore_replay.sh"

backup(){
  local f="$1"
  local b="${f}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -f "$f" "$b"
  ok "backup: $b"
}

backup test/84_test_restore_replay.sh

python3 - <<'PY'
import pathlib, re
p = pathlib.Path("test/84_test_restore_replay.sh")
s = p.read_text(encoding="utf-8")

# Replace the current debug wrapper block for rebuild_projections with a stronger one.
# We detect it by the header "Running: rebuild_projections" and the variables REBUILD_OUT/ERR.
pat = re.compile(
    r'echo "Running: rebuild_projections"\n'
    r'REBUILD_OUT="\$RESTORE_DIR/_rebuild_projections\.out"\n'
    r'REBUILD_ERR="\$RESTORE_DIR/_rebuild_projections\.err"\n'
    r'set \+e\n'
    r'.*?'
    r'fi\n',
    re.DOTALL
)

rep = (
    'echo "Running: rebuild_projections"\n'
    'REBUILD_OUT="$RESTORE_DIR/_rebuild_projections.out"\n'
    'REBUILD_ERR="$RESTORE_DIR/_rebuild_projections.err"\n'
    'REBUILD_XTRACE="$RESTORE_DIR/_rebuild_projections.xtrace"\n'
    '\n'
    '# Try mode A: explicit --root (preferred)\n'
    'set +e\n'
    '(cd "$RESTORE_DIR" && "$REBUILD_PROJECTIONS" --root "$RESTORE_DIR/runtime" >"$REBUILD_OUT" 2>"$REBUILD_ERR")\n'
    'rc=$?\n'
    'set -e\n'
    '\n'
    '# If mode A fails, try mode B: cwd-based (no args)\n'
    'if [ "$rc" -ne 0 ]; then\n'
    '  set +e\n'
    '  (cd "$RESTORE_DIR" && "$REBUILD_PROJECTIONS" >"$REBUILD_OUT" 2>"$REBUILD_ERR")\n'
    '  rc=$?\n'
    '  set -e\n'
    'fi\n'
    '\n'
    '# If still failing and no stderr, run xtrace to force visibility\n'
    'if [ "$rc" -ne 0 ]; then\n'
    '  if [ ! -s "$REBUILD_ERR" ] && [ ! -s "$REBUILD_OUT" ]; then\n'
    '    set +e\n'
    '    (cd "$RESTORE_DIR" && bash -x "$REBUILD_PROJECTIONS" --root "$RESTORE_DIR/runtime" ) >"$REBUILD_XTRACE" 2>&1\n'
    '    set -e\n'
    '  fi\n'
    '  echo "❌ rebuild_projections failed (exit=$rc)"\n'
    '  echo "---- stdout ----"\n'
    '  sed -n \'1,200p\' "$REBUILD_OUT" || true\n'
    '  echo "---- stderr ----"\n'
    '  sed -n \'1,200p\' "$REBUILD_ERR" || true\n'
    '  echo "---- xtrace (first 200) ----"\n'
    '  sed -n \'1,200p\' "$REBUILD_XTRACE" || true\n'
    '  echo "---- rebuild_projections file header ----"\n'
    '  sed -n \'1,60p\' "$REBUILD_PROJECTIONS" || true\n'
    '  exit 1\n'
    'fi\n'
)

s2, n = pat.subn(rep, s, count=1)
if n != 1:
    raise SystemExit("NO_MATCH: rebuild wrapper block not found (file changed?)")
p.write_text(s2, encoding="utf-8")
print("PATCHED")
PY

chmod +x test/84_test_restore_replay.sh
ok "Phase 84: upgraded rebuild_projections execution (try --root, then no-args, then xtrace)"

echo "Now run:"
echo "  ./test/84_test_restore_replay.sh"
