#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo "==> $*" >&2; }

WF=".github/workflows/ci.yml"
T95="test/95_test_ci_workflow.sh"

[ -f "$WF" ] || die "missing: $WF"
[ -f "$T95" ] || die "missing: $T95"
[ -x runtime/bin/validate_manifest ] || die "missing executable: runtime/bin/validate_manifest"
[ -f patch102_hygiene.sh ] || die "missing: patch102_hygiene.sh (Phase 102 root hygiene script)"

backup(){ cp -a "$1" "$1.bak.$(date -u +%Y%m%dT%H%M%SZ)"; }

note "Inspect current workflow jobs (proof)…"
grep -nE '^[[:space:]]*[a-zA-Z0-9_-]+:[[:space:]]*$|name:|upload-artifact|portability' "$WF" | head -n 120 >&2 || true

note "1) Patch ci.yml: add hygiene_report job (dry-run only) + artifact upload"
backup "$WF"

python3 - <<'PY'
import re, sys, pathlib

wf_path = pathlib.Path(".github/workflows/ci.yml")
s = wf_path.read_text(encoding="utf-8")

# Basic sanity: ensure workflow has jobs:
if "jobs:" not in s:
    raise SystemExit("ci.yml missing 'jobs:'")

# If hygiene_report already present, do nothing
if re.search(r"(?m)^\s*hygiene_report:\s*$", s):
    print("hygiene_report job already exists; leaving ci.yml unchanged", file=sys.stderr)
    sys.exit(0)

# Insert a new job after portability_report if present; else after proof job.
# We’ll look for a job key portability_report: or manifest_portability: style; fallback to first job.
insert_job = r"""
  hygiene_report:
    name: Phase 103 - Hygiene report (dry-run)
    runs-on: ubuntu-latest
    needs: [proof_chain]
    steps:
      - uses: actions/checkout@v4
      - name: Make scripts executable
        run: |
          chmod +x patch102_hygiene.sh || true
          chmod +x runtime/bin/validate_manifest || true
      - name: Run hygiene (dry-run only)
        run: |
          ./patch102_hygiene.sh --dry-run
          test -f runtime/state/reports/phase102_hygiene_latest.txt
      - name: Upload hygiene report
        uses: actions/upload-artifact@v4
        with:
          name: hygiene-report
          path: runtime/state/reports/phase102_hygiene_latest.txt
"""

# Determine the proof job id (your workflow currently has “Job 1: deterministic proof chain”).
# We enforce job id 'proof_chain' in this patch (if your job id differs, we adapt by detecting it).
# Detect first job key under jobs: as proof job id.
jobs_block = s.split("jobs:", 1)[1]
m = re.search(r"(?m)^\s{2}([a-zA-Z0-9_-]+):\s*$", jobs_block)
if not m:
    raise SystemExit("Could not detect any job id under jobs:")
first_job_id = m.group(1)

# We’ll reference needs: [proof_chain] only if proof_chain exists, else use first job id.
proof_id = "proof_chain" if re.search(r"(?m)^\s{2}proof_chain:\s*$", s) else first_job_id
insert_job = insert_job.replace("needs: [proof_chain]", f"needs: [{proof_id}]")

# Insert position: after a portability job if present (common ids: portability_report, manifest_portability)
port_match = re.search(r"(?m)^\s{2}(portability_report|manifest_portability|portability):\s*$", s)
if port_match:
    job_id = port_match.group(1)
    # Find end of that job by locating next job key at same indent
    pat = re.compile(rf"(?ms)^(\s{{2}}{re.escape(job_id)}:\s*$.*?)(?=^\s{{2}}[a-zA-Z0-9_-]+:\s*$|\Z)")
    mm = pat.search(s)
    if not mm:
        raise SystemExit(f"Found job id {job_id} but couldn't parse its block")
    s2 = s[:mm.end(1)] + "\n" + insert_job + s[mm.end(1):]
else:
    # Insert after first job block
    pat = re.compile(rf"(?ms)^(\s{{2}}{re.escape(first_job_id)}:\s*$.*?)(?=^\s{{2}}[a-zA-Z0-9_-]+:\s*$|\Z)")
    mm = pat.search(s)
    if not mm:
        raise SystemExit(f"Couldn't parse first job block: {first_job_id}")
    s2 = s[:mm.end(1)] + "\n" + insert_job + s[mm.end(1):]

wf_path.write_text(s2, encoding="utf-8")
print(f"Inserted hygiene_report job (needs: {proof_id})", file=sys.stderr)
PY

note "2) Patch test/95_test_ci_workflow.sh to enforce hygiene job + artifact"
backup "$T95"

# Append minimal enforcement checks if not already present
if ! grep -q "hygiene-report" "$T95"; then
  cat >> "$T95" <<'SH'

# Phase 103: hygiene report job must exist and upload hygiene-report artifact
grep -qE 'hygiene_report:' "$wf" || die "workflow missing Phase 103 hygiene_report job"
grep -qE 'name:\s*hygiene-report' "$wf" || die "workflow hygiene job does not upload hygiene-report artifact"
grep -qE 'patch102_hygiene\.sh[[:space:]]+--dry-run' "$wf" || die "workflow hygiene job does not run patch102_hygiene.sh --dry-run"
SH
  note "Appended Phase 103 checks to $T95"
else
  note "test/95 already references hygiene-report; leaving unchanged"
fi

note "3) Quick local proof: test/95 should pass (workflow inspection only)"
./test/95_test_ci_workflow.sh

note "✅ Phase 103 patch complete"
