#!/usr/bin/env bash
set -euo pipefail

cat > runtime/bin/release_bundle <<'SH'
#!/usr/bin/env bash
set -euo pipefail

ts="$(date -u +%Y%m%dT%H%M%SZ)"
outdir="runtime/state/releases"
mkdir -p "$outdir"

# Ensure current + coherent
./runtime/bin/runbook >/dev/null
./runtime/bin/logchain_verify >/dev/null

bundle="$outdir/release_${ts}.tar.gz"
manifest="$outdir/release_${ts}.json"

# Build manifest pre-hash
python3 - <<PY
import json, os, hashlib, glob
from datetime import datetime, timezone

ts="${ts}"
bundle="${bundle}"
manifest="${manifest}"

def sha256_file(p):
    h=hashlib.sha256()
    with open(p,"rb") as f:
        for b in iter(lambda: f.read(1024*1024), b""):
            h.update(b)
    return h.hexdigest()

def count_nonempty_lines(p):
    if not os.path.exists(p): return 0
    n=0
    with open(p,"r",encoding="utf-8") as f:
        for line in f:
            if line.strip(): n+=1
    return n

cp="runtime/state/logs/executions.chain.checkpoint.json"
ck={}
if os.path.exists(cp):
    ck=json.load(open(cp,"r",encoding="utf-8"))

# projection last_event_time (executions_summary is authoritative here)
le=""
p="runtime/state/projections/executions_summary.json"
if os.path.exists(p):
    d=json.load(open(p,"r",encoding="utf-8"))
    le=d.get("last_event_time_utc","") or ""

ss_ok=None
p2="runtime/state/projections/system_status.json"
if os.path.exists(p2):
    d=json.load(open(p2,"r",encoding="utf-8"))
    ss_ok=d.get("ok")

m={
  "created_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "release_id": ts,
  "counts": {
    "executions_jsonl_lines": count_nonempty_lines("runtime/state/logs/executions.jsonl"),
    "chain_jsonl_lines": count_nonempty_lines("runtime/state/logs/executions.chain.jsonl")
  },
  "checkpoint": ck,
  "last_event_time_utc": le,
  "system_status_ok": ss_ok,
  "bundle_path": bundle,
  "bundle_sha256": ""
}
open(manifest,"w",encoding="utf-8").write(json.dumps(m, indent=2, sort_keys=True) + "\n")
print("OK: wrote manifest (pre-hash)")
PY

# Create bundle
tar -czf "$bundle" \
  runtime/state/logs/executions.jsonl \
  runtime/state/logs/executions.chain.jsonl \
  runtime/state/logs/executions.chain.checkpoint.json \
  runtime/state/projections \
  runtime/state/reports \
  runtime/schema \
  runtime/core/projections.py \
  runtime/bin/ops \
  runtime/bin/runbook \
  runtime/bin/rebuild_projections \
  runtime/bin/make_fresh \
  runtime/bin/logchain_init \
  runtime/bin/logchain_append \
  runtime/bin/logchain_verify \
  runtime/bin/dashboard \
  "$manifest"

# Fill bundle hash into manifest
python3 - <<PY
import json, hashlib
bundle="${bundle}"
manifest="${manifest}"
h=hashlib.sha256()
with open(bundle,"rb") as f:
    for b in iter(lambda: f.read(1024*1024), b""):
        h.update(b)
sha=h.hexdigest()
d=json.load(open(manifest,"r",encoding="utf-8"))
d["bundle_sha256"]=sha
open(manifest,"w",encoding="utf-8").write(json.dumps(d, indent=2, sort_keys=True) + "\n")
print("OK: bundle sha256 =", sha)
PY

echo "OK: wrote $bundle"
echo "OK: wrote $manifest"
SH

chmod +x runtime/bin/release_bundle
echo "OK: phase 83 populate complete"
