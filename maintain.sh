#!/usr/bin/env bash
set -euo pipefail
./patch102_hygiene.sh --dry-run
echo
echo "If the report looks good: ./patch102_hygiene.sh --apply"
