#!/usr/bin/env bash
set -euo pipefail

./runtime/bin/ops report >/dev/null

LOG=/tmp/dashboard.log
rm -f "$LOG"

./runtime/bin/dashboard >"$LOG" 2>&1 &
PID=$!

cleanup() {
  kill "$PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Wait up to 5 seconds for server to come up
ok=0
for i in $(seq 1 50); do
  # if process died, show log and fail
  if ! kill -0 "$PID" >/dev/null 2>&1; then
    echo "FAIL: dashboard process exited early"
    echo "---- dashboard log ----"
    sed -n '1,200p' "$LOG" || true
    exit 1
  fi

  if curl -fsS http://127.0.0.1:5055/api/status >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 0.1
done

if [ "$ok" -ne 1 ]; then
  echo "FAIL: dashboard did not become reachable on 127.0.0.1:5055"
  echo "---- dashboard log ----"
  sed -n '1,200p' "$LOG" || true
  exit 1
fi

# Now run full smoke checks
curl -fsS http://127.0.0.1:5055/api/status >/dev/null
curl -fsS http://127.0.0.1:5055/api/diagnose >/dev/null
curl -fsS http://127.0.0.1:5055/api/report >/dev/null
curl -fsS http://127.0.0.1:5055/ >/dev/null

echo "✅ Phase 81 TEST PASS"
