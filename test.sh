cat >> test/02_test.sh <<'EOF'

# -----------------------------
# Phase 0.3 — Typed Path Tests
# -----------------------------
[ -f "runtime/schema/typed_path_contract.json" ] || fail "missing runtime/schema/typed_path_contract.json"
[ -f "runtime/core/path_model.py" ] || fail "missing runtime/core/path_model.py"
pass "typed path contract + path_model exist"

# Ensure forbidden transition is declared in the contract JSON (string check)
grep -q '"from": "HostPath"' runtime/schema/typed_path_contract.json || fail "typed_path_contract missing HostPath reference"
grep -q '"to": "MemoryPath"' runtime/schema/typed_path_contract.json || fail "typed_path_contract missing MemoryPath reference"
pass "typed_path_contract contains HostPath->MemoryPath prohibition markers"
EOF
