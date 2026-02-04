#!/usr/bin/env bash
set -euo pipefail

cat > runtime/bin/logchain_rebuild <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SRC="runtime/state/logs/executions.jsonl"
OUT="runtime/state/logs/executions.chain.jsonl"

python3 - <<'PY'
import json, hashlib, os, sys

src="runtime/state/logs/executions.jsonl"
out="runtime/state/logs/executions.chain.jsonl"

if not os.path.exists(src):
    print("ERROR: source log missing:", src)
    sys.exit(3)

prev = "0"*64
n = 0
with open(src,"r",encoding="utf-8") as fin, open(out+".tmp","w",encoding="utf-8") as fout:
    for line in fin:
        line=line.strip()
        if not line:
            continue
        ev=json.loads(line)

        # canonical event JSON (exclude any chain fields if present)
        ev2=dict(ev)
        ev2.pop("prev_sha256", None)
        ev2.pop("line_sha256", None)

        payload=json.dumps(ev2, sort_keys=True, separators=(",",":")).encode("utf-8")
        h=hashlib.sha256(prev.encode("utf-8")+payload).hexdigest()

        ev2["prev_sha256"]=prev
        ev2["line_sha256"]=h

        fout.write(json.dumps(ev2, sort_keys=True) + "\n")
        prev=h
        n += 1

os.replace(out+".tmp", out)
print("OK: rebuilt chain log, lines=", n)
PY
SH
chmod +x runtime/bin/logchain_rebuild

cat > runtime/bin/logchain_verify <<'SH'
#!/usr/bin/env bash
set -euo pipefail

CHAIN="runtime/state/logs/executions.chain.jsonl"

python3 - <<'PY'
import json, hashlib, os, sys

path="runtime/state/logs/executions.chain.jsonl"
if not os.path.exists(path):
    print("ERROR: chain log missing:", path)
    sys.exit(3)

prev="0"*64
n=0
with open(path,"r",encoding="utf-8") as f:
    for line in f:
        line=line.strip()
        if not line:
            continue
        ev=json.loads(line)

        got_prev=ev.get("prev_sha256")
        got_h=ev.get("line_sha256")
        if got_prev != prev:
            print("FAIL: prev mismatch at line", n+1)
            sys.exit(1)

        ev2=dict(ev)
        ev2.pop("prev_sha256", None)
        ev2.pop("line_sha256", None)

        payload=json.dumps(ev2, sort_keys=True, separators=(",",":")).encode("utf-8")
        h=hashlib.sha256(prev.encode("utf-8")+payload).hexdigest()

        if got_h != h:
            print("FAIL: hash mismatch at line", n+1)
            sys.exit(1)

        prev=h
        n += 1

print("PASS: chain ok, lines=", n)
PY
SH
chmod +x runtime/bin/logchain_verify

echo "OK: phase 72 populate complete"
