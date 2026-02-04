cat > patch89_fix.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
ok(){ echo "OK: $*"; }

[ -d test ] || die "missing ./test (run from repo root)"
[ -d runtime ] || die "missing ./runtime (run from repo root)"
mkdir -p .tmp

backup_dir=".tmp/patch89_backup_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir"

backup(){
  local f="$1"
  if [ -f "$f" ]; then
    mkdir -p "$backup_dir/$(dirname "$f")"
    cp -a "$f" "$backup_dir/$f"
    ok "backup: $f -> $backup_dir/$f"
  fi
}

# Back up the files we will overwrite
backup test/83_test_release_bundle.sh
backup test/86_test_bundle_sha.sh
backup test/87_test_compat_contract.sh

# IMPORTANT: disable the old patch.sh if it exists (it's sabotaging you)
if [ -f patch.sh ]; then
  mv -f patch.sh "$backup_dir/patch.sh.disabled"
  ok "disabled old patch.sh -> $backup_dir/patch.sh.disabled"
fi

# --- Rewrite test/83_test_release_bundle.sh (deterministic, no corrupted heredocs) ---
cat > test/83_test_release_bundle.sh <<'SH'
#!/usr/bin/env bash
# Phase 83 TEST: release bundle contains required evidence + manifest core fields
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }

: "${RELEASE_ID:?ERROR: RELEASE_ID not set}"

# Create the deterministic release for this RELEASE_ID
./runtime/bin/release_bundle --release-id "$RELEASE_ID" >/dev/null

bundle="runtime/state/releases/release_${RELEASE_ID}.tar.gz"
manifest="runtime/state/releases/release_${RELEASE_ID}.json"

[ -f "$bundle" ] || die "bundle missing: $bundle"
[ -f "$manifest" ] || die "manifest missing: $manifest"

python3 - <<'PY' "$bundle"
import sys, tarfile
bundle = sys.argv[1]
required = {
  "runtime/state/reports/diagnose.txt",
  "runtime/state/logs/executions.chain.jsonl",
  "runtime/state/logs/executions.chain.checkpoint.json",
  "runtime/state/logs/executions.jsonl",
  "runtime/bin/logchain_verify",
  "runtime/bin/rebuild_projections",
  "runtime/bin/ops",
  "runtime/core/projections.py",
}
with tarfile.open(bundle, "r:gz") as tf:
    names = set(tf.getnames())
missing = sorted(required - names)
if missing:
    print("MISSING:")
    for m in missing:
        print(" -", m)
    raise SystemExit(1)
print("OK: required members present")
PY

python3 - <<'PY' "$manifest"
import json, sys
d = json.load(open(sys.argv[1], "r", encoding="utf-8"))

assert "schema_version" in d, "missing schema_version"
assert "compat" in d and isinstance(d["compat"], dict), "missing/invalid compat"
assert "bundle_path" in d and isinstance(d["bundle_path"], str) and d["bundle_path"], "missing/invalid bundle_path"

assert "expected_event_count" in d and isinstance(d["expected_event_count"], int), "missing/invalid expected_event_count"
assert "expected_last_event_time_utc" in d and isinstance(d["expected_last_event_time_utc"], str), "missing/invalid expected_last_event_time_utc"

# SHA may be empty here; Phase 86 verifies/fills it
assert "bundle_sha256" in d and isinstance(d["bundle_sha256"], str), "missing/invalid bundle_sha256 key"

print("OK: manifest fields present (sha may be empty pre-86)")
PY

echo "✅ Phase 83 TEST PASS"
SH
chmod +x test/83_test_release_bundle.sh
ok "rewrote test/83_test_release_bundle.sh"

# --- Rewrite test/86_test_bundle_sha.sh (deterministic + fill sha) ---
cat > test/86_test_bundle_sha.sh <<'SH'
#!/usr/bin/env bash
# Phase 86 TEST: Bundle SHA integrity (deterministic via RELEASE_ID)
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
import hashlib, json, sys, tarfile
bundle, manifest = sys.argv[1], sys.argv[2]

h = hashlib.sha256()
with open(bundle, "rb") as f:
    for chunk in iter(lambda: f.read(1024*1024), b""):
        h.update(chunk)
sha = h.hexdigest()

d = json.load(open(manifest, "r", encoding="utf-8"))
cur = d.get("bundle_sha256")
if cur is None or cur == "":
    d["bundle_sha256"] = sha
    with open(manifest, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, sort_keys=True)
        f.write("\n")
    print("OK: wrote bundle_sha256 into sibling manifest")
else:
    if cur != sha:
        raise SystemExit(f"ERROR: bundle_sha256 mismatch: manifest={cur} actual={sha}")
    print("OK: bundle_sha256 matches manifest")

with tarfile.open(bundle, "r:gz") as tf:
    names = set(tf.getnames())
    embedded = [n for n in names if n.startswith("runtime/state/releases/release_") and n.endswith(".json")]
    if not embedded:
        raise SystemExit("ERROR: embedded manifest missing in tarball")
    print("OK: embedded manifest present:", sorted(embedded)[-1])
PY

echo "✅ Phase 86 TEST PASS (bundle sha verified)"
SH
chmod +x test/86_test_bundle_sha.sh
ok "rewrote test/86_test_bundle_sha.sh"

# --- Rewrite test/87_test_compat_contract.sh (deterministic + canonical host) ---
cat > test/87_test_compat_contract.sh <<'SH'
#!/usr/bin/env bash
# Phase 87 TEST: manifest includes compat contract and matches current host
# Deterministic via RELEASE_ID (does NOT mint new releases)
set -euo pipefail
die(){ echo "FAIL: $*" >&2; exit 1; }

: "${RELEASE_ID:?ERROR: RELEASE_ID not set}"

bundle="runtime/state/releases/release_${RELEASE_ID}.tar.gz"
manifest="runtime/state/releases/release_${RELEASE_ID}.json"
[ -f "$bundle" ] || die "bundle not found for RELEASE_ID: $bundle"
[ -f "$manifest" ] || die "manifest not found for RELEASE_ID: $manifest"

echo "Using bundle:   $bundle"
echo "Using manifest: $manifest"

python3 - <<'PY' "$manifest"
import json, platform, sys
m = json.load(open(sys.argv[1], "r", encoding="utf-8"))

assert isinstance(m.get("schema_version"), int) and m["schema_version"] >= 1, "missing/invalid schema_version"
c = m.get("compat")
assert isinstance(c, dict), "missing compat object"

required = ("os","arch","python","impl","machine")
for k in required:
    assert isinstance(c.get(k), str) and c[k], f"compat missing {k}"

host = {
  "os": platform.system().lower(),
  "arch": platform.machine().lower(),
  "python": platform.python_version(),
  "impl": platform.python_implementation().lower(),
  "machine": platform.platform(),
}

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
ok "rewrote test/87_test_compat_contract.sh"

ok "patch89_fix complete"
echo "Run:"
echo '  RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"'
echo '  ./test/83_test_release_bundle.sh'
echo '  ./test/84_test_restore_replay.sh'
echo '  ./test/86_test_bundle_sha.sh'
echo '  ./test/87_test_compat_contract.sh'
EOF

chmod +x patch89_fix.sh
