#!/usr/bin/env bash
set -euo pipefail

cat > runtime/bin/ops <<'SH'
#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-}"

status_summary() {
  # Ensure status is current (rebuild system_status only)
  ./runtime/bin/rebuild_projections system_status >/dev/null

  python3 - <<'PY'
import json, sys
d=json.load(open("runtime/state/projections/system_status.json","r",encoding="utf-8"))
rows=[r for r in d.get("projections",[]) if isinstance(r,dict)]
fails=[r for r in rows if r.get("status")=="FAIL"]
stales=[r for r in rows if r.get("status")=="STALE"]

print("system_status ok =", d.get("ok"))
print("checked_at_utc =", d.get("checked_at_utc"))
print("errors =", len(d.get("errors",[])))

def fmt(r):
    name=r.get("name")
    st=r.get("status")
    le=r.get("last_event_time_utc","")
    ll=r.get("log_last_event_time_utc","")
    return f"- {name}: {st} last={le} log_last={ll}"

if fails:
    print("\nFAIL:")
    for r in fails: print(fmt(r))
if stales:
    print("\nSTALE:")
    for r in stales: print(fmt(r))

# Exit codes:
# 0 OK, 10 STALE, 20 FAIL
if fails:
    sys.exit(20)
if stales:
    sys.exit(10)
sys.exit(0)
PY
}

case "$CMD" in
  status)
    status_summary
    ;;

  freshen)
    # make_fresh already rebuilds status and fails if unhealthy
    if ./runtime/bin/make_fresh >/dev/null; then
      # Now status should be OK
      status_summary
    else
      # If make_fresh failed, report status and propagate as FAIL
      status_summary || true
      exit 20
    fi
    ;;

  rebuild)
    MODE="${2:-all}"
    if [ "$MODE" = "all" ]; then
      ./runtime/bin/rebuild_projections >/dev/null
      echo "OK: rebuilt all projections"
      status_summary
    else
      ./runtime/bin/rebuild_projections "$MODE" >/dev/null
      echo "OK: rebuilt projection: $MODE"
      status_summary
    fi
    ;;

  *)
    echo "usage: ops {status|freshen|rebuild [all|<name>]}"
    exit 2
    ;;
esac
SH

chmod +x runtime/bin/ops

echo "OK: phase 70 populate complete"
