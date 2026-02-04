#!/usr/bin/env bash
set -euo pipefail

cat > runtime/bin/runbook <<'SH'
#!/usr/bin/env bash
set -euo pipefail

# One-command operator loop:
# - assess status
# - if stale: freshen
# - always produce reports
# - never hide failures

./runtime/bin/ops status >/dev/null
code=$?

if [ "$code" -eq 20 ]; then
  # Hard failure: still generate diagnosis + report for visibility
  ./runtime/bin/ops diagnose || true
  ./runtime/bin/ops report >/dev/null || true
  echo "RUNBOOK: FAIL (see runtime/state/reports/diagnose.txt)"
  exit 20
fi

if [ "$code" -eq 10 ]; then
  ./runtime/bin/ops freshen >/dev/null
fi

./runtime/bin/ops report >/dev/null
echo "RUNBOOK: OK (see runtime/state/reports/diagnose.txt)"
exit 0
SH

chmod +x runtime/bin/runbook
echo "OK: phase 82 populate complete"
