#!/usr/bin/env bash
# test/30_stage_test.sh
# Phase 3 TEST (staged): verify stage runtime artifacts match contracts.
# Target runtime: logs/env/stage_build/runtime
# Writes: logs/env/stage_build/logs/test.results.json

set -euo pipefail

STAGE="logs/env/stage_build"
R="$STAGE/runtime"
L="$STAGE/logs"
mkdir -p "$L"

CHECKS=()
add_check(){ CHECKS+=("$1"); }
pass(){ echo "PASS: $*"; }

write_result(){
  local status="$1"; local msg="$2"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local checks_json
  checks_json="$(printf "%s\n" "${CHECKS[@]}" | awk '
    BEGIN{print "["}
    {
      gsub(/\\/,"\\\\",$0); gsub(/"/,"\\\"",$0);
      printf "%s\"%s\"", (NR==1?"":","), $0
    }
    END{print "]"}
  ')"

  cat > "$L/test.results.json" <<EOF
{
  "phase": "3",
  "action": "TEST",
  "timestamp_utc": "$ts",
  "status": "$status",
  "message": "$msg",
  "checks": $checks_json
}
EOF
}

fail(){ echo "FAIL: $*" >&2; write_result "FAIL" "$*"; exit 1; }

# Preconditions: staged build + populate logs exist
[ -f "$L/build.manifest.json" ] || fail "missing stage build.manifest.json"
[ -f "$L/populate.files.json" ] || fail "missing stage populate.files.json"
[ -f "$L/populate.hashes.json" ] || fail "missing stage populate.hashes.json"
add_check "stage build + populate logs exist"
pass "stage build + populate logs exist"

# 1) Canonical entrypoint
[ -f "$R/bin/app_entry" ] || fail "missing stage runtime/bin/app_entry"
add_check "canonical entrypoint exists"
pass "canonical entrypoint exists"

# 2) Host adapter contract exists
[ -f "$R/schema/host_adapter_contract.json" ] || fail "missing stage schema/host_adapter_contract.json"
add_check "host adapter contract exists"
pass "host adapter contract exists"

# JSON helpers (no jq)
json_get_string() {
  local file="$1"; local key="$2"
  sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/p" "$file" | head -n 1
}
json_get_bool() {
  local file="$1"; local key="$2"
  sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*(true|false).*/\1/p" "$file" | head -n 1
}

# 3) Host adapters exist + required files + manifest invariants
hosts=(linux windows macos)
for h in "${hosts[@]}"; do
  dir="$R/host_adapters/$h"
  [ -d "$dir" ] || fail "missing stage adapter dir: $dir"
  [ -f "$dir/manifest.json" ] || fail "missing $dir/manifest.json"

  entry="$(json_get_string "$dir/manifest.json" "entrypoint")"
  [ "$entry" = "runtime/bin/app_entry" ] || fail "$h manifest entrypoint '$entry' != runtime/bin/app_entry"

  allow_paths="$(json_get_bool "$dir/manifest.json" "allow_untyped_paths")"
  [ "$allow_paths" = "false" ] || fail "$h allow_untyped_paths '$allow_paths' != false"

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

  add_check "adapter $h required files exist"
  add_check "adapter $h manifest entrypoint + args_policy valid"
  pass "$h required files exist + manifest valid"
done

# 4) Invoke purity
for h in linux macos; do
  inv="$R/host_adapters/$h/invoke.sh"
  grep -qE '\.\./\.\./bin/app_entry' "$inv" || fail "$h invoke.sh does not call ../../bin/app_entry"
  grep -qE '(curl|wget|python|python3|node|powershell|pwsh|Invoke-WebRequest|Start-Process)' "$inv" && fail "$h invoke.sh contains forbidden calls"
  add_check "adapter $h invoke purity ok"
  pass "$h invoke.sh purity OK"
done

win_inv="$R/host_adapters/windows/invoke.ps1"
grep -qE '\\\.\.\\\.\.\\bin\\app_entry' "$win_inv" || fail "windows invoke.ps1 does not call ..\\..\\bin\\app_entry"
grep -qE '(Invoke-WebRequest|Start-Process|curl|wget|python|python3|node)' "$win_inv" && fail "windows invoke.ps1 contains forbidden calls"
add_check "adapter windows invoke purity ok"
pass "windows invoke.ps1 purity OK"

# 5) Typed paths
[ -f "$R/schema/typed_path_contract.json" ] || fail "missing typed_path_contract.json"
[ -s "$R/schema/typed_path_contract.json" ] || fail "typed_path_contract.json empty"
[ -f "$R/core/path_model.py" ] || fail "missing core/path_model.py"
grep -q '"from"[[:space:]]*:[[:space:]]*"HostPath"' "$R/schema/typed_path_contract.json" || fail "typed_path_contract missing HostPath ref"
grep -q '"to"[[:space:]]*:[[:space:]]*"MemoryPath"' "$R/schema/typed_path_contract.json" || fail "typed_path_contract missing MemoryPath ref"
add_check "typed path contract + model exist + forbidden transition declared"
pass "typed path contract + path_model OK"

# 6) Capability lattice
[ -f "$R/schema/capability_lattice.json" ] || fail "missing capability_lattice.json"
[ -s "$R/schema/capability_lattice.json" ] || fail "capability_lattice.json empty"
[ -f "$R/core/capability.py" ] || fail "missing core/capability.py"
grep -qF '"contract": "capability_lattice"' "$R/schema/capability_lattice.json" || fail "capability_lattice missing contract tag"
grep -qF '"meet_table"' "$R/schema/capability_lattice.json" || fail "capability_lattice missing meet_table"
grep -qF '"execution_valid_iff_meet_not_bottom"' "$R/schema/capability_lattice.json" || fail "capability_lattice missing rule flag"
add_check "capability lattice contract + model exist + schema markers present"
pass "capability lattice contract + capability.py OK"

# 7) Command registry
[ -f "$R/schema/command_registry.json" ] || fail "missing command_registry.json"
[ -s "$R/schema/command_registry.json" ] || fail "command_registry.json empty"
[ -f "$R/core/executor.py" ] || fail "missing core/executor.py"
grep -qF '"contract": "command_registry"' "$R/schema/command_registry.json" || fail "command_registry missing contract tag"
grep -qF '"commands"' "$R/schema/command_registry.json" || fail "command_registry missing commands"
add_check "command registry contract + executor stub exist"
pass "command registry contract + executor.py OK"

write_result "PASS" "all staged checks passed"
echo "✅ Phase 3 TEST (staged) PASS"
echo "Wrote: $L/test.results.json"
