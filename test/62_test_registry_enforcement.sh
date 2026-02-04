#!/usr/bin/env bash
set -euo pipefail

ROOT="."

REG="$ROOT/runtime/schema/projection_registry.json"
BACK="$ROOT/test/tmp/_reg_backup.json"

mkdir -p "$ROOT/test/tmp"

test -x "$ROOT/runtime/bin/rebuild_projections" || { echo "ERROR: rebuild_projections missing"; exit 1; }
test -f "$REG" || { echo "ERROR: registry missing"; exit 1; }

cp "$REG" "$BACK"

cleanup() {
  cp "$BACK" "$REG" || true
}
trap cleanup EXIT

# A) Add fake projection -> rebuild must FAIL
python3 - <<'PY'
import json
p="runtime/schema/projection_registry.json"
d=json.load(open(p,"r",encoding="utf-8"))
d["projections"].append({
  "name":"fake_projection",
  "source_log":"runtime/state/logs/executions.jsonl",
  "output":"runtime/state/projections/fake.json",
  "enabled": True
})
json.dump(d, open(p,"w",encoding="utf-8"), indent=2, sort_keys=True); open(p,"a").write("\n")
PY

if "$ROOT/runtime/bin/rebuild_projections" >/dev/null 2>&1; then
  echo "FAIL: rebuild succeeded with fake projection"
  exit 1
fi
echo "PASS: fake projection correctly rejected"

# B) Restore registry and disable existing projection -> rebuild should skip (still succeed)
cp "$BACK" "$REG"
python3 - <<'PY'
import json
p="runtime/schema/projection_registry.json"
d=json.load(open(p,"r",encoding="utf-8"))
d["projections"][0]["enabled"] = False
json.dump(d, open(p,"w",encoding="utf-8"), indent=2, sort_keys=True); open(p,"a").write("\n")
PY

"$ROOT/runtime/bin/rebuild_projections" >/dev/null
echo "PASS: disabled projection skipped (rebuild succeeded)"

echo "✅ Phase 62 TEST PASS"
