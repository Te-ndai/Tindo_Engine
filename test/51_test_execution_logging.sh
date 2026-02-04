#!/usr/bin/env bash
set -euo pipefail

LOG="runtime/state/logs/executions.jsonl"
rm -f "$LOG"

runtime/bin/app_entry '{"command":"noop","args":{}}' >/dev/null
runtime/bin/app_entry '{"command":"validate","args":{"command":"noop","args":{}}}' >/dev/null
runtime/bin/app_entry '{"command":"does_not_exist","args":{}}' >/dev/null || true

[ -f "$LOG" ] || { echo "FAIL: executions.jsonl not created" >&2; exit 1; }
lines="$(wc -l < "$LOG")"
[ "$lines" -ge 3 ] || { echo "FAIL: expected >=3 log lines, got $lines" >&2; exit 1; }

echo "PASS: execution log appended ($lines lines)"
echo "Sample:"
tail -n 2 "$LOG"
echo "✅ Phase 51 app_entry execution logging test PASS"