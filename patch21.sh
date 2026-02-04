#!/usr/bin/env bash
set -euo pipefail

# patch.sh — Phase 98: signing contract becomes first-class (schema + invariants + tests)
# Rules obeyed:
# - No guessing: inspect files and rewrite only if proven outdated.
# - No release minting in tests: Phase 98 test uses already-minted artifacts only.
# - Rewrite (not patch) when outdated.
# - Run proof chain at end.

ROOT="$(pwd)"

die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo "==> $*" >&2; }

require_file(){
  [[ -f "$1" ]] || die "Missing required file: $1"
}

# --- Preflight: root sanity
require_file "test/90_test_all_deterministic.sh"
require_file "test/97_test_detached_signatures.sh"
require_file "test/91_test_no_release_minting.sh"

require_file "runtime/bin/validate_manifest"
require_file "runtime/schema/release_manifest.schema.json"

# --- Minimal JSON helpers (no jq dependency)
pyjson_get() {
  # usage: pyjson_get <file> <python_expr_returning_bool_or_value>
  python3 - "$1" <<'PY'
import json,sys
path=sys.argv[1]
with open(path,'r',encoding='utf-8') as f:
    obj=json.load(f)
# expression is provided via stdin? no, we embed in script caller by editing this function if needed
PY
}

schema_has_signing_fields() {
  python3 - "$1" <<'PY'
import json,sys
p=sys.argv[1]
s=json.load(open(p,'r',encoding='utf-8'))

def has_prop(name):
    # tolerate schemas that place properties under top-level or under definitions
    props=s.get("properties") or {}
    return name in props

needed = [
  "signing_alg",
  "signing_pub_fingerprint_sha256",
  "manifest_sig_b64_path",
  "bundle_sig_b64_path",
]
missing=[k for k in needed if not has_prop(k)]
print("OK" if not missing else "MISSING:" + ",".join(missing))
PY
}

validator_has_signing_invariants() {
  # Heuristic inspection: look for the invariant keywords in validate_manifest
  # This is "proof via inspection", not assumption.
  local f="$1"
  if grep -q "signing_pub_fingerprint_sha256" "$f" \
    && grep -q "manifest_sig_b64_path" "$f" \
    && grep -q "bundle_sig_b64_path" "$f" \
    && grep -q "signing_alg" "$f"; then
    echo "OK"
  else
    echo "MISSING"
  fi
}

backup(){
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp -a "$f" "$f.bak.$(date -u +%Y%m%dT%H%M%SZ)"
}

# --- Inspect: schema
note "Inspecting schema for Phase 98 signing fields…"
SCHEMA_STATUS="$(schema_has_signing_fields runtime/schema/release_manifest.schema.json)"
note "Schema inspection: $SCHEMA_STATUS"

if [[ "$SCHEMA_STATUS" == MISSING:* ]]; then
  note "Schema proven outdated -> rewriting runtime/schema/release_manifest.schema.json"
  backup "runtime/schema/release_manifest.schema.json"

  # Rewrite: keep it permissive enough not to break unknown/legacy fields,
  # but formally define signing fields and their formats.
  cat > runtime/schema/release_manifest.schema.json <<'JSON'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "release_manifest",
  "type": "object",
  "additionalProperties": true,

  "properties": {
    "release_id": { "type": "string", "minLength": 1 },
    "created_at_utc": { "type": "string", "minLength": 1 },

    "bundle_path": { "type": "string", "minLength": 1 },
    "bundle_sha256": { "type": "string", "pattern": "^[a-f0-9]{64}$" },

    "compat": {
      "type": "object",
      "additionalProperties": true,
      "properties": {
        "os": { "type": "string" },
        "arch": { "type": "string" },
        "python": { "type": "string" },
        "impl": { "type": "string" },
        "machine": { "type": "string" }
      }
    },

    "expectations": {
      "type": "object",
      "additionalProperties": true,
      "properties": {
        "expected_event_count": { "type": "integer", "minimum": 0 },
        "expected_last_event_time_utc": { "type": "string", "minLength": 1 }
      }
    },

    "signing_alg": {
      "type": "string",
      "enum": ["rsa-sha256-b64"]
    },
    "signing_pub_fingerprint_sha256": {
      "type": "string",
      "pattern": "^[a-f0-9]{64}$"
    },
    "manifest_sig_b64_path": {
      "type": "string",
      "minLength": 1
    },
    "bundle_sig_b64_path": {
      "type": "string",
      "minLength": 1
    }
  }
}
JSON
else
  note "Schema already contains signing fields -> no rewrite"
fi

# --- Inspect: validator invariants
note "Inspecting validator for Phase 98 signing invariants…"
VAL_STATUS="$(validator_has_signing_invariants runtime/bin/validate_manifest)"
note "Validator inspection: $VAL_STATUS"

if [[ "$VAL_STATUS" != "OK" ]]; then
  note "Validator proven outdated -> rewriting runtime/bin/validate_manifest"
  backup "runtime/bin/validate_manifest"

  # Rewrite validate_manifest as a self-contained python tool (no external deps).
  # Keeps CLI stable: validate_manifest --manifest <path>
  cat > runtime/bin/validate_manifest <<'PY'
#!/usr/bin/env python3
import argparse, json, os, re, sys

HEX64 = re.compile(r"^[a-f0-9]{64}$")
REL_SAFE = re.compile(r"^[A-Za-z0-9._-]+$")  # basename-only, no slashes

def fail(msg: str) -> int:
    print(f"INVALID: {msg}", file=sys.stderr)
    return 1

def ok(msg: str="OK") -> int:
    print(msg)
    return 0

def is_relative_sibling_path(p: str) -> bool:
    # Strict: basename only (no dirs), prevents arbitrary paths.
    return bool(REL_SAFE.match(p))

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    args = ap.parse_args()

    mpath = args.manifest
    if not os.path.isfile(mpath):
        return fail(f"manifest not found: {mpath}")

    try:
        with open(mpath, "r", encoding="utf-8") as f:
            m = json.load(f)
    except Exception as e:
        return fail(f"manifest not valid json: {e}")

    # Baseline invariants (minimal, stable)
    for k in ("release_id", "bundle_path", "bundle_sha256"):
        if k not in m:
            return fail(f"missing required field: {k}")
    if not isinstance(m["release_id"], str) or not m["release_id"].strip():
        return fail("release_id must be non-empty string")
    if not isinstance(m["bundle_path"], str) or not m["bundle_path"].strip():
        return fail("bundle_path must be non-empty string")
    if not isinstance(m["bundle_sha256"], str) or not HEX64.match(m["bundle_sha256"]):
        return fail("bundle_sha256 must be 64-char lowercase hex")

    # Phase 98 signing invariants (policy-driven)
    signing_fields = (
        "signing_alg",
        "signing_pub_fingerprint_sha256",
        "manifest_sig_b64_path",
        "bundle_sig_b64_path",
    )
    present = [k for k in signing_fields if k in m and m[k] is not None]

    if present and len(present) != len(signing_fields):
        missing = [k for k in signing_fields if k not in m or m[k] is None]
        return fail(f"partial signing metadata: missing {','.join(missing)}")

    if len(present) == len(signing_fields):
        # Alg
        if m["signing_alg"] != "rsa-sha256-b64":
            return fail("signing_alg must be rsa-sha256-b64")

        # Fingerprint
        fp = m["signing_pub_fingerprint_sha256"]
        if not isinstance(fp, str) or not HEX64.match(fp):
            return fail("signing_pub_fingerprint_sha256 must be 64-char lowercase hex")

        # Paths must be safe siblings (no arbitrary paths)
        man_sig = m["manifest_sig_b64_path"]
        bun_sig = m["bundle_sig_b64_path"]
        if not isinstance(man_sig, str) or not is_relative_sibling_path(man_sig):
            return fail("manifest_sig_b64_path must be a safe sibling basename")
        if not isinstance(bun_sig, str) or not is_relative_sibling_path(bun_sig):
            return fail("bundle_sig_b64_path must be a safe sibling basename")

        # Strong naming expectations: signatures should look like siblings of targets
        # (We don't assume exact bundle filename, but enforce .sig.b64 suffix.)
        if not man_sig.endswith(".sig.b64"):
            return fail("manifest_sig_b64_path must end with .sig.b64")
        if not bun_sig.endswith(".sig.b64"):
            return fail("bundle_sig_b64_path must end with .sig.b64")

        # Optional existence check (strict-but-local): if signature paths declared, they should exist.
        # They are expected to be siblings of the manifest file.
        mdir = os.path.dirname(os.path.abspath(mpath))
        if not os.path.isfile(os.path.join(mdir, man_sig)):
            return fail(f"declared manifest signature missing: {man_sig}")
        if not os.path.isfile(os.path.join(mdir, bun_sig)):
            return fail(f"declared bundle signature missing: {bun_sig}")

    return ok("VALID")

if __name__ == "__main__":
    raise SystemExit(main())
PY
  chmod +x runtime/bin/validate_manifest
else
  note "Validator already has signing invariant keywords -> no rewrite"
fi

# --- Add Phase 98 test (deterministic, no minting)
note "Installing Phase 98 test: test/98_test_manifest_signing_invariants.sh"
backup "test/98_test_manifest_signing_invariants.sh"

cat > test/98_test_manifest_signing_invariants.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

# Phase 98: manifest signing invariants
# MUST NOT MINT RELEASES. Operates only on already-minted artifacts.
# Uses Phase 90 minted release and performs mutations ONLY on temp copies.

die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo "==> $*" >&2; }

RID="${RELEASE_ID:-}"
RELEASE_DIR="runtime/state/releases"

[[ -d "$RELEASE_DIR" ]] || die "missing $RELEASE_DIR (run Phase 90 chain first)"

# Prefer RELEASE_ID if provided; else pick newest manifest.
pick_manifest() {
  if [[ -n "$RID" && -f "$RELEASE_DIR/release_${RID}.json" ]]; then
    echo "$RELEASE_DIR/release_${RID}.json"
    return 0
  fi
  ls -1t "$RELEASE_DIR"/release_*.json 2>/dev/null | head -n1
}

MANIFEST="$(pick_manifest || true)"
[[ -n "${MANIFEST:-}" && -f "$MANIFEST" ]] || die "no release manifest found in $RELEASE_DIR"

note "Using manifest: $MANIFEST"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp -a "$MANIFEST" "$TMP/manifest.json"

python3 - "$TMP/manifest.json" <<'PY'
import json,sys
p=sys.argv[1]
m=json.load(open(p,'r',encoding='utf-8'))
# Ensure baseline fields exist for the validator
for k in ("release_id","bundle_path","bundle_sha256"):
    if k not in m:
        raise SystemExit(f"baseline missing {k}, cannot test signing invariants")
print("baseline ok")
PY

# Helper to write mutated variants
mutate() {
  local in="$1"
  local out="$2"
  python3 - "$in" "$out" <<'PY'
import json,sys,copy
inp, outp = sys.argv[1], sys.argv[2]
m=json.load(open(inp,'r',encoding='utf-8'))
m2=copy.deepcopy(m)

mode=os.environ.get("MUT_MODE","")
if mode=="ALG_ONLY":
    m2["signing_alg"]="rsa-sha256-b64"
elif mode=="BAD_FP":
    m2["signing_alg"]="rsa-sha256-b64"
    m2["signing_pub_fingerprint_sha256"]="abc123"  # invalid
    m2["manifest_sig_b64_path"]="manifest.sig.b64"
    m2["bundle_sig_b64_path"]="bundle.sig.b64"
elif mode=="BAD_PATH":
    m2["signing_alg"]="rsa-sha256-b64"
    m2["signing_pub_fingerprint_sha256"]="0"*64
    m2["manifest_sig_b64_path"]="../escape.sig.b64"  # invalid
    m2["bundle_sig_b64_path"]="bundle.sig.b64"
elif mode=="VALID":
    m2["signing_alg"]="rsa-sha256-b64"
    m2["signing_pub_fingerprint_sha256"]="0"*64
    m2["manifest_sig_b64_path"]="manifest.sig.b64"
    m2["bundle_sig_b64_path"]="bundle.sig.b64"
else:
    raise SystemExit("unknown MUT_MODE")
json.dump(m2, open(outp,'w',encoding='utf-8'), indent=2, sort_keys=True)
PY
}

expect_fail() {
  local file="$1"
  if runtime/bin/validate_manifest --manifest "$file" >/dev/null 2>&1; then
    die "Expected FAIL but got PASS for $file"
  fi
}

expect_pass() {
  local file="$1"
  runtime/bin/validate_manifest --manifest "$file" >/dev/null
}

# Case 1: partial signing fields -> fail
note "Case 1: ALG_ONLY -> must fail"
export MUT_MODE="ALG_ONLY"
mutate "$TMP/manifest.json" "$TMP/alg_only.json"
expect_fail "$TMP/alg_only.json"

# Case 2: bad fingerprint -> fail
note "Case 2: BAD_FP -> must fail"
export MUT_MODE="BAD_FP"
mutate "$TMP/manifest.json" "$TMP/bad_fp.json"
# create declared sig files so failure is only fingerprint
touch "$TMP/manifest.sig.b64" "$TMP/bundle.sig.b64"
expect_fail "$TMP/bad_fp.json"

# Case 3: bad path traversal -> fail
note "Case 3: BAD_PATH -> must fail"
export MUT_MODE="BAD_PATH"
mutate "$TMP/manifest.json" "$TMP/bad_path.json"
touch "$TMP/bundle.sig.b64"
expect_fail "$TMP/bad_path.json"

# Case 4: valid signing metadata + files -> pass
note "Case 4: VALID -> must pass"
export MUT_MODE="VALID"
mutate "$TMP/manifest.json" "$TMP/valid.json"
touch "$TMP/manifest.sig.b64" "$TMP/bundle.sig.b64"
expect_pass "$TMP/valid.json"

note "✅ Phase 98 signing invariants test PASS"
SH
chmod +x test/98_test_manifest_signing_invariants.sh

# --- Wire Phase 98 into deterministic chain (ONLY if chain script exists and doesn't already include it)
CHAIN="test/90_test_all_deterministic.sh"
if grep -q "98_test_manifest_signing_invariants" "$CHAIN"; then
  note "Phase 98 already wired into $CHAIN -> no rewrite"
else
  note "Wiring Phase 98 into $CHAIN (rewrite-if-needed via safe append)"
  backup "$CHAIN"
  # Append in a deterministic place: end of chain, after 97 ideally.
  # We do not assume internal layout; we append a block guarded by a marker.
  cat >> "$CHAIN" <<'APPEND'

# --- Phase 98: signing contract invariants (no minting)
./test/98_test_manifest_signing_invariants.sh
APPEND
fi

# --- Final proof run (authoritative)
note "Running golden proof chain (deterministic) after patch…"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh
./test/97_test_detached_signatures.sh
./test/91_test_no_release_minting.sh

note "✅ patch.sh complete: Phase 98 contract + tests installed and proof chain PASS"
