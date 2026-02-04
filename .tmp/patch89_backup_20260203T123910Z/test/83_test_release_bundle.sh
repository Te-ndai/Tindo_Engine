#!/usr/bin/env bash
# Phase 83 TEST: release bundle contains required evidence + replay commands
set -euo pipefail

die(){ echo "FAIL: $*" >&2; exit 1; }

: "${RELEASE_ID:?ERROR: RELEASE_ID not set}"

./runtime/bin/release_bundle --release-id "$RELEASE_ID" >/dev/null

bundle="runtime/state/releases/release_${RELEASE_ID}.tar.gz"
manifest="runtime/state/releases/release_${RELEASE_ID}.json"


[ -n "$bundle" ] || die "bundle missing"
[ -n "$manifest" ] || die "manifest missing"
[ -f "$bundle" ] || die "bundle path not a file: $bundle"
[ -f "$manifest" ] || die "manifest path not a file: $manifest"


python3 - <<'PY' "$bundle"
import sys, tarfile

bundle = sys.argv[1]
required = {
  "runtime/state/reports/diagnose.txt",
  "runtime/state/logs/executions.chain.jsonl",
  "runtime/state/logs/executions.chain.checkpoint.json",
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

python3 - <<'PY' "$manifest"
import json, platform, sys

d = json.load(open(sys.argv[1], "r", encoding="utf-8"))
assert "compat" in d and isinstance(d["compat"], dict), "missing compat"

manifest = d["compat"]
host = {
  "os": platform.system().lower(),
  "arch": platform.machine().lower(),
  "python": platform.python_version(),
  "impl": platform.python_implementation().lower(),
  "machine": platform.platform(),
}

# Strict equality (including machine)
if manifest != host:
    print("COMPAT_MISMATCH:")
    for k in ("os","arch","python","impl","machine"):
        if manifest.get(k) != host.get(k):
            print(f" - {k}: manifest={manifest.get(k)!r} host={host.get(k)!r}")
    raise SystemExit(1)

print("OK: compat matches host")
PY

echo "✅ Phase 83 TEST PASS"
