#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
ok(){ echo "OK: $*"; }

[ -d runtime ] || die "missing ./runtime"
[ -d test ] || die "missing ./test"
mkdir -p .tmp

backup_dir=".tmp/phase94_patch_backup_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir"

backup(){
  local f="$1"
  if [ -f "$f" ]; then
    mkdir -p "$backup_dir/$(dirname "$f")"
    cp -a "$f" "$backup_dir/$f"
    ok "backup: $f -> $backup_dir/$f"
  fi
}

backup runtime/bin/release_bundle
backup runtime/schema/release_manifest.schema.json
backup runtime/bin/validate_manifest

# --- 1) Rewrite runtime/bin/release_bundle to emit version + provenance ---
cat > runtime/bin/release_bundle <<'SH'
#!/usr/bin/env bash
set -euo pipefail

usage(){
  echo "usage: release_bundle [--release-id RID]" >&2
  exit 2
}

# Optional deterministic release id
ts=""
while [ $# -gt 0 ]; do
  case "$1" in
    --release-id) shift; ts="${1:-}"; [ -n "$ts" ] || usage; shift ;;
    -h|--help) usage ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage ;;
  esac
done

if [ -z "$ts" ]; then
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
fi

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
import json, os, platform, subprocess, sys
from datetime import datetime, timezone

ts, bundle, manifest = sys.argv[1], sys.argv[2], sys.argv[3]

def read_text(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read().strip()
    except FileNotFoundError:
        return ""

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
    return obj.get("event_time_utc") or obj.get("event_time") or obj.get("timestamp_utc") or ""

def get_git_commit():
    # Empty string allowed when not a git repo or git not available.
    try:
        if not os.path.isdir(".git"):
            return ""
        out = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], stderr=subprocess.DEVNULL)
        return out.decode("utf-8").strip()
    except Exception:
        return ""

# Versions: prefer env overrides, then VERSION files, else "dev"
factory_version = os.environ.get("FACTORY_VERSION","").strip() or read_text("runtime/VERSION") or "dev"
runtime_version  = os.environ.get("RUNTIME_VERSION","").strip()  or read_text("runtime/RUNTIME_VERSION") or "dev"

logs_dir="runtime/state/logs"
exec_log=os.path.join(logs_dir, "executions.jsonl")
chain_log=os.path.join(logs_dir, "executions.chain.jsonl")
checkpoint_path=os.path.join(logs_dir, "executions.chain.checkpoint.json")

expected_event_count = count_nonempty_lines(exec_log)
last_event_time_utc  = last_event_time_from_chain(chain_log)

# counts object (expand later if needed)
counts = {
    "executions": expected_event_count,
    "chain_lines": count_nonempty_lines(chain_log),
}

# checkpoint id (string)
checkpoint_id = ""
if os.path.exists(checkpoint_path):
    try:
        checkpoint_id = json.load(open(checkpoint_path, "r", encoding="utf-8")).get("checkpoint_id","") or ""
    except Exception:
        checkpoint_id = ""

created_at_utc = ts  # already UTC Z-format

doc = {
    "schema_version": 1,

    # Phase 94: version + provenance
    "factory_version": factory_version,
    "runtime_version": runtime_version,
    "git_commit": get_git_commit(),

    "release_id": ts,
    "created_at_utc": created_at_utc,
    "bundle_path": f"runtime/state/releases/release_{ts}.tar.gz",

    # Phase 86 will fill/verify this later; allow empty pre-86
    "bundle_sha256": "",

    "compat": {
        "os": platform.system().lower(),
        "arch": platform.machine().lower(),
        "python": platform.python_version(),
        "impl": platform.python_implementation().lower(),
        "machine": platform.platform(),
    },

    "checkpoint": checkpoint_id or "unknown",
    "counts": counts,

    "expected_event_count": expected_event_count,
    "expected_last_event_time_utc": last_event_time_utc or "",
    "last_event_time_utc": last_event_time_utc or "",

    # status projection
    "system_status_ok": True,
}

with open(manifest, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, sort_keys=True)
    f.write("\n")
PY

# Build tarball (include runtime/ tree and embed the sibling manifest inside)
tar -czf "$bundle" \
  runtime/bin \
  runtime/core \
  runtime/schema \
  runtime/state/logs \
  runtime/state/projections \
  runtime/state/reports \
  "$manifest"

echo "$bundle"
echo "$manifest"
SH

sed -i 's/\r$//' runtime/bin/release_bundle
chmod +x runtime/bin/release_bundle
ok "rewrote runtime/bin/release_bundle (phase 94 fields added)"

# --- 2) Update schema: require factory_version/runtime_version/git_commit ---
# We rewrite schema fully to avoid partial edits.
cat > runtime/schema/release_manifest.schema.json <<'JSON'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "runtime/schema/release_manifest.schema.json",
  "title": "Release Manifest Schema",
  "type": "object",
  "additionalProperties": true,
  "required": [
    "schema_version",

    "factory_version",
    "runtime_version",
    "git_commit",

    "release_id",
    "created_at_utc",
    "bundle_path",
    "bundle_sha256",
    "compat",
    "checkpoint",
    "counts",
    "expected_event_count",
    "expected_last_event_time_utc",
    "last_event_time_utc",
    "system_status_ok"
  ],
  "properties": {
    "schema_version": { "type": "integer", "minimum": 1 },

    "factory_version": { "type": "string", "minLength": 1 },
    "runtime_version": { "type": "string", "minLength": 1 },
    "git_commit": { "type": "string" , "pattern": "^[0-9a-f]{0,64}$" },

    "release_id": { "type": "string", "pattern": "^[0-9]{8}T[0-9]{6}Z$" },
    "created_at_utc": { "type": "string", "pattern": "^[0-9]{8}T[0-9]{6}Z$" },
    "bundle_path": { "type": "string", "pattern": "^runtime/state/releases/release_[0-9]{8}T[0-9]{6}Z\\.tar\\.gz$" },
    "bundle_sha256": { "type": "string", "pattern": "^[a-f0-9]{64}$|^$" },
    "checkpoint": { "type": "string", "minLength": 1 },
    "system_status_ok": { "type": "boolean" },

    "compat": {
      "type": "object",
      "additionalProperties": true,
      "required": ["os", "arch", "python", "impl", "machine"],
      "properties": {
        "os": { "type": "string", "pattern": "^[a-z0-9._-]+$" },
        "arch": { "type": "string", "pattern": "^[a-z0-9._-]+$" },
        "python": { "type": "string", "minLength": 1 },
        "impl": { "type": "string", "pattern": "^[a-z0-9._-]+$" },
        "machine": { "type": "string", "minLength": 1 }
      }
    },

    "counts": {
      "type": "object",
      "additionalProperties": true,
      "required": ["executions", "chain_lines"],
      "properties": {
        "executions": { "type": "integer", "minimum": 0 },
        "chain_lines": { "type": "integer", "minimum": 0 }
      }
    },

    "expected_event_count": { "type": "integer", "minimum": 0 },
    "expected_last_event_time_utc": { "type": "string", "minLength": 0 },
    "last_event_time_utc": { "type": "string", "minLength": 0 }
  }
}
JSON
ok "updated runtime/schema/release_manifest.schema.json (phase 94 required fields)"

# --- 3) Update validator: enforce versions non-empty and git pattern already enforced by schema ---
# Minimal change: validator already loads schema and enforces required+pattern.
# We just ensure it strips CRLF.
sed -i 's/\r$//' runtime/bin/validate_manifest
chmod +x runtime/bin/validate_manifest
ok "validated runtime/bin/validate_manifest (no logic change needed)"

ok "Phase 94 patch complete."
echo "Next run:"
echo "  ./test/90_test_all_deterministic.sh"
echo "Optional:"
echo "  FACTORY_VERSION=1.0.0 RUNTIME_VERSION=1.0.0 ./test/90_test_all_deterministic.sh"
echo
echo "Backups in: $backup_dir"
