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

# Patch rebuild_projections invocation to capture output on failure.
python3 - <<'PY'
import pathlib, re

p = pathlib.Path("test/84_test_restore_replay.sh")
s = p.read_text(encoding="utf-8")

# Idempotency: if debug block already present, do nothing.
if "REBUILD_OUT=" in s and "---- rebuild_projections --help ----" in s:
    print("ALREADY")
    raise SystemExit(0)

# Replace the single-line rebuild call with a debug wrapper.
pattern = re.compile(
    r'echo "Running: rebuild_projections"\s*\n'
    r'"\$REBUILD_PROJECTIONS" --root "\$RESTORE_DIR/runtime" \|\| die "rebuild_projections failed"\s*\n'
)

replacement = (
    'echo "Running: rebuild_projections"\n'
    'REBUILD_OUT="$RESTORE_DIR/_rebuild_projections.out"\n'
    'REBUILD_ERR="$RESTORE_DIR/_rebuild_projections.err"\n'
    'set +e\n'
    '"$REBUILD_PROJECTIONS" --root "$RESTORE_DIR/runtime" >"$REBUILD_OUT" 2>"$REBUILD_ERR"\n'
    'rc=$?\n'
    'set -e\n'
    'if [ "$rc" -ne 0 ]; then\n'
    '  echo "❌ rebuild_projections failed (exit=$rc)"\n'
    '  echo "---- stdout ----"\n'
    '  sed -n \'1,200p\' "$REBUILD_OUT" || true\n'
    '  echo "---- stderr ----"\n'
    '  sed -n \'1,200p\' "$REBUILD_ERR" || true\n'
    '  echo "---- rebuild_projections --help ----"\n'
    '  "$REBUILD_PROJECTIONS" --help 2>&1 | sed -n \'1,120p\' || true\n'
    '  echo "---- restore tree (first 120) ----"\n'
    '  (cd "$RESTORE_DIR" && find . -maxdepth 4 -type f | sed -n \'1,120p\') || true\n'
    '  exit 1\n'
    'fi\n'
)

s2, n = pattern.subn(replacement, s, count=1)
if n != 1:
    raise SystemExit("NO_MATCH")
p.write_text(s2, encoding="utf-8")
print("PATCHED")
PY

chmod +x test/84_test_restore_replay.sh
ok "Phase 84: added rebuild_projections debug capture"

echo "OK. Now run:"
echo "  ./test/84_test_restore_replay.sh"
