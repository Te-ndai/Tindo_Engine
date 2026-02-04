#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

./test/86_test_bundle_sha.sh
