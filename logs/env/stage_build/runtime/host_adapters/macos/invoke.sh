#!/usr/bin/env bash
set -euo pipefail
# Pure translator: invoke canonical entrypoint only.
exec ../../bin/app_entry "$@"
