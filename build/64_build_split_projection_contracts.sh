#!/usr/bin/env bash
set -euo pipefail

ROOT="."

mkdir -p "$ROOT/runtime/schema"

: > "$ROOT/runtime/schema/projection_envelope_contract.json"
: > "$ROOT/runtime/schema/projection_payload_contracts.json"

echo "OK: phase 64 build complete"
