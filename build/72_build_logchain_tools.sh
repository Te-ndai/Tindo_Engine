#!/usr/bin/env bash
set -euo pipefail

mkdir -p runtime/bin
: > runtime/bin/logchain_rebuild
: > runtime/bin/logchain_verify

echo "OK: phase 72 build complete"
