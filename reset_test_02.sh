#!/usr/bin/env bash
set -euo pipefail

mkdir -p test logs

cat > test/02_test.sh <<'EOF'
#!/usr/bin/env bash
# test/02_test.sh
# Phase 0.3 TEST: verify host adapter contract + typed path contract.
# Writes: logs/test.results.json
# Read-only over runtime/ and logs/.

set -euo pipefail

write_result() {
  local status="$1"
  local msg="$2"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat > logs/test.results.json <<EOT
{
  "phase": "0.3",
  "action": "TEST",
  "timestamp_utc": "$ts",
  "status": "$status",
  "message": "$msg"
}
EOT
}

fail() { echo "FAIL: $*" >&2; write_result "FAIL" "$*"; exit 1; }
pass() { echo "PASS: $*"; }

# Preconditions
[ -f "specs/system.md" ] || fail "missing specs/system.md"
[ -f "specs/constraints.md" ] || fail "missing specs/constraints.md"
[ -f "specs/phases.md" ] || fail "missing specs/phases.md"

[ -f "logs/build.manifest.json" ] || fail "missing logs/build.manifest.json"
[ -f "logs/populate.files.json" ] || fail "missing logs/populate.files.json"
[ -f "logs/populate.hashes.json" ] || fail "missing logs/populate.hashes.json"

# 1) Canonical entrypoint exists
[ -f "runtime/bin/app_entry" ] || fail "missing runtime/bin/app_entry"
pass "canonical entrypoint exists"

# 2) Host adapter contract exists
[ -f "runtime/schema/host_adapter_contract.json" ] || fail "missing runtime/schema/host_adapter_contract.json"
pass "host adapter contract exists"

# Helper: extract JSON string field without jq
json_get_string() {
  local file="$1"
  local key="$2"
  sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/p" "$file" | head -n 1
}
json_get_bool() {
  local file="$1"
  local key="$2"
  sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*(true|false).*/\1/p" "$file" | head -n 1
}

# 3) Host adapter directories + required files exist + manifest checks
hosts=(linux windows macos)

for h in "${hosts[@]}"; do
  dir="runtime/host_adapters/$h"
  [ -d "$dir" ] || fail "missing adapter dir: $dir"
  [ -f "$dir/manifest.json" ] || fail "missing $dir/manifest.json"

  entry="$(json_get_string "$dir/manifest.json" "entrypoint")"
  [ "$entry" = "runtime/bin/app_entry" ] || fail "$h manifest entrypoint is '$entry' (expected runtime/bin/app_entry)"

  allow_paths="$(json_get_bool "$dir/manifest.json" "allow_untyped_paths")"
  [ "$allow_paths" = "false" ] || fail "$h manifest allow_untyped_paths is '$allow_paths' (expected false)"

  case "$h" in
    linux|macos)
      [ -f "$dir/install.sh" ] || fail "missing $dir/install.sh"
      [ -f "$dir/uninstall.sh" ] || fail "missing $dir/uninstall.sh"
      [ -f "$dir/invoke.sh" ] || fail "missing $dir/invoke.sh"
      ;;
    windows)
      [ -f "$dir/install.ps1" ] || fail "missing $dir/install.ps1"
      [ -f "$dir/uninstall.ps1" ] || fail "missing $dir/uninstall.ps1"
      [ -f "$dir/invoke.ps1" ] || fail "missing $dir/invoke.ps1"
      ;;
  esac

  pass "$h required files exist + manifest valid"
done

# 4) Invoke scripts purity: must invoke canonical entrypoint only
for h in linux macos; do
  inv="runtime/host_adapters/$h/invoke.sh"
  grep -qE '\.\./\.\./bin/app_entry' "$inv" || fail "$h invoke.sh does not call ../../bin/app_entry"
  grep -qE '(curl|wget|python|python3|node|powershell|pwsh|Invoke-WebRequest|Start-Process)' "$inv" && fail "$h invoke.sh contains forbidden executors/network calls"
  pass "$h invoke.sh purity OK"
done

win_inv="runtime/host_adapters/windows/invoke.ps1"
grep -qE '\\\.\.\\\.\.\\bin\\app_entry' "$win_inv" || fail "windows invoke.ps1 does not call ..\\..\\bin\\app_entry"
grep -qE '(Invoke-WebRequest|Start-Process|curl|wget|python|python3|node)' "$win_inv" && fail "windows invoke.ps1 contains forbidden executors/network calls"
pass "windows invoke.ps1 purity OK"

# 5) Typed path contract + model exist (your hard constraint)
[ -f "runtime/schema/typed_path_contract.json" ] || fail "missing runtime/schema/typed_path_contract.json"
[ -s "runtime/schema/typed_path_contract.json" ] || fail "typed_path_contract.json is empty"
[ -f "runtime/core/path_model.py" ] || fail "missing runtime/core/path_model.py"
pass "typed path contract + path_model exist"

# Ensure the forbidden transition marker exists in contract (string check)
grep -q '"from"[[:space:]]*:[[:space:]]*"HostPath"' runtime/schema/typed_path_contract.json || fail "typed_path_contract missing HostPath reference"
grep -q '"to"[[:space:]]*:[[:space:]]*"MemoryPath"' runtime/schema/typed_path_contract.json || fail "typed_path_contract missing MemoryPath reference"
pass "typed_path_contract contains HostPath->MemoryPath prohibition markers"

# 6) Top-level directory set OK (matches specs/system.md skeleton)
allowed_top='^(./)?(build|populate|test|promote|specs|logs|runtime)$'
extra_top="$(find . -maxdepth 1 -mindepth 1 -type d -printf "%p\n" | sort | grep -Ev "$allowed_top" || true)"
[ -z "$extra_top" ] || fail "extra top-level dirs found: $(echo "$extra_top" | tr '\n' ' ')"
pass "top-level directory set OK"

# If we reach here, the test passed.
write_result "PASS" "all checks passed"
echo "✅ Phase 0.3 TEST PASS"
echo "Wrote: logs/test.results.json"
EOF

chmod +x test/02_test.sh
echo "OK: test/02_test.sh reset to clean Phase 0.3 gate."
