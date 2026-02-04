#!/usr/bin/env bash
set -euo pipefail

# BUILD: create empty placeholders only
# Relative paths only (enforced by repo policy)

ROOT="."
test -d "$ROOT/runtime/schema" || { echo "ERROR: runtime/schema missing"; exit 1; }

mkdir -p "$ROOT/runtime/schema"

: > "$ROOT/runtime/schema/projection_registry.json"
: > "$ROOT/runtime/schema/projection_contract.json"

echo "OK: created empty projection schema placeholders"

# Optional: log build manifest (if you have a standard logger already)
# (If not, keep this phase pure and let your existing build harness log it.)
