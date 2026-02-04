#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
ok(){ echo "OK: $*"; }

# Must run from repo root
[ -d runtime ] || die "missing ./runtime (run from repo root)"
[ -d test ] || die "missing ./test (run from repo root)"

mkdir -p .tmp
backup_dir=".tmp/phase93_patch_backup_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir"

backup(){
  local f="$1"
  if [ -f "$f" ]; then
    mkdir -p "$backup_dir/$(dirname "$f")"
    cp -a "$f" "$backup_dir/$f"
    ok "backup: $f -> $backup_dir/$f"
  fi
}

# Back up files we will modify/create
backup "test/83_test_release_bundle.sh"
backup "test/86_test_bundle_sha.sh"
backup "runtime/bin/validate_manifest"
backup "runtime/schema/release_manifest.schema.json"
if [ -f "runtime/bin/validate_manifest.sh" ]; then
  backup "runtime/bin/validate_manifest.sh"
fi

# Ensure dirs exist
mkdir -p runtime/schema runtime/bin

# --- Write schema ---
cat > runtime/schema/release_manifest.schema.json <<'JSON'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "runtime/schema/release_manifest.schema.json",
  "title": "Release Manifest Schema",
  "type": "object",
  "additionalProperties": true,
  "required": [
    "schema_version",
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
    "expected_last_event_time_utc": { "type": "string", "minLength": 1 },
    "last_event_time_utc": { "type": "string", "minLength": 1 }
  }
}
JSON
ok "wrote runtime/schema/release_manifest.schema.json"

# --- Write validator runtime/bin/validate_manifest (no .sh) ---
cat > runtime/bin/validate_manifest <<'SH'
#!/usr/bin/env bash
set -euo pipefail

usage(){
  echo "usage: validate_manifest <manifest.json> [--release-id RID]" >&2
  exit 2
}

[ $# -ge 1 ] || usage
manifest="$1"; shift

rid=""
while [ $# -gt 0 ]; do
  case "$1" in
    --release-id) shift; rid="${1:-}"; [ -n "$rid" ] || usage; shift ;;
    -h|--help) usage ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage ;;
  esac
done

python3 - <<'PY' "$manifest" "$rid"
import json, os, re, sys

manifest_path = sys.argv[1]
rid = sys.argv[2] or None
schema_path = os.path.join("runtime", "schema", "release_manifest.schema.json")

def fail(msg):
    raise SystemExit("ERROR: " + msg)

def load_json(p):
    try:
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        fail(f"missing file: {p}")
    except json.JSONDecodeError as e:
        fail(f"invalid JSON in {p}: {e}")

schema = load_json(schema_path)
doc = load_json(manifest_path)

def check_type(v, t):
    if t == "object": return isinstance(v, dict)
    if t == "string": return isinstance(v, str)
    if t == "integer": return isinstance(v, int) and not isinstance(v, bool)
    if t == "boolean": return isinstance(v, bool)
    return False

def validate_obj(obj, sch, path="$"):
    if sch.get("type") != "object":
        fail(f"{path}: schema type must be object")
    if not isinstance(obj, dict):
        fail(f"{path}: expected object")

    for k in sch.get("required", []):
        if k not in obj:
            fail(f"{path}: missing required field: {k}")

    props = sch.get("properties", {})
    for k, ps in props.items():
        if k not in obj:
            continue
        v = obj[k]
        t = ps.get("type")
        if t and not check_type(v, t):
            fail(f"{path}.{k}: wrong type (expected {t})")

        if t == "integer":
            mn = ps.get("minimum")
            if mn is not None and v < mn:
                fail(f"{path}.{k}: must be >= {mn}")

        if t == "string":
            mnlen = ps.get("minLength")
            if mnlen is not None and len(v) < mnlen:
                fail(f"{path}.{k}: minLength {mnlen}")
            pat = ps.get("pattern")
            if pat is not None and not re.match(pat, v):
                fail(f"{path}.{k}: pattern mismatch")

        if t == "object":
            validate_obj(v, ps, f"{path}.{k}")

validate_obj(doc, schema, "$")

# Cross-field invariants
if rid is not None and doc.get("release_id") != rid:
    fail(f"release_id mismatch: manifest={doc.get('release_id')!r} expected={rid!r}")

expected_bundle = f"runtime/state/releases/release_{doc['release_id']}.tar.gz"
if doc.get("bundle_path") != expected_bundle:
    fail(f"bundle_path mismatch: {doc.get('bundle_path')!r} expected={expected_bundle!r}")

c = doc["compat"]
for k in ("os", "arch", "impl"):
    if c.get(k) != c.get(k, "").lower():
        fail(f"compat.{k} must be lowercase")

print("OK: manifest validated against schema + invariants")
PY
SH

# Fix CRLF if any and chmod +x
sed -i 's/\r$//' runtime/bin/validate_manifest
chmod +x runtime/bin/validate_manifest
ok "wrote + chmod runtime/bin/validate_manifest"

# If user has validate_manifest.sh with CRLF, normalize it too (optional hygiene)
if [ -f runtime/bin/validate_manifest.sh ]; then
  sed -i 's/\r$//' runtime/bin/validate_manifest.sh
  chmod +x runtime/bin/validate_manifest.sh || true
  ok "normalized CRLF on runtime/bin/validate_manifest.sh"
fi

# --- Patch test/83 to call validator (replace entire manifest python block) ---
# We replace everything between:
#   python3 - <<'PY' "$manifest"
# and the following line that is exactly: PY
# with a call to validate_manifest.
if grep -q "python3 - <<'PY' \"\$manifest\"" test/83_test_release_bundle.sh; then
  awk '
    BEGIN{inblock=0}
    {
      if($0 ~ /python3 - <<'\''PY'\'' "\$manifest"/){
        print "./runtime/bin/validate_manifest \"$manifest\" --release-id \"$RELEASE_ID\" >/dev/null"
        print "echo \"OK: manifest validated (schema + invariants)\""
        inblock=1
        next
      }
      if(inblock==1){
        if($0 ~ /^PY$/){ inblock=0 }
        next
      }
      print
    }
  ' test/83_test_release_bundle.sh > .tmp/83.tmp && mv .tmp/83.tmp test/83_test_release_bundle.sh
  ok "patched test/83_test_release_bundle.sh to use validate_manifest"
else
  ok "test/83_test_release_bundle.sh: no manifest heredoc found (no change)"
fi
chmod +x test/83_test_release_bundle.sh

# --- Patch test/86 to re-validate after sha fill ---
# Add validator call just before the final ✅ echo if not already present.
if ! grep -q "validate_manifest" test/86_test_bundle_sha.sh; then
  awk '
    {
      if($0 ~ /^echo "✅ Phase 86 TEST PASS/){
        print "./runtime/bin/validate_manifest \"$manifest\" --release-id \"$RELEASE_ID\" >/dev/null"
        print "echo \"OK: manifest re-validated after sha fill\""
      }
      print
    }
  ' test/86_test_bundle_sha.sh > .tmp/86.tmp && mv .tmp/86.tmp test/86_test_bundle_sha.sh
  ok "patched test/86_test_bundle_sha.sh to re-validate manifest"
else
  ok "test/86_test_bundle_sha.sh already calls validate_manifest"
fi
chmod +x test/86_test_bundle_sha.sh

ok "Phase 93 patch complete."
echo "Next run:"
echo '  ./test/90_test_all_deterministic.sh'
echo '  ./runtime/bin/validate_manifest runtime/state/releases/release_<RID>.json --release-id <RID>'
echo
echo "Backups in: $backup_dir"
