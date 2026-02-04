#!/usr/bin/env bash
set -euo pipefail

cat > runtime/bin/logchain_init <<'SH2'
#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json, hashlib, os, sys
from datetime import datetime, timezone

SRC="runtime/state/logs/executions.jsonl"
CHAIN="runtime/state/logs/executions.chain.jsonl"
CP="runtime/state/logs/executions.chain.checkpoint.json"

if os.path.exists(CP):
    print("ERROR: checkpoint exists; init refused")
    sys.exit(3)

if not os.path.exists(SRC):
    print("ERROR: source log missing:", SRC)
    sys.exit(3)

def canon(ev: dict) -> bytes:
    ev2=dict(ev)
    ev2.pop("prev_sha256", None)
    ev2.pop("line_sha256", None)
    return json.dumps(ev2, sort_keys=True, separators=(",",":")).encode("utf-8")

# Load source events
raw=[l for l in open(SRC,"r",encoding="utf-8").read().splitlines() if l.strip()]
events=[json.loads(l) for l in raw]

# Build chain
prev="0"*64
n=0
with open(CHAIN+".tmp","w",encoding="utf-8") as fout:
    for ev in events:
        payload=canon(ev)
        h=hashlib.sha256(prev.encode("utf-8")+payload).hexdigest()
        ev2=json.loads(payload.decode("utf-8"))
        ev2["prev_sha256"]=prev
        ev2["line_sha256"]=h
        fout.write(json.dumps(ev2, sort_keys=True) + "\n")
        prev=h
        n+=1
os.replace(CHAIN+".tmp", CHAIN)

# Prefix digest of source up to N (entire current file)
pref=hashlib.sha256()
for ev in events:
    pref.update(canon(ev))
prefix_sha=pref.hexdigest()

ck={
  "lines": n,
  "last_line_sha256": prev if n>0 else "0"*64,
  "source_prefix_sha256": prefix_sha,
  "checkpoint_time_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}
with open(CP+".tmp","w",encoding="utf-8") as f:
    json.dump(ck, f, indent=2, sort_keys=True); f.write("\n")
os.replace(CP+".tmp", CP)

print("OK: init complete lines=", n)
PY
SH2
chmod +x runtime/bin/logchain_init

cat > runtime/bin/logchain_append <<'SH2'
#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json, hashlib, os, sys
from datetime import datetime, timezone

SRC="runtime/state/logs/executions.jsonl"
CHAIN="runtime/state/logs/executions.chain.jsonl"
CP="runtime/state/logs/executions.chain.checkpoint.json"

if not os.path.exists(CP):
    print("ERROR: missing checkpoint; run logchain_init first")
    sys.exit(3)
if not os.path.exists(SRC) or not os.path.exists(CHAIN):
    print("ERROR: missing src or chain")
    sys.exit(3)

ck=json.load(open(CP,"r",encoding="utf-8"))
start=int(ck.get("lines",0))
prev=str(ck.get("last_line_sha256","0"*64))
expected_prefix=str(ck.get("source_prefix_sha256",""))

def canon(ev: dict) -> bytes:
    ev2=dict(ev)
    ev2.pop("prev_sha256", None)
    ev2.pop("line_sha256", None)
    return json.dumps(ev2, sort_keys=True, separators=(",",":")).encode("utf-8")

raw=[l for l in open(SRC,"r",encoding="utf-8").read().splitlines() if l.strip()]
if start > len(raw):
    print("FAIL: source log shorter than checkpoint (rewrite/truncate detected)")
    sys.exit(1)

# Verify prefix digest for first start lines
pref=hashlib.sha256()
for i in range(start):
    ev=json.loads(raw[i])
    pref.update(canon(ev))
got_prefix=pref.hexdigest()
if expected_prefix and got_prefix != expected_prefix:
    print("FAIL: source prefix hash mismatch (rewrite detected)")
    sys.exit(1)

new = raw[start:]
if not new:
    print("OK: no new lines")
    sys.exit(0)

# Append new lines
with open(CHAIN,"a",encoding="utf-8") as fout:
    for line in new:
        ev=json.loads(line)
        payload=canon(ev)
        h=hashlib.sha256(prev.encode("utf-8")+payload).hexdigest()
        ev2=json.loads(payload.decode("utf-8"))
        ev2["prev_sha256"]=prev
        ev2["line_sha256"]=h
        fout.write(json.dumps(ev2, sort_keys=True) + "\n")
        prev=h
        start += 1

# Update checkpoint prefix digest to include all lines up to new start
pref2=hashlib.sha256()
for i in range(start):
    ev=json.loads(raw[i])
    pref2.update(canon(ev))
prefix_sha=pref2.hexdigest()

ck2={
  "lines": start,
  "last_line_sha256": prev,
  "source_prefix_sha256": prefix_sha,
  "checkpoint_time_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}
with open(CP+".tmp","w",encoding="utf-8") as f:
    json.dump(ck2, f, indent=2, sort_keys=True); f.write("\n")
os.replace(CP+".tmp", CP)

print("OK: appended lines, new_total=", start)
PY
SH2
chmod +x runtime/bin/logchain_append

echo "OK: patched logchain to enforce source prefix hash"
