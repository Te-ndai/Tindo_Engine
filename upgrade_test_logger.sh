#!/usr/bin/env bash
set -euo pipefail

f="test/02_test.sh"
[ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }

# Overwrite with a clean, cumulative-check logger version.
cat > "$f" <<'EOF'
#!/usr/bin/env bash
# test/02_test.sh
# Phase 0.4 TEST: verify host adapters + typed paths + capability lattice.
# Writes: logs/test.results.json

set -euo pipefail

mkdir -p logs

CHECKS=()

add_check() { CHECKS+=("$1"); }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; write_result "FAIL" "$*"; exit 1; }

write_result() {
  local status="$1"
  local msg="$2"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # JSON array for checks
  local checks_json
  checks_json="$(printf "%s\n" "${CHECKS[@]}" | awk '
    BEGIN{print "["}
    {
      gsub(/\\/,"\\\\",$0); gsub(/"/,"\\\"",$0);
      printf "%s\"%s\"", (NR==1?"":","), $0
    }
    END{print "]"}
  ')"

  cat > logs/test.results.json <<EOT
{
  "phase": "0.4",
  "action": "TEST",
  "timestamp_utc": "$ts",
  "status": "$status",
  "message": "$msg",
  "checks": $checks_json
}
EOT
}

# Preconditions
[ -f "specs/system.md" ] || fail "missing specs/system.md"
[ -f "specs/constraints.md" ] || fail "missing specs/constraints.md"
[ -f "specs/phases.md" ] || fail "missing specs/phases.md"
add_check "specs exist"

[ -f "logs/build.manifest.json" ] || fail "missing logs/build.manifest.json"
[ -f "logs/populate.files.json" ] || fail "missing logs/populate.files.json"
[ -f "logs/populate.hashes.json" ] || fail "missing logs/populate.hashes.json"
add_check "build + populate logs exist"

# 1) Canonical entrypoint
[ -f "runtime/bin/app_entry" ] || fail "missing runtime/bin/app_entry"
add_check "canonical entrypoint exists"
pass "canonical entrypoint exists"

# 2) Host adapter contract
[ -f "runtime/schema/host_adapter_contract.json" ] || fail "missing runtime/schema/host_adapter_contract.json"
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
  dir="runtime/host_adapters/$h"
  [ -d "$dir" ] || fail "missing adapter dir: $dir"
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
  inv="runtime/host_adapters/$h/invoke.sh"
  grep -qE '\.\./\.\./bin/app_entry' "$inv" || fail "$h invoke.sh does not call ../../bin/app_entry"
  grep -qE '(curl|wget|python|python3|node|powershell|pwsh|Invoke-WebRequest|Start-Process)' "$inv" && fail "$h invoke.sh contains forbidden calls"
  add_check "adapter $h invoke purity ok"
  pass "$h invoke.sh purity OK"
done

win_inv="runtime/host_adapters/windows/invoke.ps1"
grep -qE '\\\.\.\\\.\.\\bin\\app_entry' "$win_inv" || fail "windows invoke.ps1 does not call ..\\..\\bin\\app_entry"
grep -qE '(Invoke-WebRequest|Start-Process|curl|wget|python|python3|node)' "$win_inv" && fail "windows invoke.ps1 contains forbidden calls"
add_check "adapter windows invoke purity ok"
pass "windows invoke.ps1 purity OK"

# 5) Typed path contract + model
[ -f "runtime/schema/typed_path_contract.json" ] || fail "missing runtime/schema/typed_path_contract.json"
[ -s "runtime/schema/typed_path_contract.json" ] || fail "typed_path_contract.json empty"
[ -f "runtime/core/path_model.py" ] || fail "missing runtime/core/path_model.py"
grep -q '"from"[[:space:]]*:[[:space:]]*"HostPath"' runtime/schema/typed_path_contract.json || fail "typed_path_contract missing HostPath ref"
grep -q '"to"[[:space:]]*:[[:space:]]*"MemoryPath"' runtime/schema/typed_path_contract.json || fail "typed_path_contract missing MemoryPath ref"
add_check "typed path contract + model exist + forbidden transition declared"
pass "typed path contract + path_model OK"

# 6) Capability lattice contract + model
[ -f "runtime/schema/capability_lattice.json" ] || fail "missing runtime/schema/capability_lattice.json"
[ -s "runtime/schema/capability_lattice.json" ] || fail "capability_lattice.json empty"
[ -f "runtime/core/capability.py" ] || fail "missing runtime/core/capability.py"
grep -q '"contract"[[:space:]]*:[[:space:]]*"capability_lattice"' runtime/schema/capability_lattice.json || fail "capability_lattice missing contract tag"
grep -q '"meet_table"' runtime/schema/capability_lattice.json || fail "capability_lattice missing meet_table"
grep -q '"execution_valid_iff_meet_not_bottom"' runtime/schema/capability_lattice.json || fail "capability_lattice missing rule flag"
add_check "capability lattice contract + model exist + schema markers present"
pass "capability lattice contract + capability.py OK"

# 7) Top-level directory set matches system skeleton
allowed_top='^(./)?(build|populate|test|promote|specs|logs|runtime)$'
extra_top="$(find . -maxdepth 1 -mindepth 1 -type d -printf "%p\n" | sort | grep -Ev "$allowed_top" || true)"
[ -z "$extra_top" ] || fail "extra top-level dirs found: $(echo "$extra_top" | tr '\n' ' ')"
add_check "top-level directory set OK"
pass "top-level directory set OK"

write_result "PASS" "all checks passed"
echo "✅ Phase 0.4 TEST PASS"
echo "Wrote: logs/test.results.json"
EOF

chmod +x "$f"
echo "OK: upgraded test/02_test.sh logger to Phase 0.4 with check list."
