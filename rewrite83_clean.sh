#!/usr/bin/env bash
set -euo pipefail

# anchor to repo root as the directory containing this script
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

die(){ echo "FAIL: $*" >&2; exit 1; }
ok(){ echo "✅ $*"; }

OUT="test/83_test_release_bundle.sh"
[ -d test ] || die "missing ./test"
[ -x runtime/bin/release_bundle ] || die "missing runtime/bin/release_bundle"

# backup
if [ -f "$OUT" ]; then
  B="${OUT}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -f "$OUT" "$B"
  ok "backup: $B"
fi

cat > "$OUT" <<'SH'
#!/usr/bin/env bash
# Phase 83 TEST: release bundle contains required evidence + replay commands
set -euo pipefail

die(){ echo "FAIL: $*" >&2; exit 1; }

./runtime/bin/release_bundle >/dev/null

bundle="$(ls -1t runtime/state/releases/release_*.tar.gz 2>/dev/null | head -n 1 || true)"
manifest="$(ls -1t runtime/state/releases/release_*.json 2>/dev/null | head -n 1 || true)"

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
PY
[ "$?" -eq 0 ] || die "bundle missing required members (see list above)"

python3 - <<'PY' "$manifest"
import json, sys
d=json.load(open(sys.argv[1],"r",encoding="utf-8"))
assert "expected_event_count" in d and isinstance(d["expected_event_count"], int), "missing/invalid expected_event_count"
assert "expected_last_event_time_utc" in d and isinstance(d["expected_last_event_time_utc"], str), "missing/invalid expected_last_event_time_utc"
assert d.get("bundle_sha256",""), "missing bundle_sha256"
print("OK: manifest expectations present")
PY

echo "✅ Phase 83 TEST PASS"
SH

chmod +x "$OUT"
ok "rewrote: test/83_test_release_bundle.sh"
echo "Run:"
echo "  ./test/83_test_release_bundle.sh"
