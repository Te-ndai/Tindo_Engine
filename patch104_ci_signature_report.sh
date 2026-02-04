#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo "==> $*" >&2; }

WF=".github/workflows/ci.yml"
T95="test/95_test_ci_workflow.sh"

[ -f "$WF" ] || die "missing: $WF"
[ -f "$T95" ] || die "missing: $T95"
[ -x runtime/bin/verify_release_signatures ] || die "missing executable: runtime/bin/verify_release_signatures"

backup(){ cp -a "$1" "$1.bak.$(date -u +%Y%m%dT%H%M%SZ)"; }

note "0) Inspect verify_release_signatures (to avoid guessing CLI)…"
head -n 5 runtime/bin/verify_release_signatures | sed 's/^/   /' >&2 || true

note "1) Install runtime/bin/signature_report (report-only; auto-detect verify CLI)"
backup runtime/bin/signature_report 2>/dev/null || true

cat > runtime/bin/signature_report <<'SH'
#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo "==> $*" >&2; }

REL_DIR="runtime/state/releases"
PUB_DEFAULT="runtime/state/keys/release_pub.pem"

[ -d "$REL_DIR" ] || die "missing: $REL_DIR"
[ -x runtime/bin/verify_release_signatures ] || die "missing executable: runtime/bin/verify_release_signatures"

PUB="${SIGNING_PUB_PATH:-$PUB_DEFAULT}"
HAS_PUB="0"
[ -f "$PUB" ] && HAS_PUB="1"

# Detect verify_release_signatures CLI shape by grepping file content (proof, not guessing)
MODE="positional"   # positional | flag_manifest
if grep -qE -- '--manifest' runtime/bin/verify_release_signatures; then
  MODE="flag_manifest"
fi

# Helper to check if manifest declares signing
declares_signing(){
  python3 - <<'PY' "$1"
import json,sys
m=json.load(open(sys.argv[1],'r',encoding='utf-8'))
val=m.get("signing_alg","")
print("1" if isinstance(val,str) and val.strip() else "0")
PY
}

verify_one(){
  local manifest="$1"
  local out err rc
  out="$(mktemp)"; err="$(mktemp)"
  rc=0

  if [ "$HAS_PUB" = "1" ]; then
    if [ "$MODE" = "flag_manifest" ]; then
      # Try common forms; we keep this deterministic by trying in a fixed order.
      ./runtime/bin/verify_release_signatures --manifest "$manifest" --pub "$PUB" >"$out" 2>"$err" || rc=$?
      if [ "$rc" -ne 0 ]; then
        ./runtime/bin/verify_release_signatures --manifest "$manifest" "$PUB" >"$out" 2>"$err" || rc=$?
      fi
    else
      ./runtime/bin/verify_release_signatures "$manifest" --pub "$PUB" >"$out" 2>"$err" || rc=$?
      if [ "$rc" -ne 0 ]; then
        ./runtime/bin/verify_release_signatures "$manifest" "$PUB" >"$out" 2>"$err" || rc=$?
      fi
    fi
  else
    rc=90
    echo "NO_PUBKEY" >"$err"
  fi

  echo "$rc" >"$out.rc"
  echo "$out" >"$out.path"
  echo "$err" >"$err.path"
  echo "$out" "$err" "$rc"
}

echo "=== Phase 104 Signature report ==="
echo "scan_dir=$REL_DIR"
echo "pubkey_path=$PUB"
echo "pubkey_present=$HAS_PUB"
echo "verify_cli_mode=$MODE"
echo

printf "%-18s | %-28s | %s\n" "RID" "STATUS" "DETAIL"
printf "%-18s-+-%-28s-+-%s\n" "------------------" "----------------------------" "---------------------------"

shopt -s nullglob
for m in "$REL_DIR"/release_*.json; do
  rid="$(basename "$m")"
  rid="${rid#release_}"; rid="${rid%.json}"

  signed="$(declares_signing "$m")"
  if [ "$signed" = "0" ]; then
    printf "%-18s | %-28s | %s\n" "$rid" "UNSIGNED" "-"
    continue
  fi

  if [ "$HAS_PUB" != "1" ]; then
    printf "%-18s | %-28s | %s\n" "$rid" "SIGNED_UNVERIFIED_NO_PUBKEY" "missing $PUB"
    continue
  fi

  read -r out err rc < <(verify_one "$m")
  if [ "$rc" -eq 0 ]; then
    printf "%-18s | %-28s | %s\n" "$rid" "SIGNED_VERIFIED_OK" "-"
  else
    # show first line of stderr as detail
    detail="$(head -n 1 "$err" 2>/dev/null || true)"
    detail="${detail:-verify_failed_rc=$rc}"
    printf "%-18s | %-28s | %s\n" "$rid" "SIGNED_VERIFY_FAIL" "$detail"
  fi
done
SH

chmod +x runtime/bin/signature_report
note "Wrote + chmod runtime/bin/signature_report"

note "2) Patch ci.yml: add signature-report job + upload artifact"
backup "$WF"

python3 - <<'PY'
import re, pathlib, sys
wf = pathlib.Path(".github/workflows/ci.yml")
s = wf.read_text(encoding="utf-8")

if "jobs:" not in s:
    raise SystemExit("ci.yml missing jobs:")

if re.search(r"(?m)^\s{2}signature-report:\s*$", s):
    print("signature-report job already exists; leaving ci.yml unchanged", file=sys.stderr)
    sys.exit(0)

# detect first job id
jobs_block = s.split("jobs:",1)[1]
m = re.search(r"(?m)^\s{2}([a-zA-Z0-9_-]+):\s*$", jobs_block)
if not m:
    raise SystemExit("Could not detect any job id")
first_job = m.group(1)

# prefer deterministic-proof if present
needs = "deterministic-proof" if re.search(r"(?m)^\s{2}deterministic-proof:\s*$", s) else first_job

job = f"""
  signature-report:
    name: Phase 104 - Signature verification report
    runs-on: ubuntu-latest
    needs: [{needs}]
    steps:
      - uses: actions/checkout@v4
      - name: Ensure scripts executable
        run: |
          chmod +x runtime/bin/signature_report || true
          chmod +x runtime/bin/verify_release_signatures || true
      - name: Generate signature report (no mutation)
        run: |
          ./runtime/bin/signature_report > signature_report.txt
          cat signature_report.txt
      - name: Upload signature report
        uses: actions/upload-artifact@v4
        with:
          name: signature-report
          path: signature_report.txt
"""

# insert after manifest-portability-report if present, else after first job
port = re.search(r"(?m)^\s{2}manifest-portability-report:\s*$", s)
anchor = "manifest-portability-report" if port else first_job

pat = re.compile(rf"(?ms)^(\s{{2}}{re.escape(anchor)}:\s*$.*?)(?=^\s{{2}}[a-zA-Z0-9_-]+:\s*$|\Z)")
mm = pat.search(s)
if not mm:
    raise SystemExit(f"Could not parse job block for insertion anchor: {anchor}")

s2 = s[:mm.end(1)] + "\n" + job + s[mm.end(1):]
wf.write_text(s2, encoding="utf-8")
print(f"Inserted signature-report job (needs: {needs})", file=sys.stderr)
PY

note "3) Enforce Phase 104 in test/95_test_ci_workflow.sh"
backup "$T95"

if ! grep -q "signature-report" "$T95"; then
  cat >> "$T95" <<'SH'

# Phase 104: signature report job must exist and upload signature-report artifact
grep -qE 'signature-report:' "$wf" || die "workflow missing Phase 104 signature-report job"
grep -qE 'name:\s*signature-report' "$wf" || die "workflow Phase 104 job does not upload signature-report artifact"
grep -qE 'runtime/bin/signature_report' "$wf" || die "workflow Phase 104 job does not run runtime/bin/signature_report"
SH
  note "Appended Phase 104 checks to $T95"
else
  note "test/95 already enforces signature-report; leaving unchanged"
fi

note "4) Local proof: test/95 workflow inspection must pass"
./test/95_test_ci_workflow.sh

note "✅ Phase 104 patch complete"
