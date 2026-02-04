#!/usr/bin/env bash
set -euo pipefail

ROOT="."

test -f "$ROOT/runtime/schema/projection_envelope_contract.json" || { echo "ERROR: envelope placeholder missing"; exit 1; }
test -f "$ROOT/runtime/schema/projection_payload_contracts.json" || { echo "ERROR: payload placeholder missing"; exit 1; }

# 1) Envelope contract: applies to all projections
cat > "$ROOT/runtime/schema/projection_envelope_contract.json" <<'JSON'
{
  "schema_version": 1,
  "required_fields": ["projection", "source", "total", "last_event_time_utc"],
  "field_types": {
    "projection": "string",
    "source": "string",
    "total": "int",
    "last_event_time_utc": "string"
  }
}
JSON

# 2) Payload contracts: per-projection requirements
cat > "$ROOT/runtime/schema/projection_payload_contracts.json" <<'JSON'
{
  "schema_version": 1,
  "contracts": {
    "executions_summary": {
      "required_fields": ["by_command", "by_status", "last_n"],
      "field_types": {
        "by_command": "object",
        "by_status": "object",
        "last_n": "list"
      },
      "last_n_item_required": ["event_type", "event_time_utc", "command", "status", "exit_code", "request_sha256", "response"]
    },
    "commands_summary": {
      "required_fields": ["by_command", "by_status"],
      "field_types": {
        "by_command": "object",
        "by_status": "object"
      }
    }
  }
}
JSON

# Keep old contract file around? No. Delete to prevent ambiguity.
rm -f "$ROOT/runtime/schema/projection_contract.json" || true

echo "OK: populated phase 64 split contracts"
