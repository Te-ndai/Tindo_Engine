#!/usr/bin/env bash
set -euo pipefail
mkdir -p test/tmp

# Backup
cp runtime/state/logs/executions.jsonl test/tmp/executions.bak || true
rm -f runtime/state/logs/executions.chain.checkpoint.json runtime/state/logs/executions.chain.jsonl

# Init
./runtime/bin/logchain_init >/dev/null
echo "OK: init done"

# Tamper source log (rewrite existing line)
python3 - <<'PY'
import json, pathlib
p=pathlib.Path("runtime/state/logs/executions.jsonl")
lines=p.read_text(encoding="utf-8").splitlines()
nonempty=[i for i,l in enumerate(lines) if l.strip()]
mid=nonempty[len(nonempty)//2]
ev=json.loads(lines[mid])
ev["command"]=str(ev.get("command","noop"))+"_REWRITE"
lines[mid]=json.dumps(ev, sort_keys=True)
p.write_text("\n".join(lines)+"\n", encoding="utf-8")
print("OK: source tampered")
PY

# Append should FAIL (rewrite detected)
set +e
./runtime/bin/logchain_append >/dev/null
code=$?
set -e
if [ "$code" -eq 0 ]; then
  echo "FAIL: append succeeded despite rewrite"
  exit 1
fi
echo "PASS: append blocked rewrite"

# Init should be refused because checkpoint exists
set +e
./runtime/bin/logchain_init >/dev/null
code=$?
set -e
if [ "$code" -eq 0 ]; then
  echo "FAIL: init succeeded despite checkpoint"
  exit 1
fi
echo "PASS: init refused when checkpoint exists"

# Restore
cp test/tmp/executions.bak runtime/state/logs/executions.jsonl || true

echo "✅ Phase 75 TEST PASS"
