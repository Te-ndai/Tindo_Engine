#!/usr/bin/env bash
set -euo pipefail

f="test/02_test.sh"
[ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }

# Replace the two grep lines inside the Phase 0.5 block with fixed-string checks.
# We search and replace only those specific lines.

# 1) Replace contract grep with fixed string match
sed -i 's|grep -qE .*command_registry.* runtime/schema/command_registry.json .*|grep -qF "\"contract\": \"command_registry\"" runtime/schema/command_registry.json || fail "command_registry missing contract tag"|' "$f"

# 2) Replace commands grep with fixed string match
sed -i 's|grep -qE .*"commands".* runtime/schema/command_registry.json .*|grep -qF "\"commands\"" runtime/schema/command_registry.json || fail "command_registry missing commands"|' "$f"

chmod +x "$f"
echo "OK: patched Phase 0.5 greps to deterministic fixed-string checks."
