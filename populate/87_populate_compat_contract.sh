#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

cat > note/PHASE_87_COMPAT_CONTRACT.md <<'MD'
# PHASE 87 — Compatibility Contract

Problem:
- A release without a declared runtime environment is archival, not portable.
- We need a compatibility contract: “this release can be restored and replayed on X”.

Solution:
- Add `compat` fields to the release manifest:
  - os, arch, python version, python implementation, machine
- Add `schema_version` to manifest for forward evolution.

Test:
- Build a release.
- Assert manifest contains compat + schema_version.
- Assert compat matches current host (os/arch/python/impl/machine).
MD

F="runtime/bin/release_bundle"
[ -f "$F" ] || { echo "❌ missing $F" >&2; exit 1; }
B="${F}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp -f "$F" "$B"
echo "✅ backup: $B"

# Rewrite release_bundle by extending manifest generation (keep your current behavior intact).
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

python3 - <<'PY' "$ts" "$bundle" "$manifest"
import json, os, platform, sys, hashlib
from datetime import datetime, timezone

ts, bundle, manifest = sys.argv[1], sys.argv[2], sys.argv[3]

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

compat = {
  "os": platform.system(),
  "arch": platform.machine(),
  "python": platform.python_version(),
  "impl": platform.python_implementation(),
  "machine": platform.platform(),
}

m={
  "schema_version": 1,
  "created_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "release_id": ts,

  # Expectations used by restore/replay proof (Phase 84)
  "expected_event_count": chain_lines,
  "expected_last_event_time_utc": le,

  "counts": {
    "executions_jsonl_lines": count_nonempty_lines("runtime/state/logs/executions.jsonl"),
    "chain_jsonl_lines": chain_lines
  },
  "checkpoint": ck,
  "last_event_time_utc": le,
  "system_status_ok": ss_ok,

  # NEW: compatibility contract
  "compat": compat,

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
  runtime/state/projections/system_status.json \
  runtime/state/projections/diagnose.json \
  runtime/state/reports/diagnose.txt \
  runtime/state/reports/diagnose.json \
  runtime/state/projections \
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

# Fill bundle sha into manifest (sibling)
python3 - <<'PY' "$bundle" "$manifest"
import json, hashlib, sys
bundle, manifest = sys.argv[1], sys.argv[2]
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
echo "✅ rewrote: runtime/bin/release_bundle"

# Write the test
cat > test/87_test_compat_contract.sh <<'SH'
#!/usr/bin/env bash
# Phase 87 TEST: manifest includes compat contract and matches current host
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }

./runtime/bin/release_bundle >/dev/null

bundle="$(ls -1t runtime/state/releases/release_*.tar.gz 2>/dev/null | head -n 1 || true)"
manifest="$(ls -1t runtime/state/releases/release_*.json 2>/dev/null | head -n 1 || true)"
[ -n "$bundle" ] || die "no release tarball found"
[ -n "$manifest" ] || die "no release manifest found"
[ -f "$bundle" ] || die "bundle not a file: $bundle"
[ -f "$manifest" ] || die "manifest not a file: $manifest"

echo "Using bundle:   $bundle"
echo "Using manifest: $manifest"

python3 - <<'PY' "$manifest"
import json, platform, sys

m=json.load(open(sys.argv[1],"r",encoding="utf-8"))

# required fields
assert isinstance(m.get("schema_version"), int) and m["schema_version"] >= 1, "missing/invalid schema_version"
c=m.get("compat")
assert isinstance(c, dict), "missing compat object"

required=("os","arch","python","impl","machine")
for k in required:
    assert isinstance(c.get(k), str) and c[k], f"compat missing {k}"

host={
  "os": platform.system(),
  "arch": platform.machine(),
  "python": platform.python_version(),
  "impl": platform.python_implementation(),
  "machine": platform.platform(),
}

# strict equality for now (you can relax later if needed)
mism=[]
for k in required:
    if c.get(k) != host.get(k):
        mism.append((k, c.get(k), host.get(k)))

if mism:
    print("COMPAT_MISMATCH:")
    for k, exp, act in mism:
        print(f" - {k}: manifest={exp!r} host={act!r}")
    raise SystemExit(2)

print("OK: compat matches host")
PY

echo "✅ Phase 87 TEST PASS (compat contract)"
SH

chmod +x test/87_test_compat_contract.sh

echo "OK: Phase 87 POPULATE wrote:"
echo " - note/PHASE_87_COMPAT_CONTRACT.md"
echo " - runtime/bin/release_bundle (rewritten with compat)"
echo " - test/87_test_compat_contract.sh"
