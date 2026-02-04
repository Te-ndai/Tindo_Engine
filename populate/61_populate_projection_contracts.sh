#!/usr/bin/env bash
set -euo pipefail

ROOT="."

# Guard: files must already exist from BUILD
test -f "$ROOT/runtime/schema/projection_registry.json" || { echo "ERROR: registry placeholder missing"; exit 1; }
test -f "$ROOT/runtime/schema/projection_contract.json" || { echo "ERROR: contract placeholder missing"; exit 1; }

# 1) Projection output contract (minimal but strict)
cat > "$ROOT/runtime/schema/projection_contract.json" <<'JSON'
{
  "schema_version": 1,
  "required_fields": ["projection", "source", "total", "last_event_time_utc", "last_n"],
  "field_types": {
    "projection": "string",
    "source": "string",
    "total": "int",
    "last_event_time_utc": "string",
    "last_n": "list"
  },
  "last_n_item_required": ["event_type", "event_time_utc", "command", "status", "exit_code", "request_sha256", "response"]
}
JSON

# 2) Projection registry (declares authoritative set)
# Add more projections here later; this is the “inventory”.
cat > "$ROOT/runtime/schema/projection_registry.json" <<'JSON'
{
  "schema_version": 1,
  "projections": [
    {
      "name": "executions_summary",
      "source_log": "runtime/state/logs/executions.jsonl",
      "output": "runtime/state/projections/executions_summary.json",
      "enabled": true
    }
  ]
}
JSON

echo "OK: populated projection registry + contract"

# NOTE: If your factory requires logs/populate.files.json + logs/populate.hashes.json,
# keep using your established mechanism. Don’t invent a second logging standard here.
