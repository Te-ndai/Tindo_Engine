#!/usr/bin/env bash
set -euo pipefail
if [ -f runtime/state/keys/release_priv.pem ]; then
  echo "FAIL: private key present in repo tree: runtime/state/keys/release_priv.pem" >&2
  exit 1
fi
echo "✅ Phase 105 TEST PASS (no private key in repo tree)"
