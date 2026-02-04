#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

die(){ echo "❌ $*" >&2; exit 1; }
ok(){ echo "✅ $*"; }

F="test/84_test_restore_replay.sh"
[ -f "$F" ] || die "missing $F"

backup(){
  local b="${F}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -f "$F" "$b"
  ok "backup: $b"
}

backup

# Verify anchors exist exactly once
a1=$(grep -n '^python3 - <<'\''PY'\'' "\$OPS_JSON" > "\$RESTORE_DIR/_actual\.json"$' "$F" | cut -d: -f1 || true)
a2=$(grep -n '^ACTUAL_LAST_EVENT_TIME=' "$F" | head -n1 | cut -d: -f1 || true)
e1=$(grep -n '^echo "Actual event count:' "$F" | head -n1 | cut -d: -f1 || true)

[ -n "${a1:-}" ] || die "anchor not found: ops actuals python heredoc line"
[ -n "${a2:-}" ] || die "anchor not found: ACTUAL_LAST_EVENT_TIME line"
[ -n "${e1:-}" ] || die "anchor not found: echo Actual event count line"

# We want to wrap from the python heredoc start (a1) up to just before echo actuals (e1)
start="$a1"
end="$((e1-1))"

tmp="${F}.tmp.$(date -u +%Y%m%dT%H%M%SZ)"

nl -ba "$F" | awk -v start="$start" -v end="$end" '
BEGIN{OFS=""; wrapped=0}
{
  line_no=$1; $1=""; sub(/^ /,"");  # remove the line number and leading space from nl
  if(line_no==start){
    print "if [ -s \"$OPS_JSON\" ]; then"
    wrapped=1
  }
  if(line_no>=start && line_no<=end){
    # indent wrapped block content by two spaces
    print "  " $0
    next
  }
  if(line_no==end+1 && wrapped==1){
    # close the if before the echo actuals line
    print "else"
    print "  echo \"Skipping JSON actuals parsing (ops report not JSON)\""
    print "  ACTUAL_EVENT_COUNT=\"\""
    print "  ACTUAL_LAST_EVENT_TIME=\"\""
    print "fi"
    wrapped=2
  }
  print $0
}
' > "$tmp"

mv "$tmp" "$F"
chmod +x "$F"

# Sanity checks: ensure guard exists and the parse line is now indented
grep -q '^if \[ -s "\$OPS_JSON" \]; then$' "$F" || die "guard not inserted"
grep -q '^  python3 - <<'\''PY'\'' "\$OPS_JSON" > "\$RESTORE_DIR/_actual\.json"$' "$F" || die "parse block not indented under guard"

ok "Patched Phase 84: guarded JSON parsing of ops report actuals"
echo "Now run:"
echo "  ./test/84_test_restore_replay.sh"
