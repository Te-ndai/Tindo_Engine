#!/usr/bin/env bash
# populate/84_populate_restore_replay.sh
# Phase 84 POPULATE: write inert content into files created in BUILD.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Guard: files must already exist (created in BUILD)
[ -f test/84_test_restore_replay.sh ] || { echo "ERROR: missing test/84_test_restore_replay.sh (run build first)"; exit 1; }
[ -f note/PHASE_84_RESTORE_REPLAY.md ] || { echo "ERROR: missing note/PHASE_84_RESTORE_REPLAY.md (run build first)"; exit 1; }

cat > note/PHASE_84_RESTORE_REPLAY.md << 'EOF'
# Phase 84 — Restore + Replay Proof

Goal:
- A "release" is not archival unless it can be restored and replayed in a clean directory.

Restore + Replay proof must:
1) unpack a release bundle into a clean temp dir
2) run logchain_verify
3) run rebuild_projections
4) run ops report
5) assert results match manifest expectations:
   - counts (at least: logchain events)
   - last_event_time_utc (or equivalent)
   - integrity verification pass

Non-negotiables:
- test is read-only with respect to repository artifacts
- temp restore dir is isolated and deleted
- no absolute paths
- fail-fast
EOF

cat > test/84_test_restore_replay.sh << 'EOF'
#!/usr/bin/env bash
# test/84_test_restore_replay.sh
# Phase 84 TEST: Restore + replay proof for release bundle
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# ---------- helpers ----------
die() { echo "❌ $*" 1>&2; exit 1; }

require_file() { [ -f "$1" ] || die "missing file: $1"; }
require_dir() { [ -d "$1" ] || die "missing dir: $1"; }

# Locate the newest release bundle.
# Expected: releases/*.tar.gz and a corresponding manifest json alongside or inside.
# If your Phase 83 wrote a different location, adjust RELEASE_GLOB only.
RELEASE_GLOB="releases/*.tar.gz"

# shellcheck disable=SC2086
LATEST_TARBALL="$(ls -1t $RELEASE_GLOB 2>/dev/null | head -n 1 || true)"
[ -n "$LATEST_TARBALL" ] || die "no release tarball found at: $RELEASE_GLOB"

echo "Using release tarball: $LATEST_TARBALL"

# Create clean restore dir
RESTORE_DIR="$(mktemp -d)"
cleanup() { rm -rf "$RESTORE_DIR"; }
trap cleanup EXIT

# Unpack
tar -xzf "$LATEST_TARBALL" -C "$RESTORE_DIR"

# Heuristic: bundle root should contain runtime/ and a manifest json.
# Try common names.
MANIFEST_PATH=""
for cand in \
  "$RESTORE_DIR/release.manifest.json" \
  "$RESTORE_DIR/manifest.json" \
  "$RESTORE_DIR/runtime.manifest.json" \
  "$RESTORE_DIR/logs/release.manifest.json" \
  "$RESTORE_DIR/logs/runtime.manifest.json"
do
  if [ -f "$cand" ]; then MANIFEST_PATH="$cand"; break; fi
done

[ -n "$MANIFEST_PATH" ] || die "could not find manifest json in restored bundle"

echo "Found manifest: $MANIFEST_PATH"

# Must contain runtime/
require_dir "$RESTORE_DIR/runtime"
require_file "$RESTORE_DIR/runtime/bin/app_entry"

# Make entrypoint executable just in case tar preserved perms poorly
chmod +x "$RESTORE_DIR/runtime/bin/app_entry" || true

# ---------- read expectations from manifest ----------
# We only assert what we can robustly find. This avoids brittle coupling.
# Expected fields (recommended):
# - expected_event_count
# - expected_last_event_time_utc
# If absent, we assert integrity + that replay produces non-empty projections/reports.

python3 - <<'PY' "$MANIFEST_PATH" > "$RESTORE_DIR/_expected.json"
import json, sys
p = sys.argv[1]
m = json.load(open(p, "r", encoding="utf-8"))

def pick(*keys):
    cur = m
    for k in keys:
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            return None
    return cur

out = {
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

EXPECTED_EVENT_COUNT="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("" if d.get("expected_event_count") is None else d["expected_event_count"])' "$RESTORE_DIR/_expected.json")"
EXPECTED_LAST_EVENT_TIME="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("" if d.get("expected_last_event_time_utc") is None else d["expected_last_event_time_utc"])' "$RESTORE_DIR/_expected.json")"

echo "Expected event count: ${EXPECTED_EVENT_COUNT:-<unspecified>}"
echo "Expected last_event_time_utc: ${EXPECTED_LAST_EVENT_TIME:-<unspecified>}"

# ---------- run restore verification + replay ----------
# We assume your runtime supports subcommands via app_entry.
# If your runtime uses different verbs, rename them here ONLY.
APP="$RESTORE_DIR/runtime/bin/app_entry"

# 1) logchain_verify
echo "Running: logchain_verify"
"$APP" logchain_verify --root "$RESTORE_DIR/runtime" || die "logchain_verify failed"

# 2) rebuild_projections
echo "Running: rebuild_projections"
"$APP" rebuild_projections --root "$RESTORE_DIR/runtime" || die "rebuild_projections failed"

# 3) ops report
echo "Running: ops report"
OPS_JSON="$RESTORE_DIR/_ops_report.json"
"$APP" ops report --root "$RESTORE_DIR/runtime" --format json > "$OPS_JSON" || die "ops report failed"
[ -s "$OPS_JSON" ] || die "ops report produced empty output"

# ---------- assert results ----------
# Parse ops report for actuals. We look for obvious keys:
# - event_count
# - last_event_time_utc
python3 - <<'PY' "$OPS_JSON" > "$RESTORE_DIR/_actual.json"
import json, sys

o = json.load(open(sys.argv[1], "r", encoding="utf-8"))

def find_key(obj, targets):
    if isinstance(obj, dict):
        for k,v in obj.items():
            if k in targets:
                return v
        for v in obj.values():
            r = find_key(v, targets)
            if r is not None: return r
    elif isinstance(obj, list):
        for it in obj:
            r = find_key(it, targets)
            if r is not None: return r
    return None

out = {
  "event_count": find_key(o, {"event_count","events","log_event_count"}),
  "last_event_time_utc": find_key(o, {"last_event_time_utc","last_event_utc","last_event_time"}),
}
print(json.dumps(out))
PY

ACTUAL_EVENT_COUNT="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("" if d.get("event_count") is None else d["event_count"])' "$RESTORE_DIR/_actual.json")"
ACTUAL_LAST_EVENT_TIME="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("" if d.get("last_event_time_utc") is None else d["last_event_time_utc"])' "$RESTORE_DIR/_actual.json")"

echo "Actual event count: ${ACTUAL_EVENT_COUNT:-<unknown>}"
echo "Actual last_event_time_utc: ${ACTUAL_LAST_EVENT_TIME:-<unknown>}"

# If expected values exist, enforce equality.
if [ -n "${EXPECTED_EVENT_COUNT:-}" ]; then
  [ -n "${ACTUAL_EVENT_COUNT:-}" ] || die "manifest specifies expected_event_count but ops report did not provide event_count"
  [ "$ACTUAL_EVENT_COUNT" = "$EXPECTED_EVENT_COUNT" ] || die "event_count mismatch: expected=$EXPECTED_EVENT_COUNT actual=$ACTUAL_EVENT_COUNT"
fi

if [ -n "${EXPECTED_LAST_EVENT_TIME:-}" ]; then
  [ -n "${ACTUAL_LAST_EVENT_TIME:-}" ] || die "manifest specifies expected_last_event_time_utc but ops report did not provide last_event_time_utc"
  [ "$ACTUAL_LAST_EVENT_TIME" = "$EXPECTED_LAST_EVENT_TIME" ] || die "last_event_time_utc mismatch: expected=$EXPECTED_LAST_EVENT_TIME actual=$ACTUAL_LAST_EVENT_TIME"
fi

# Minimal operational assertions (even if manifest doesn't specify counts):
# Projections directory should exist and be non-empty after rebuild.
PROJ_DIR="$RESTORE_DIR/runtime/state/projections"
require_dir "$PROJ_DIR"
[ "$(ls -A "$PROJ_DIR" | wc -l | tr -d ' ')" -gt 0 ] || die "projections are empty after rebuild"

echo "✅ Phase 84 TEST PASS (restore + replay proof)"
EOF

chmod +x test/84_test_restore_replay.sh

echo "OK: Phase 84 POPULATE wrote:"
echo " - note/PHASE_84_RESTORE_REPLAY.md"
echo " - test/84_test_restore_replay.sh"
