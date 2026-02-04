#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p test note build populate

touch test/86_test_bundle_sha.sh
touch note/PHASE_86_BUNDLE_SHA.md

chmod +x test/86_test_bundle_sha.sh

echo "OK: Phase 86 BUILD created placeholders:"
echo " - test/86_test_bundle_sha.sh"
echo " - note/PHASE_86_BUNDLE_SHA.md"
