#!/usr/bin/env bash
set -euo pipefail

cat > runtime/bin/runbook <<'RB'
#!/usr/bin/env bash
set -euo pipefail

# One-command operator loop:
# - assess status (without dying under set -e)
# - if stale: freshen
# - always produce reports
# - never hide failures

set +e
./runtime/bin/ops status >/dev/null
code=$?
set -e

if [ "$code" -eq 20 ]; then
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
RB

chmod +x runtime/bin/runbook
echo "OK: patched runbook to handle set -e correctly"
