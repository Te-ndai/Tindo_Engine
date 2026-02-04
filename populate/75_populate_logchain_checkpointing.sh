#!/usr/bin/env bash
set -euo pipefail

cat > runtime/bin/logchain_init <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SRC="runtime/state/logs/executions.jsonl"
CHAIN="runtime/state/logs/executions.chain.jsonl"
CP="runtime/state/logs/executions.chain.checkpoint.json"

python3 - <<'PY'
import json, hashlib, os, sys
from datetime import datetime, timezone

src="runtime/state/logs/executions.jsonl"
chain="runtime/state/logs/executions.chain.jsonl"
cp="runtime/state/logs/executions.chain.checkpoint.json"

if os.path.exists(cp):
    print("ERROR: checkpoint exists; init refused")
    sys.exit(3)

if not os.path.exists(src):
    print("ERROR: source log missing:", src)
    sys.exit(3)

prev="0"*64
n=0
with open(src,"r",encoding="utf-8") as fin, open(chain+".tmp","w",encoding="utf-8") as fout:
    for line in fin:
        line=line.strip()
        if not line:
            continue
        ev=json.loads(line)
        ev2=dict(ev)
        ev2.pop("prev_sha256", None)
        ev2.pop("line_sha256", None)
        payload=json.dumps(ev2, sort_keys=True, separators=(",",":")).encode("utf-8")
        h=hashlib.sha256(prev.encode("utf-8")+payload).hexdigest()
        ev2["prev_sha256"]=prev
        ev2["line_sha256"]=h
        fout.write(json.dumps(ev2, sort_keys=True) + "\n")
        prev=h
        n+=1

os.replace(chain+".tmp", chain)

ck={
  "lines": n,
  "last_line_sha256": prev if n>0 else "0"*64,
  "checkpoint_time_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}
with open(cp+".tmp","w",encoding="utf-8") as f:
    json.dump(ck, f, indent=2, sort_keys=True)
    f.write("\n")
os.replace(cp+".tmp", cp)

print("OK: init complete lines=", n)
PY
SH
chmod +x runtime/bin/logchain_init


cat > runtime/bin/logchain_append <<'SH'
#!/usr/bin/env bash
set -euo pipefail

SRC="runtime/state/logs/executions.jsonl"
CHAIN="runtime/state/logs/executions.chain.jsonl"
CP="runtime/state/logs/executions.chain.checkpoint.json"

python3 - <<'PY'
import json, hashlib, os, sys
from datetime import datetime, timezone

src="runtime/state/logs/executions.jsonl"
chain="runtime/state/logs/executions.chain.jsonl"
cp="runtime/state/logs/executions.chain.checkpoint.json"

if not os.path.exists(cp):
    print("ERROR: missing checkpoint; run logchain_init first")
    sys.exit(3)

ck=json.load(open(cp,"r",encoding="utf-8"))
start=int(ck.get("lines",0))
prev=str(ck.get("last_line_sha256","0"*64))

if not os.path.exists(src) or not os.path.exists(chain):
    print("ERROR: missing src or chain")
    sys.exit(3)

# Read source lines and process only new ones
lines=[l for l in open(src,"r",encoding="utf-8").read().splitlines() if l.strip()]
if start > len(lines):
    print("FAIL: source log shorter than checkpoint (rewrite detected)")
    sys.exit(1)

new = lines[start:]
if not new:
    print("OK: no new lines")
    sys.exit(0)

# Append to chain
with open(chain,"a",encoding="utf-8") as fout:
    for line in new:
        ev=json.loads(line)
        ev2=dict(ev)
        ev2.pop("prev_sha256", None)
        ev2.pop("line_sha256", None)
        payload=json.dumps(ev2, sort_keys=True, separators=(",",":")).encode("utf-8")
        h=hashlib.sha256(prev.encode("utf-8")+payload).hexdigest()
        ev2["prev_sha256"]=prev
        ev2["line_sha256"]=h
        fout.write(json.dumps(ev2, sort_keys=True) + "\n")
        prev=h
        start += 1

ck2={
  "lines": start,
  "last_line_sha256": prev,
  "checkpoint_time_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}
with open(cp+".tmp","w",encoding="utf-8") as f:
    json.dump(ck2, f, indent=2, sort_keys=True); f.write("\n")
os.replace(cp+".tmp", cp)

print("OK: appended lines, new_total=", start)
PY
SH
chmod +x runtime/bin/logchain_append

echo "OK: phase 75 populate complete"
