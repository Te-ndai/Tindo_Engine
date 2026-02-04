#!/usr/bin/env bash
# test/50_test_app_entry.sh
# Smoke tests for runtime/bin/app_entry behavior.

set -euo pipefail

ok() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x runtime/bin/app_entry ] || fail "runtime/bin/app_entry not executable"

# noop
out="$(runtime/bin/app_entry '{"command":"noop","args":{}}')"
echo "$out" | grep -q '"ok": true' || fail "noop did not return ok:true"
echo "$out" | grep -q '"command": "noop"' || fail "noop did not echo command"
ok "noop works"

# validate noop
out2="$(runtime/bin/app_entry '{"command":"validate","args":{"command":"noop","args":{}}}')"
echo "$out2" | grep -q '"valid": true' || fail "validate noop not valid:true"
ok "validate(noop) works"

# invalid command
out3="$(runtime/bin/app_entry '{"command":"does_not_exist","args":{}}' || true)"
echo "$out3" | grep -q '"ok": false' || fail "unknown command did not return ok:false"
ok "unknown command fails as expected"

echo "✅ Phase 5 app_entry smoke tests PASS"
