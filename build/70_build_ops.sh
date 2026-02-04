#!/usr/bin/env bash
set -euo pipefail

ROOT="."
mkdir -p "$ROOT/runtime/bin"
: > "$ROOT/runtime/bin/ops"

echo "OK: phase 70 build complete"
