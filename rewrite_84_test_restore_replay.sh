#!/usr/bin/env bash
# Rewrite Phase 84 test cleanly (replace corrupted file)
set -euo pipefail
cd "$(dirname "$0")/.."

die(){ echo "❌ $*" >&2; exit 1; }
ok(){ echo "✅ $*"; }

OUT="test/84_test_restore_replay.sh"
[ -d test ] || die "missing ./test dir"

# Backup existing (even if corrupted)
if [ -f "$OUT" ]; then
  B="${OUT}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -f "$OUT" "$B"
  ok "backup: $B"
fi

cat > "$OUT" <<'SH'
#!/usr/bin/env bash
# test/84_test_restore_replay.sh
# Phase 84 TEST: Restore + replay proof for release bundle (clean rewrite)
set -euo pipefail

die(){ echo "❌ $*" >&2; exit 1; }
require_file(){ [ -f "$1" ] || die "missing file: $1"; }
require_dir(){ [ -d "$1" ] || die "missing dir: $1"; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RELEASE_GLOB="runtime/state/releases/release_*.tar.gz"
LATEST_TARBALL="$(ls -1t $RELEASE_GLOB 2>/dev/null | head -n 1 || true)"
[ -n "$LATEST_TARBALL" ] || die "no release tarball found at: $RELEASE_GLOB"

echo "Using release tarball: $LATEST_TARBALL"

RESTORE_DIR="$(mktemp -d)"
cleanup(){ rm -rf "$RESTORE_DIR"; }
trap cleanup EXIT

tar -xzf "$LATEST_TARBALL" -C "$RESTORE_DIR"

# Find manifest json inside restored bundle
MANIFEST_PATH="$(find "$RESTORE_DIR" -type f -name 'release_*.json' 2>/dev/null | sort | tail -n 1 || true)"
[ -n "$MANIFEST_PATH" ] || die "could not find release_*.json manifest in restored bundle"

echo "Found manifest: $MANIFEST_PATH"

# Required restored structure
require_dir "$RESTORE_DIR/runtime"
require_dir "$RESTORE_DIR/runtime/bin"
require_dir "$RESTORE_DIR/runtime/state"

LOGCHAIN_VERIFY="$RESTORE_DIR/runtime/bin/logchain_verify"
REBUILD_PROJECTIONS="$RESTORE_DIR/runtime/bin/rebuild_projections"
OPS="$RESTORE_DIR/runtime/bin/ops"

require_file "$LOGCHAIN_VERIFY"
require_file "$REBUILD_PROJECTIONS"
require_file "$OPS"
chmod +x "$LOGCHAIN_VERIFY" "$REBUILD_PROJECTIONS" "$OPS" || true

# Read expectations (optional)
python3 - <<'PY' "$MANIFEST_PATH" > "$RESTORE_DIR/_expected.json"
import json, sys
m=json.load(open(sys.argv[1],"r",encoding="utf-8"))
def pick(*keys):
    cur=m
    for k in keys:
        if isinstance(cur, dict) and k in cur:
            cur=cur[k]
        else:
            return None
    return cur

out={
  "expected_event_count": (
      m.get("expected_event_count")
      or pick("expectations","event_count")
      or pick("runtime","state","logs","event_count")
  ),
  "expected_last_event_time_utc": (
      m.get("expected_last_event_time_utc")
      or pick("expectations","last_event_time_utc")
      or pick("runtime","state","logs","last_event_time_utc")
  ),
}
print(json.dumps(out))
PY

EXPECTED_EVENT_COUNT="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); v=d.get("expected_event_count"); print("" if v is None else v)' "$RESTORE_DIR/_expected.json")"
EXPECTED_LAST_EVENT_TIME="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); v=d.get("expected_last_event_time_utc"); print("" if v is None else v)' "$RESTORE_DIR/_expected.json")"

echo "Expected event count: ${EXPECTED_EVENT_COUNT:-<unspecified>}"
echo "Expected last_event_time_utc: ${EXPECTED_LAST_EVENT_TIME:-<unspecified>}"

# 1) logchain_verify (cwd-sensitive scripts: run from restored root)
echo "Running: logchain_verify"
(cd "$RESTORE_DIR" && "$LOGCHAIN_VERIFY" --root "$RESTORE_DIR/runtime") || die "logchain_verify failed"

# 2) rebuild_projections (supports optional target; run full rebuild by default)
echo "Running: rebuild_projections"
set +e
(cd "$RESTORE_DIR" && "$REBUILD_PROJECTIONS" --root "$RESTORE_DIR/runtime" >/dev/null 2>&1)
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  # fallback: no args (some wrappers are cwd-only)
  set +e
  (cd "$RESTORE_DIR" && "$REBUILD_PROJECTIONS" >/dev/null 2>&1)
  rc=$?
  set -e
fi
[ "$rc" -eq 0 ] || die "rebuild_projections failed"

# 3) ops report (writes files; does NOT emit JSON)
echo "Running: ops report"
(cd "$RESTORE_DIR" && "$OPS" report >/dev/null 2>&1) || die "ops report failed"

# ---- derive actuals from append-only chain ----
CHAIN_PATH="$RESTORE_DIR/runtime/state/logs/executions.chain.jsonl"
require_file "$CHAIN_PATH"

ACTUAL_EVENT_COUNT="$(wc -l < "$CHAIN_PATH" | tr -d ' ')"

ACTUAL_LAST_EVENT_TIME="$(python3 - <<'PY' "$CHAIN_PATH"
import json, sys
path=sys.argv[1]
last=""
with open(path,"r",encoding="utf-8",errors="replace") as f:
    for line in f:
        line=line.strip()
        if line: last=line
if not last:
    print("")
    raise SystemExit(0)
try:
    obj=json.loads(last)
except Exception:
    print("")
    raise SystemExit(0)
for k in ("event_time_utc","event_time","timestamp_utc","time_utc"):
    v=obj.get(k)
    if isinstance(v,str) and v:
        print(v)
        raise SystemExit(0)
print("")
PY
)"

echo "Actual event count: ${ACTUAL_EVENT_COUNT:-<unknown>}"
echo "Actual last_event_time_utc: ${ACTUAL_LAST_EVENT_TIME:-<unknown>}"

# If expected values exist, enforce equality.
if [ -n "${EXPECTED_EVENT_COUNT:-}" ]; then
  [ -n "${ACTUAL_EVENT_COUNT:-}" ] || die "manifest specifies expected_event_count but actual event_count is empty"
  [ "$ACTUAL_EVENT_COUNT" = "$EXPECTED_EVENT_COUNT" ] || die "event_count mismatch: expected=$EXPECTED_EVENT_COUNT actual=$ACTUAL_EVENT_COUNT"
fi

if [ -n "${EXPECTED_LAST_EVENT_TIME:-}" ]; then
  [ -n "${ACTUAL_LAST_EVENT_TIME:-}" ] || die "manifest specifies expected_last_event_time_utc but actual last_event_time_utc is empty"
  [ "$ACTUAL_LAST_EVENT_TIME" = "$EXPECTED_LAST_EVENT_TIME" ] || die "last_event_time_utc mismatch: expected=$EXPECTED_LAST_EVENT_TIME actual=$ACTUAL_LAST_EVENT_TIME"
fi

# Minimal operational assertions
PROJ_DIR="$RESTORE_DIR/runtime/state/projections"
require_dir "$PROJ_DIR"
[ "$(ls -A "$PROJ_DIR" | wc -l | tr -d ' ')" -gt 0 ] || die "projections are empty after rebuild"

echo "✅ Phase 84 TEST PASS (restore + replay proof)"
SH

chmod +x "$OUT"
ok "rewrote: $OUT"
echo "Run:"
echo "  ./test/84_test_restore_replay.sh"
