#!/usr/bin/env bash
set -euo pipefail

# Always run from the directory where this script lives (repo root)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# If patch0.sh is being used as a "runner", it should execute a target script if provided.
# Usage:
#   ./patch0.sh <script>
# or just run whatever content is inside patch0.sh (current behavior).

# If a target script is supplied, run it.
if [ "${1:-}" != "" ]; then
  exec bash "$1"
fi

# Otherwise: fall through to any embedded patch content below (if you keep using patch0 as a scratch runner).
