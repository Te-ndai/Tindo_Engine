#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

F="test/83_test_release_bundle.sh"
[ -f "$F" ] || { echo "❌ missing $F" >&2; exit 1; }

B="${F}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp -f "$F" "$B"
echo "✅ backup: $B"

# Replace grep -q '^...$' with fixed-string whole-line matches.
python3 - <<'PY' "test/83_test_release_bundle.sh"
from pathlib import Path
p = Path(__import__("sys").argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

repls = [
    ("tar -tzf \"$bundle\" | grep -q '^runtime/state/reports/diagnose\\.txt$' || die \"missing diagnose.txt in bundle\"",
     "tar -tzf \"$bundle\" | grep -F -x -q 'runtime/state/reports/diagnose.txt' || die \"missing diagnose.txt in bundle\""),
    ("tar -tzf \"$bundle\" | grep -q '^runtime/state/logs/executions\\.chain\\.checkpoint\\.json$' || die \"missing checkpoint in bundle\"",
     "tar -tzf \"$bundle\" | grep -F -x -q 'runtime/state/logs/executions.chain.checkpoint.json' || die \"missing checkpoint in bundle\""),
    ("tar -tzf \"$bundle\" | grep -q '^runtime/state/logs/executions\\.chain\\.jsonl$' || die \"missing executions.chain.jsonl in bundle\"",
     "tar -tzf \"$bundle\" | grep -F -x -q 'runtime/state/logs/executions.chain.jsonl' || die \"missing executions.chain.jsonl in bundle\""),
    ("tar -tzf \"$bundle\" | grep -q '^runtime/bin/logchain_verify$' || die \"missing runtime/bin/logchain_verify in bundle\"",
     "tar -tzf \"$bundle\" | grep -F -x -q 'runtime/bin/logchain_verify' || die \"missing runtime/bin/logchain_verify in bundle\""),
    ("tar -tzf \"$bundle\" | grep -q '^runtime/bin/rebuild_projections$' || die \"missing runtime/bin/rebuild_projections in bundle\"",
     "tar -tzf \"$bundle\" | grep -F -x -q 'runtime/bin/rebuild_projections' || die \"missing runtime/bin/rebuild_projections in bundle\""),
    ("tar -tzf \"$bundle\" | grep -q '^runtime/bin/ops$' || die \"missing runtime/bin/ops in bundle\"",
     "tar -tzf \"$bundle\" | grep -F -x -q 'runtime/bin/ops' || die \"missing runtime/bin/ops in bundle\""),
    ("tar -tzf \"$bundle\" | grep -q '^runtime/core/projections\\.py$' || die \"missing runtime/core/projections.py in bundle\"",
     "tar -tzf \"$bundle\" | grep -F -x -q 'runtime/core/projections.py' || die \"missing runtime/core/projections.py in bundle\""),
]

for a,b in repls:
    if a in s:
        s = s.replace(a,b)

p.write_text(s, encoding="utf-8")
print("OK: rewrote grep checks to grep -F -x")
PY

chmod +x "$F"
echo "✅ fixed Phase 83 greps (exact match)"
echo "Run:"
echo "  ./test/83_test_release_bundle.sh"
