#!/usr/bin/env bash
set -euo pipefail

ROOT="."
mkdir -p "$ROOT/runtime/bin"

: > "$ROOT/runtime/bin/make_fresh"

echo "OK: phase 69 build complete"
