#!/usr/bin/env bash
# promote/40_promote_stage_to_runtime.sh
# Phase 4 PROMOTE: atomic promotion of staged runtime into ROOT/runtime
# with rollback snapshot and manifest logging.

set -euo pipefail

STAGE="logs/env/stage_build"
STAGE_RUNTIME="$STAGE/runtime"
STAGE_LOGS="$STAGE/logs"

[ -d "$STAGE_RUNTIME" ] || { echo "ERROR: missing stage runtime at $STAGE_RUNTIME" >&2; exit 1; }
[ -f "$STAGE_LOGS/test.results.json" ] || { echo "ERROR: missing stage test results at $STAGE_LOGS/test.results.json" >&2; exit 2; }

# Require stage PASS
grep -qF '"status": "PASS"' "$STAGE_LOGS/test.results.json" || { echo "ERROR: stage tests not PASS" >&2; exit 3; }

mkdir -p logs/env

ts="$(date -u +%Y%m%d_%H%M%S)"
ROLLBACK="logs/env/rollback_runtime_${ts}"
mkdir -p "$ROLLBACK"

# 1) Snapshot current runtime (if exists)
if [ -d "runtime" ]; then
  cp -a "runtime" "$ROLLBACK/runtime"
  echo "Snapshot saved to: $ROLLBACK/runtime"
else
  echo "No existing runtime/ to snapshot."
fi

# 2) Atomic replace:
#    - move current runtime aside
#    - copy stage runtime into place via temp dir then rename
TMP="logs/env/.promote_tmp_runtime_${ts}"
rm -rf "$TMP"
cp -a "$STAGE_RUNTIME" "$TMP"

# Preserve executable bit on app_entry just in case
chmod +x "$TMP/bin/app_entry" 2>/dev/null || true

# Move old runtime aside (optional)
OLD="logs/env/old_runtime_${ts}"
if [ -d "runtime" ]; then
  mv "runtime" "$OLD"
  echo "Moved old runtime to: $OLD"
fi

# Promote temp into runtime (atomic rename)
mv "$TMP" "runtime"
echo "Promoted staged runtime into ROOT/runtime"

# 3) Write logs/runtime.manifest.json
ts_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
dirs_json="$(find runtime -type d -print | sort | awk 'BEGIN{print "["}{gsub(/\\/,"\\\\");gsub(/"/,"\\\"");printf "%s\"%s\"", (NR==1?"":","), $0}END{print "]"}')"
files_json="$(find runtime -type f -print | sort | awk 'BEGIN{print "["}{gsub(/\\/,"\\\\");gsub(/"/,"\\\"");printf "%s\"%s\"", (NR==1?"":","), $0}END{print "]"}')"

cat > logs/runtime.manifest.json <<EOF
{
  "phase": "4",
  "action": "PROMOTE",
  "timestamp_utc": "$ts_iso",
  "source_stage": "$STAGE_RUNTIME",
  "rollback_snapshot": "$ROLLBACK/runtime",
  "previous_runtime_moved_to": "$( [ -d "$OLD" ] && echo "$OLD" || echo "" )",
  "dirs": $dirs_json,
  "files": $files_json
}
EOF

echo "Wrote: logs/runtime.manifest.json"
echo "✅ Phase 4 PROMOTE complete."
