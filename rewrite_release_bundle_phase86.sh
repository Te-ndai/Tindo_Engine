#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

F="runtime/bin/release_bundle"
[ -f "$F" ] || { echo "❌ missing $F" >&2; exit 1; }

B="${F}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp -f "$F" "$B"
echo "✅ backup: $B"

cat > "$F" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

ts="$(date -u +%Y%m%dT%H%M%SZ)"
outdir="runtime/state/releases"
mkdir -p "$outdir"

# Ensure current + coherent
./runtime/bin/runbook >/dev/null
./runtime/bin/logchain_verify >/dev/null

# Hard requirement: reports must exist
test -f runtime/state/reports/diagnose.txt || { echo "ERROR: missing runtime/state/reports/diagnose.txt"; exit 3; }
test -f runtime/state/projections/system_status.json || { echo "ERROR: missing system_status.json"; exit 3; }
test -f runtime/state/projections/diagnose.json || { echo "ERROR: missing diagnose.json"; exit 3; }

bundle="$outdir/release_${ts}.tar.gz"
manifest="$outdir/release_${ts}.json"

# Define the payload file list (manifest excluded by definition)
PAYLOAD_FILES=(
  runtime/state/logs/executions.jsonl
  runtime/state/logs/executions.chain.jsonl
  runtime/state/logs/executions.chain.checkpoint.json
  runtime/state/projections/system_status.json
  runtime/state/projections/diagnose.json
  runtime/state/reports/diagnose.txt
  runtime/state/reports/diagnose.json
  runtime/state/projections
  runtime/schema
  runtime/core/projections.py
  runtime/bin/ops
  runtime/bin/runbook
  runtime/bin/rebuild_projections
  runtime/bin/make_fresh
  runtime/bin/logchain_init
  runtime/bin/logchain_append
  runtime/bin/logchain_verify
  runtime/bin/dashboard
)

# Compute payload_sha256 as hash over (path + NUL + bytes) for all payload members.
payload_sha256="$(python3 - <<'PY'
import hashlib, os, sys

files = sys.argv[1:]
h = hashlib.sha256()

def feed_file(path):
    h.update(path.encode("utf-8") + b"\0")
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1024*1024), b""):
            h.update(b)

def walk_dir(path):
    # Deterministic: sorted file paths
    for root, dirs, files2 in os.walk(path):
        dirs.sort()
        files2.sort()
        for name in files2:
            p=os.path.join(root, name)
            feed_file(p)

for p in files:
    if os.path.isdir(p):
        walk_dir(p)
    else:
        feed_file(p)

print(h.hexdigest())
PY
"${PAYLOAD_FILES[@]}")"

# Write manifest pre-bundle (includes payload_sha256; bundle_sha256 filled after tar)
python3 - <<PY
import json, os
from datetime import datetime, timezone

ts="${ts}"
bundle="${bundle}"
manifest="${manifest}"
payload_sha="${payload_sha256}"

def count_nonempty_lines(p):
    if not os.path.exists(p): return 0
    n=0
    with open(p,"r",encoding="utf-8",errors="replace") as f:
        for line in f:
            if line.strip(): n+=1
    return n

def last_event_time_from_chain(p):
    if not os.path.exists(p): return ""
    last=""
    with open(p,"r",encoding="utf-8",errors="replace") as f:
        for line in f:
            line=line.strip()
            if line: last=line
    if not last: return ""
    try:
        obj=json.loads(last)
    except Exception:
        return ""
    for k in ("event_time_utc","event_time","timestamp_utc","time_utc"):
        v=obj.get(k)
        if isinstance(v,str) and v: return v
    return ""

cp="runtime/state/logs/executions.chain.checkpoint.json"
ck={}
if os.path.exists(cp):
    ck=json.load(open(cp,"r",encoding="utf-8"))

chain_path="runtime/state/logs/executions.chain.jsonl"
chain_lines=count_nonempty_lines(chain_path)
le=last_event_time_from_chain(chain_path)

ss_ok=None
p2="runtime/state/projections/system_status.json"
if os.path.exists(p2):
    d=json.load(open(p2,"r",encoding="utf-8"))
    ss_ok=d.get("ok")

m={
  "created_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "release_id": ts,

  "expected_event_count": chain_lines,
  "expected_last_event_time_utc": le,

  "counts": {
    "executions_jsonl_lines": count_nonempty_lines("runtime/state/logs/executions.jsonl"),
    "chain_jsonl_lines": chain_lines
  },
  "checkpoint": ck,
  "last_event_time_utc": le,
  "system_status_ok": ss_ok,

  # NEW: stable integrity target (hash of payload members, excluding manifest)
  "payload_sha256": payload_sha,

  "bundle_path": bundle,
  "bundle_sha256": ""
}
open(manifest,"w",encoding="utf-8").write(json.dumps(m, indent=2, sort_keys=True) + "\n")
print("OK: wrote manifest (pre-bundle)")
PY

# Create bundle including manifest (manifest is not part of payload hash)
tar -czf "$bundle" \
  "${PAYLOAD_FILES[@]}" \
  "$manifest"

# Fill bundle sha into manifest (sibling)
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

chmod +x "$F"
echo "✅ rewrote: $F"
echo "Next:"
echo "  ./runtime/bin/release_bundle"
echo "  ./test/86_test_bundle_sha.sh"
