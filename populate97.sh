cat > populate/97_populate_detached_signing.sh <<'SH'
#!/usr/bin/env bash
# Phase 97 POPULATE: detached signing + verification + safe Phase 86
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }
ok(){ echo "OK: $*"; }

[ -d runtime/bin ] || die "missing runtime/bin"
[ -d runtime/schema ] || die "missing runtime/schema"
[ -d test ] || die "missing test"
[ -x runtime/bin/validate_manifest ] || die "missing runtime/bin/validate_manifest"

# --- runtime/bin/sign_detached ---
cat > runtime/bin/sign_detached <<'BASH'
#!/usr/bin/env bash
# Sign a file with RSA private key, output base64 signature.
set -euo pipefail
die(){ echo "ERROR: $*" >&2; exit 1; }

KEY=""
IN=""
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --key) shift; KEY="${1:-}"; shift ;;
    --in)  shift; IN="${1:-}"; shift ;;
    --out) shift; OUT="${1:-}"; shift ;;
    -h|--help)
      echo "usage: sign_detached --key priv.pem --in file --out file.sig.b64" >&2
      exit 2
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

[ -n "$KEY" ] || die "missing --key"
[ -n "$IN" ]  || die "missing --in"
[ -n "$OUT" ] || die "missing --out"
[ -f "$KEY" ] || die "key not found: $KEY"
[ -f "$IN" ]  || die "input not found: $IN"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

openssl dgst -sha256 -sign "$KEY" -out "$tmp" "$IN" >/dev/null 2>&1 || die "openssl sign failed"
base64 -w 0 "$tmp" > "$OUT"
echo "OK: signed: $IN -> $OUT"
BASH
chmod +x runtime/bin/sign_detached
ok "wrote runtime/bin/sign_detached"

# --- runtime/bin/verify_detached ---
cat > runtime/bin/verify_detached <<'BASH'
#!/usr/bin/env bash
# Verify a base64 detached signature for a file with RSA public key.
set -euo pipefail
die(){ echo "ERROR: $*" >&2; exit 1; }

PUB=""
IN=""
SIG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pub) shift; PUB="${1:-}"; shift ;;
    --in)  shift; IN="${1:-}"; shift ;;
    --sig) shift; SIG="${1:-}"; shift ;;
    -h|--help)
      echo "usage: verify_detached --pub pub.pem --in file --sig file.sig.b64" >&2
      exit 2
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

[ -n "$PUB" ] || die "missing --pub"
[ -n "$IN" ]  || die "missing --in"
[ -n "$SIG" ] || die "missing --sig"
[ -f "$PUB" ] || die "pub not found: $PUB"
[ -f "$IN" ]  || die "input not found: $IN"
[ -f "$SIG" ] || die "sig not found: $SIG"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

base64 -d "$SIG" > "$tmp" || die "base64 decode failed"
openssl dgst -sha256 -verify "$PUB" -signature "$tmp" "$IN" >/dev/null 2>&1 || die "signature verify failed"
echo "OK: verified: $IN"
BASH
chmod +x runtime/bin/verify_detached
ok "wrote runtime/bin/verify_detached"

# --- runtime/bin/verify_release_signatures ---
cat > runtime/bin/verify_release_signatures <<'BASH'
#!/usr/bin/env bash
# Verify release manifest + tarball signatures using public key.
set -euo pipefail
die(){ echo "ERROR: $*" >&2; exit 1; }

PUB=""
MANIFEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pub) shift; PUB="${1:-}"; shift ;;
    --manifest) shift; MANIFEST="${1:-}"; shift ;;
    -h|--help)
      echo "usage: verify_release_signatures --pub pub.pem --manifest release_<RID>.json" >&2
      exit 2
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

[ -n "$PUB" ] || die "missing --pub"
[ -n "$MANIFEST" ] || die "missing --manifest"
[ -f "$PUB" ] || die "pub not found: $PUB"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"

bundle="$(python3 - <<'PY' "$MANIFEST"
import json,sys
m=json.load(open(sys.argv[1],"r",encoding="utf-8"))
print(m.get("bundle_path",""))
PY
)"

[ -n "$bundle" ] || die "manifest missing bundle_path"
[ -f "$bundle" ] || die "bundle not found at bundle_path: $bundle"

msig="${MANIFEST}.sig.b64"
bsig="${bundle}.sig.b64"

[ -f "$msig" ] || die "missing manifest signature: $msig"
[ -f "$bsig" ] || die "missing bundle signature: $bsig"

./runtime/bin/verify_detached --pub "$PUB" --in "$MANIFEST" --sig "$msig"
./runtime/bin/verify_detached --pub "$PUB" --in "$bundle" --sig "$bsig"
echo "OK: release signatures verified"
BASH
chmod +x runtime/bin/verify_release_signatures
ok "wrote runtime/bin/verify_release_signatures"

# --- Rewrite runtime/bin/release_bundle to optionally sign ---
# Signing is enabled only if SIGNING_KEY_PATH and SIGNING_PUB_PATH env vars are set (files must exist).
# Outputs .sig.b64 files alongside tarball + manifest.
cat > runtime/bin/release_bundle <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

usage(){
  echo "usage: release_bundle [--release-id RID]" >&2
  exit 2
}

ts=""
while [ $# -gt 0 ]; do
  case "$1" in
    --release-id) shift; ts="${1:-}"; [ -n "$ts" ] || usage; shift ;;
    -h|--help) usage ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage ;;
  esac
done
if [ -z "$ts" ]; then ts="$(date -u +%Y%m%dT%H%M%SZ)"; fi

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
import json, os, platform, subprocess, sys, hashlib

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
    try:
        if not os.path.isdir(".git"):
            return ""
        out = subprocess.check_output(["git","rev-parse","--short","HEAD"], stderr=subprocess.DEVNULL)
        return out.decode("utf-8").strip()
    except Exception:
        return ""

factory_version = os.environ.get("FACTORY_VERSION","").strip() or read_text("runtime/VERSION") or "dev"
runtime_version  = os.environ.get("RUNTIME_VERSION","").strip()  or read_text("runtime/RUNTIME_VERSION") or "dev"

logs_dir="runtime/state/logs"
exec_log=os.path.join(logs_dir, "executions.jsonl")
chain_log=os.path.join(logs_dir, "executions.chain.jsonl")
checkpoint_path=os.path.join(logs_dir, "executions.chain.checkpoint.json")

expected_event_count = count_nonempty_lines(exec_log)
last_event_time_utc  = last_event_time_from_chain(chain_log)

counts = {
    "executions": expected_event_count,
    "chain_lines": count_nonempty_lines(chain_log),
}

checkpoint_id = ""
if os.path.exists(checkpoint_path):
    try:
        checkpoint_id = json.load(open(checkpoint_path, "r", encoding="utf-8")).get("checkpoint_id","") or ""
    except Exception:
        checkpoint_id = ""

doc = {
    "schema_version": 1,

    "factory_version": factory_version,
    "runtime_version": runtime_version,
    "git_commit": get_git_commit(),

    "release_id": ts,
    "created_at_utc": ts,
    "bundle_path": f"runtime/state/releases/release_{ts}.tar.gz",

    # Will be filled after tar is written (in bash)
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
    "system_status_ok": True,

    # Phase 97: signature metadata (empty unless signed)
    "signing_alg": "",
    "signing_pub_fingerprint_sha256": "",
    "bundle_sig_b64_path": "",
    "manifest_sig_b64_path": "",
}

with open(manifest, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, sort_keys=True)
    f.write("\n")
PY

# Build tarball (embed the sibling manifest as a member too)
tar -czf "$bundle" \
  runtime/bin \
  runtime/core \
  runtime/schema \
  runtime/state/logs \
  runtime/state/projections \
  runtime/state/reports \
  "$manifest"

# Compute sha256 and write into sibling manifest (this is now part of release_bundle, not Phase 86)
sha="$(sha256sum "$bundle" | awk '{print $1}')"
python3 - <<'PY' "$manifest" "$sha"
import json, sys, hashlib, os
mp, sha = sys.argv[1], sys.argv[2]
d=json.load(open(mp,"r",encoding="utf-8"))
d["bundle_sha256"]=sha
json.dump(d, open(mp,"w",encoding="utf-8"), indent=2, sort_keys=True)
open(mp,"a",encoding="utf-8").write("\n")
PY

# Optional signing (detached) — enabled only if env vars point to real key files
KEY="${SIGNING_KEY_PATH:-}"
PUB="${SIGNING_PUB_PATH:-}"

if [ -n "$KEY" ] || [ -n "$PUB" ]; then
  [ -f "$KEY" ] || { echo "ERROR: SIGNING_KEY_PATH set but not found: $KEY" >&2; exit 7; }
  [ -f "$PUB" ] || { echo "ERROR: SIGNING_PUB_PATH set but not found: $PUB" >&2; exit 7; }

  msig="${manifest}.sig.b64"
  bsig="${bundle}.sig.b64"

  ./runtime/bin/sign_detached --key "$KEY" --in "$manifest" --out "$msig" >/dev/null
  ./runtime/bin/sign_detached --key "$KEY" --in "$bundle"   --out "$bsig" >/dev/null

  fp="$(sha256sum "$PUB" | awk '{print $1}')"
  python3 - <<'PY' "$manifest" "$fp" "$msig" "$bsig"
import json, sys
mp, fp, msig, bsig = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d=json.load(open(mp,"r",encoding="utf-8"))
d["signing_alg"]="openssl-rsa-sha256"
d["signing_pub_fingerprint_sha256"]=fp
d["manifest_sig_b64_path"]=msig
d["bundle_sig_b64_path"]=bsig
json.dump(d, open(mp,"w",encoding="utf-8"), indent=2, sort_keys=True)
open(mp,"a",encoding="utf-8").write("\n")
PY

  echo "OK: signed release (detached sigs):"
  echo " - $msig"
  echo " - $bsig"
fi

# Validate final manifest
./runtime/bin/validate_manifest "$manifest" --release-id "$ts" >/dev/null

echo "$bundle"
echo "$manifest"
BASH

chmod +x runtime/bin/release_bundle
ok "rewrote runtime/bin/release_bundle (phase 97 signing optional)"

# --- Rewrite test/86_test_bundle_sha.sh to VERIFY-ONLY (never mutate signed manifest) ---
cat > test/86_test_bundle_sha.sh <<'SH86'
#!/usr/bin/env bash
# Phase 86 TEST (hardened for Phase 97): verify sha256 matches manifest; do NOT mutate manifest.
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }

: "${RELEASE_ID:?ERROR: RELEASE_ID not set}"

bundle="runtime/state/releases/release_${RELEASE_ID}.tar.gz"
manifest="runtime/state/releases/release_${RELEASE_ID}.json"

[ -f "$bundle" ] || die "bundle missing: $bundle"
[ -f "$manifest" ] || die "manifest missing: $manifest"

echo "Using bundle:   $bundle"
echo "Using manifest: $manifest"

python3 - <<'PY' "$bundle" "$manifest"
import json, sys, hashlib, tarfile

bundle, manifest = sys.argv[1], sys.argv[2]

def sha256_file(p):
    h=hashlib.sha256()
    with open(p,"rb") as f:
        for b in iter(lambda: f.read(1024*1024), b""):
            h.update(b)
    return h.hexdigest()

m=json.load(open(manifest,"r",encoding="utf-8"))
exp=m.get("bundle_sha256","")
act=sha256_file(bundle)

if not exp:
    raise SystemExit("FAIL: manifest bundle_sha256 is empty (should be filled by release_bundle now)")
if exp != act:
    raise SystemExit(f"FAIL: bundle sha mismatch: expected={exp} actual={act}")

# sanity: embedded manifest exists
with tarfile.open(bundle, "r:gz") as tf:
    names=set(tf.getnames())
if m.get("bundle_path","").endswith(".tar.gz"):
    embedded = manifest  # we store the sibling manifest file itself into the tar
    # tar stores relative paths; manifest is runtime/state/releases/release_<RID>.json
    if embedded not in names:
        raise SystemExit(f"FAIL: embedded manifest missing in tarball: {embedded}")

print("OK: bundle sha verified and embedded manifest present")
PY

echo "✅ Phase 86 TEST PASS (bundle sha verified; no mutation)"
SH86
chmod +x test/86_test_bundle_sha.sh
ok "rewrote test/86_test_bundle_sha.sh (verify-only)"

echo "✅ Phase 97 POPULATE PASS"
SH

chmod +x populate/97_populate_detached_signing.sh
