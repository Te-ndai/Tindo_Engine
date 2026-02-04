#!/usr/bin/env bash
set -euo pipefail
die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo "==> $*" >&2; }

WF=".github/workflows/ci.yml"
T95="test/95_test_ci_workflow.sh"

[ -f "$WF" ] || die "missing: $WF"
[ -f "$T95" ] || die "missing: $T95"
[ -x runtime/bin/attach_release_signatures ] || die "missing executable: runtime/bin/attach_release_signatures"
[ -x runtime/bin/verify_release_signatures ] || die "missing executable: runtime/bin/verify_release_signatures"
[ -x runtime/bin/validate_manifest ] || die "missing executable: runtime/bin/validate_manifest"
[ -f runtime/state/keys/release_pub.pem ] || die "missing repo pubkey: runtime/state/keys/release_pub.pem (Phase 99A)"

backup(){ cp -a "$1" "$1.bak.$(date -u +%Y%m%dT%H%M%SZ)"; }

note "1) Install runtime/bin/ci_sign_releases"
backup runtime/bin/ci_sign_releases 2>/dev/null || true

cat > runtime/bin/ci_sign_releases <<'SH'
#!/usr/bin/env bash
set -euo pipefail
die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo "==> $*" >&2; }

REL_DIR="${1:-runtime/state/releases}"
PUB="runtime/state/keys/release_pub.pem"

[ -d "$REL_DIR" ] || die "missing releases dir: $REL_DIR"
[ -f "$PUB" ] || die "missing repo pubkey: $PUB"
[ -n "${RELEASE_SIGNING_KEY_PEM:-}" ] || die "missing env: RELEASE_SIGNING_KEY_PEM"

# write secret key to temp file (CI only)
KEYFILE="$(mktemp)"
trap 'rm -f "$KEYFILE"' EXIT
printf "%s\n" "$RELEASE_SIGNING_KEY_PEM" > "$KEYFILE"
chmod 600 "$KEYFILE" || true

signed=0
scanned=0

# Helper: does manifest declare signing already?
declares_signing(){
  python3 - <<'PY' "$1"
import json,sys
m=json.load(open(sys.argv[1],'r',encoding='utf-8'))
v=m.get("signing_alg","")
print("1" if isinstance(v,str) and v.strip() else "0")
PY
}

shopt -s nullglob
for m in "$REL_DIR"/release_*.json; do
  scanned=$((scanned+1))
  rid="$(basename "$m")"; rid="${rid#release_}"; rid="${rid%.json}"
  b="$REL_DIR/release_${rid}.tar.gz"

  # skip if missing bundle
  [ -f "$b" ] || { note "skip RID=$rid (bundle missing)"; continue; }

  # skip if already signed
  if [ "$(declares_signing "$m")" = "1" ]; then
    note "skip RID=$rid (already declares signing)"
    continue
  fi

  note "sign RID=$rid"
  # Try canonical CLI first, then fallback positional
  if ./runtime/bin/attach_release_signatures --manifest "$m" --key "$KEYFILE" --pub "$PUB" >/dev/null 2>&1; then
    :
  else
    ./runtime/bin/attach_release_signatures "$m" "$KEYFILE" "$PUB" >/dev/null
  fi

  # validate + verify (should now pass)
  ./runtime/bin/validate_manifest "$m" >/dev/null
  ./runtime/bin/verify_release_signatures --manifest "$m" >/dev/null

  signed=$((signed+1))
done

note "done: scanned=$scanned signed=$signed rel_dir=$REL_DIR"
echo "scanned=$scanned signed=$signed"
SH

chmod +x runtime/bin/ci_sign_releases
note "Wrote + chmod runtime/bin/ci_sign_releases"

note "2) Patch ci.yml: add sign-releases job (uses RELEASE_SIGNING_KEY_PEM secret)"
backup "$WF"

python3 - <<'PY'
import re, pathlib, sys
wf = pathlib.Path(".github/workflows/ci.yml")
s = wf.read_text(encoding="utf-8")

if re.search(r"(?m)^\s{2}sign-releases:\s*$", s):
    print("sign-releases job already exists; leaving ci.yml unchanged", file=sys.stderr)
    sys.exit(0)

# Determine proof job id (you have deterministic-proof)
needs = "deterministic-proof" if re.search(r"(?m)^\s{2}deterministic-proof:\s*$", s) else None
if not needs:
    m = re.search(r"(?m)^\s{2}([a-zA-Z0-9_-]+):\s*$", s.split("jobs:",1)[1])
    if not m: raise SystemExit("Could not detect first job id")
    needs = m.group(1)

job = f"""
  sign-releases:
    name: Phase 105B - Sign minted releases (CI)
    runs-on: ubuntu-latest
    needs: [{needs}]
    steps:
      - uses: actions/checkout@v4
      - name: Download minted release artifacts
        uses: actions/download-artifact@v4
        with:
          name: runtime-releases
          path: runtime/state/releases
      - name: Ensure tools executable
        run: |
          chmod +x runtime/bin/ci_sign_releases || true
          chmod +x runtime/bin/attach_release_signatures || true
          chmod +x runtime/bin/verify_release_signatures || true
          chmod +x runtime/bin/validate_manifest || true
      - name: Sign releases (no minting)
        env:
          RELEASE_SIGNING_KEY_PEM: ${{ secrets.RELEASE_SIGNING_KEY_PEM }}
        run: |
          ./runtime/bin/ci_sign_releases runtime/state/releases
      - name: Signature report (post-sign)
        run: |
          chmod +x runtime/bin/signature_report || true
          ./runtime/bin/signature_report > signature_report_after_sign.txt
          cat signature_report_after_sign.txt
      - name: Upload signed releases
        uses: actions/upload-artifact@v4
        with:
          name: runtime-releases-signed
          path: runtime/state/releases
      - name: Upload signature report (after sign)
        uses: actions/upload-artifact@v4
        with:
          name: signature-report-after-sign
          path: signature_report_after_sign.txt
"""

# Insert after deterministic-proof block
anchor = "deterministic-proof" if re.search(r"(?m)^\s{2}deterministic-proof:\s*$", s) else needs
pat = re.compile(rf"(?ms)^(\s{{2}}{re.escape(anchor)}:\s*$.*?)(?=^\s{{2}}[a-zA-Z0-9_-]+:\s*$|\Z)")
mm = pat.search(s)
if not mm:
    raise SystemExit(f"Could not parse anchor job block: {anchor}")

s2 = s[:mm.end(1)] + "\n" + job + s[mm.end(1):]
wf.write_text(s2, encoding="utf-8")
print(f"Inserted sign-releases job (needs: {needs})", file=sys.stderr)
PY

note "3) Enforce Phase 105B in test/95_test_ci_workflow.sh"
backup "$T95"

if ! grep -q "Phase 105B" "$T95"; then
  cat >> "$T95" <<'SH'

# Phase 105B: CI must sign minted releases using a secret key, without minting
grep -qE 'sign-releases:' "$wf" || die "workflow missing Phase 105B sign-releases job"
grep -qE 'secrets\.RELEASE_SIGNING_KEY_PEM' "$wf" || die "workflow sign-releases job does not reference RELEASE_SIGNING_KEY_PEM secret"
grep -qE 'actions/download-artifact@v4' "$wf" || die "workflow sign-releases job does not download runtime-releases artifact"
grep -qE 'name:\s*runtime-releases-signed' "$wf" || die "workflow sign-releases job does not upload runtime-releases-signed artifact"
SH
  note "Appended Phase 105B checks to $T95"
else
  note "test/95 already has Phase 105B checks; leaving unchanged"
fi

note "4) Local proof: workflow inspection test must pass"
./test/95_test_ci_workflow.sh

note "✅ Phase 105B patch complete"
note "ACTION REQUIRED: add GitHub Secret RELEASE_SIGNING_KEY_PEM (private key PEM) matching runtime/state/keys/release_pub.pem"
