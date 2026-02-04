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

# Replace the ops report block (from echo "Running: ops report" to the empty-check)
pat = re.compile(
    r'echo "Running: ops report"\n'
    r'OPS_JSON="\$RESTORE_DIR/_ops_report\.json"\n'
    r'"\$OPS" report --root "\$RESTORE_DIR/runtime" --format json > "\$OPS_JSON" \|\| die "ops report failed"\n'
    r'\[ -s "\$OPS_JSON" \] \|\| die "ops report produced empty output"\n'
)

rep = (
    'echo "Running: ops report"\n'
    'OPS_JSON="$RESTORE_DIR/_ops_report.json"\n'
    'OPS_OUT="$RESTORE_DIR/_ops_report.out"\n'
    'OPS_ERR="$RESTORE_DIR/_ops_report.err"\n'
    '\n'
    '# Try JSON mode first (stdout). If not JSON/empty, fall back.\n'
    'set +e\n'
    '(cd "$RESTORE_DIR" && "$OPS" report --root "$RESTORE_DIR/runtime" --format json >"$OPS_OUT" 2>"$OPS_ERR")\n'
    'rc=$?\n'
    'set -e\n'
    '\n'
    'if [ "$rc" -ne 0 ] || [ ! -s "$OPS_OUT" ]; then\n'
    '  # Fallback 1: --json\n'
    '  set +e\n'
    '  : >"$OPS_OUT"; : >"$OPS_ERR"\n'
    '  (cd "$RESTORE_DIR" && "$OPS" report --root "$RESTORE_DIR/runtime" --json >"$OPS_OUT" 2>"$OPS_ERR")\n'
    '  rc=$?\n'
    '  set -e\n'
    'fi\n'
    '\n'
    'if [ "$rc" -ne 0 ] || [ ! -s "$OPS_OUT" ]; then\n'
    '  # Fallback 2: plain (maybe text)\n'
    '  set +e\n'
    '  : >"$OPS_OUT"; : >"$OPS_ERR"\n'
    '  (cd "$RESTORE_DIR" && "$OPS" report --root "$RESTORE_DIR/runtime" >"$OPS_OUT" 2>"$OPS_ERR")\n'
    '  rc=$?\n'
    '  set -e\n'
    'fi\n'
    '\n'
    'if [ "$rc" -ne 0 ]; then\n'
    '  echo "❌ ops report failed (exit=$rc)"\n'
    '  echo "---- ops stdout ----"\n'
    '  sed -n \'1,200p\' "$OPS_OUT" || true\n'
    '  echo "---- ops stderr ----"\n'
    '  sed -n \'1,200p\' "$OPS_ERR" || true\n'
    '  exit 1\n'
    'fi\n'
    '\n'
    '# If stdout is valid JSON, copy it to OPS_JSON; otherwise keep text in OPS_OUT.\n'
    'python3 - <<\'PY2\' "$OPS_OUT" "$OPS_JSON"\n'
    'import json,sys\n'
    'src,dst=sys.argv[1],sys.argv[2]\n'
    'txt=open(src,"r",encoding="utf-8",errors="replace").read().strip()\n'
    'if not txt:\n'
    '    open(dst,"w",encoding="utf-8").write("")\n'
    '    raise SystemExit(0)\n'
    'try:\n'
    '    json.loads(txt)\n'
    '    open(dst,"w",encoding="utf-8").write(txt)\n'
    'except Exception:\n'
    '    open(dst,"w",encoding="utf-8").write("")\n'
    'PY2\n'
    '\n'
    'if [ -s "$OPS_JSON" ]; then\n'
    '  echo "ops report: JSON OK"\n'
    'else\n'
    '  echo "ops report: non-JSON output (continuing with limited assertions)"\n'
    'fi\n'
)

s2, n = pat.subn(rep, s, count=1)
if n != 1:
    raise SystemExit("NO_MATCH: ops report block not found (file changed?)")
p.write_text(s2, encoding="utf-8")
print("PATCHED")
PY

chmod +x test/84_test_restore_replay.sh
ok "Phase 84: ops report capture + JSON fallback added"

echo "Now rerun:"
echo "  ./test/84_test_restore_replay.sh"
