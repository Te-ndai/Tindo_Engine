#!/usr/bin/env bash
set -euo pipefail

# patch22.sh — Fix validate_manifest CLI compatibility + remove zero-arg invocations
# - Inspects filenames + contents before rewriting
# - Restores backward-compatible CLI:
#     ./runtime/bin/validate_manifest <manifest.json> [--release-id RID]
#   while ALSO supporting:
#     ./runtime/bin/validate_manifest --manifest <manifest.json>
# - Removes any accidental lines that invoke validate_manifest with NO args
# - Updates Phase 98 test to call positional (consistent with repo)
# - Runs golden proof chain at end

note(){ echo "==> $*" >&2; }
die(){ echo "ERROR: $*" >&2; exit 1; }

backup(){
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp -a "$f" "$f.bak.$(date -u +%Y%m%dT%H%M%SZ)"
}

require_file(){
  [[ -f "$1" ]] || die "Missing required file: $1"
}

# --- Preflight: must be run from repo root
require_file "test/90_test_all_deterministic.sh"
require_file "test/97_test_detached_signatures.sh"
require_file "test/91_test_no_release_minting.sh"
require_file "runtime/bin/validate_manifest"
require_file "runtime/schema/release_manifest.schema.json"

note "Inspecting validate_manifest CLI shape…"
# If it mentions argparse requiring --manifest, it's the incompatible version.
if grep -q "add_argument(\"--manifest\"" runtime/bin/validate_manifest; then
  VM_MODE="ARGPARSE_STRICT"
else
  VM_MODE="LEGACY_OR_COMPAT"
fi
note "validate_manifest mode detected: $VM_MODE"

note "Scanning for ZERO-ARG invocations of validate_manifest (this caused your crash)…"
# Match lines that end right after validate_manifest, possibly with ./ prefix and whitespace
# Exclude grep results from backups/tmp by ignoring *.bak.* and .tmp/ if you use that.
ZERO_CALLS="$(grep -RIn --exclude='*.bak.*' --exclude-dir='.tmp' --exclude-dir='.git' \
  -E '^[[:space:]]*\.?/runtime/bin/validate_manifest[[:space:]]*$' . || true)"

if [[ -n "$ZERO_CALLS" ]]; then
  note "Found zero-arg calls (will remove):"
  echo "$ZERO_CALLS" >&2

  # For each file containing the offending line, backup and delete the line.
  # We avoid patching unknown files blindly: only those with proven bad lines.
  while IFS= read -r line; do
    file="$(echo "$line" | cut -d: -f1)"
    [[ -f "$file" ]] || continue
    note "Backing up + removing zero-arg validate_manifest line(s) in: $file"
    backup "$file"
    # Delete exact zero-arg line forms (./runtime/bin/validate_manifest or runtime/bin/validate_manifest)
    sed -i \
      -E '/^[[:space:]]*\.?\/?runtime\/bin\/validate_manifest[[:space:]]*$/d' \
      "$file"
  done <<<"$(echo "$ZERO_CALLS" | sed -E 's/:.*$//')"
else
  note "No zero-arg validate_manifest invocations found."
fi

# --- Restore backward-compatible validate_manifest if proven incompatible
if [[ "$VM_MODE" == "ARGPARSE_STRICT" ]]; then
  note "validate_manifest proven incompatible with repo callers -> rewriting to compat CLI"
  backup "runtime/bin/validate_manifest"

  cat > runtime/bin/validate_manifest <<'PY'
#!/usr/bin/env python3
import argparse, json, os, re, sys

HEX64 = re.compile(r"^[a-f0-9]{64}$")
REL_SAFE = re.compile(r"^[A-Za-z0-9._-]+$")  # basename-only, no slashes

def fail(msg: str) -> int:
    print(f"INVALID: {msg}", file=sys.stderr)
    return 1

def ok(msg: str="VALID") -> int:
    print(msg)
    return 0

def is_safe_sibling_basename(p: str) -> bool:
    return bool(REL_SAFE.match(p))

def parse_args():
    # Compat with BOTH:
    #   validate_manifest <manifest.json> [--release-id RID]
    #   validate_manifest --manifest <manifest.json> [--release-id RID]
    # Also tolerates: validate_manifest <manifest.json> --release-id RID
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("manifest_pos", nargs="?", help="manifest.json (positional)")
    ap.add_argument("--manifest", dest="manifest_opt", help="manifest.json (flag)")
    ap.add_argument("--release-id", dest="release_id", default=None, help="optional (legacy); accepted for compatibility")
    ns = ap.parse_args()

    m = ns.manifest_opt or ns.manifest_pos
    if not m:
        # Keep behavior strict (non-zero) so misuse is caught,
        # but now we should have removed the zero-arg invocations from tests/scripts.
        ap.print_usage(sys.stderr)
        raise SystemExit(2)
    return m, ns.release_id

def main() -> int:
    mpath, _rid = parse_args()

    if not os.path.isfile(mpath):
        return fail(f"manifest not found: {mpath}")

    try:
        with open(mpath, "r", encoding="utf-8") as f:
            m = json.load(f)
    except Exception as e:
        return fail(f"manifest not valid json: {e}")

    # Baseline invariants (stable)
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
        if m["signing_alg"] != "rsa-sha256-b64":
            return fail("signing_alg must be rsa-sha256-b64")

        fp = m["signing_pub_fingerprint_sha256"]
        if not isinstance(fp, str) or not HEX64.match(fp):
            return fail("signing_pub_fingerprint_sha256 must be 64-char lowercase hex")

        man_sig = m["manifest_sig_b64_path"]
        bun_sig = m["bundle_sig_b64_path"]

        if not isinstance(man_sig, str) or not is_safe_sibling_basename(man_sig):
            return fail("manifest_sig_b64_path must be a safe sibling basename")
        if not isinstance(bun_sig, str) or not is_safe_sibling_basename(bun_sig):
            return fail("bundle_sig_b64_path must be a safe sibling basename")

        if not man_sig.endswith(".sig.b64"):
            return fail("manifest_sig_b64_path must end with .sig.b64")
        if not bun_sig.endswith(".sig.b64"):
            return fail("bundle_sig_b64_path must end with .sig.b64")

        # If signing metadata is declared, signature files must exist as siblings of manifest.
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
  note "validate_manifest already legacy/compat -> no rewrite"
fi

# --- Inspect & fix Phase 98 test caller style (positional is repo-canonical)
if [[ -f test/98_test_manifest_signing_invariants.sh ]]; then
  note "Inspecting test/98_test_manifest_signing_invariants.sh for --manifest usage…"
  if grep -q "validate_manifest[[:space:]]\+--manifest" test/98_test_manifest_signing_invariants.sh; then
    note "Phase 98 test uses --manifest (not canonical here) -> rewriting that test to positional"
    backup test/98_test_manifest_signing_invariants.sh
    sed -i -E 's/runtime\/bin\/validate_manifest[[:space:]]+--manifest[[:space:]]+"/runtime\/bin\/validate_manifest "/g' \
      test/98_test_manifest_signing_invariants.sh
  else
    note "Phase 98 test already positional -> ok"
  fi
fi

# --- Final proof run
note "Running golden proof chain after fixes…"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
./test/90_test_all_deterministic.sh
./test/97_test_detached_signatures.sh
./test/91_test_no_release_minting.sh

note "✅ patch22.sh complete: compat validator + zero-arg call removal + proof chain PASS"
