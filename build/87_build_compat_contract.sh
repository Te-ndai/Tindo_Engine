#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p test note build populate

touch test/87_test_compat_contract.sh
touch note/PHASE_87_COMPAT_CONTRACT.md
chmod +x test/87_test_compat_contract.sh

echo "OK: Phase 87 BUILD created placeholders:"
echo " - test/87_test_compat_contract.sh"
echo " - note/PHASE_87_COMPAT_CONTRACT.md"
