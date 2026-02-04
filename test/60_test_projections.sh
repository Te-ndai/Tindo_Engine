#!/usr/bin/env bash
set -euo pipefail

# Ensure some events exist
runtime/bin/app_entry '{"command":"noop","args":{}}' >/dev/null
runtime/bin/app_entry '{"command":"does_not_exist","args":{}}' >/dev/null || true

# Rebuild
runtime/bin/rebuild_projections >/dev/null

OUT="runtime/state/projections/executions_summary.json"
[ -f "$OUT" ] || { echo "FAIL: projection not created" >&2; exit 1; }

# Basic checks
python3 -c "import json; d=json.load(open('$OUT')); assert d['projection']=='executions_summary'; assert d['total']>=2; print('PASS: projection shape ok, total=', d['total'])"

# Rebuildability check: delete projection and rebuild
rm -f "$OUT"
runtime/bin/rebuild_projections >/dev/null
[ -f "$OUT" ] || { echo "FAIL: projection not recreated" >&2; exit 1; }

echo "✅ projections rebuild test PASS"
