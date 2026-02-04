#!/usr/bin/env bash
set -euo pipefail

echo "== patch9: force diagnose wiring + rebuild_projections single-target support =="

# --- (1) Registry: ensure diagnose exists ---
python3 - <<'PY'
import json, pathlib
p=pathlib.Path("runtime/schema/projection_registry.json")
d=json.loads(p.read_text(encoding="utf-8"))
projs=d.get("projections",[])
names=[x.get("name") for x in projs if isinstance(x,dict)]
if "diagnose" not in names:
    projs.append({
        "name":"diagnose",
        "enabled": True,
        "source_log":"",
        "output":"runtime/state/projections/diagnose.json"
    })
    d["projections"]=projs
    p.write_text(json.dumps(d, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("OK: registry added diagnose")
else:
    print("OK: registry already has diagnose")
PY

# --- (2) Payload contracts: ensure diagnose exists ---
python3 - <<'PY'
import json, pathlib
p=pathlib.Path("runtime/schema/projection_payload_contracts.json")
d=json.loads(p.read_text(encoding="utf-8"))
contracts=d.setdefault("contracts",{})
contracts["diagnose"]={
    "required_fields":["ok","generated_at_utc","findings"],
    "field_types":{"ok":"int","generated_at_utc":"string","findings":"list"}
}
p.write_text(json.dumps(d, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print("OK: payload contract set for diagnose")
PY

# --- (3) projections.py: force-insert build_diagnose and ensure BUILDERS has it ---
python3 - <<'PY'
import pathlib, re

p=pathlib.Path("runtime/core/projections.py")
s=p.read_text(encoding="utf-8")

# Insert build_diagnose once, right before BUILDERS = { ... }
if "def build_diagnose" not in s:
    fn = r'''

def build_diagnose(_: str) -> Dict[str, Any]:
    from datetime import datetime, timezone
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    status_path = os.path.join(ROOT, "runtime", "state", "projections", "system_status.json")
    findings: List[Dict[str, Any]] = []
    ok = 1

    if not os.path.exists(status_path):
        ok = 0
        findings.append({
          "severity":"FAIL",
          "code":"SYSTEM_STATUS_MISSING",
          "message":"system_status.json missing",
          "action":"./runtime/bin/rebuild_projections system_status"
        })
    else:
        st = _read_json(status_path)
        rows = [r for r in st.get("projections", []) if isinstance(r, dict)]
        by_name = {r.get("name"): r for r in rows if isinstance(r.get("name"), str)}

        li = by_name.get("log_integrity")
        if not li or li.get("status") != "OK":
            ok = 0
            details = li.get("details") if isinstance(li, dict) else "missing row"
            findings.append({
              "severity":"FAIL",
              "code":"LOG_INTEGRITY",
              "message":f"log integrity FAIL: {details}",
              "action":"# restore logs/checkpoint then: ./runtime/bin/ops status"
            })

        stale = [r.get("name") for r in rows if r.get("status") == "STALE"]
        stale = [n for n in stale if n and n not in ("system_status","log_integrity")]
        if stale:
            findings.append({
              "severity":"WARN",
              "code":"PROJECTION_STALE",
              "message":"stale projections: " + ", ".join(stale),
              "action":"./runtime/bin/ops freshen"
            })

        fails = [r.get("name") for r in rows if r.get("status") == "FAIL"]
        fails = [n for n in fails if n and n not in ("system_status","log_integrity")]
        if fails:
            ok = 0
            findings.append({
              "severity":"FAIL",
              "code":"PROJECTION_FAIL",
              "message":"failed projections: " + ", ".join(fails),
              "action":"./runtime/bin/ops rebuild all"
            })

        if ok == 1 and not findings:
            findings.append({
              "severity":"INFO",
              "code":"ALL_GOOD",
              "message":"system healthy",
              "action":"./runtime/bin/ops status"
            })

    return {
      "projection":"diagnose",
      "source":"",
      "total":0,
      "last_event_time_utc":"",
      "ok": ok,
      "generated_at_utc": generated_at,
      "findings": findings
    }
'''
    s = re.sub(r'\nBUILDERS\s*=\s*{', fn + r'\n\nBUILDERS = {', s, count=1)
    print("OK: inserted build_diagnose")
else:
    print("OK: build_diagnose already present")

# Ensure BUILDERS dict contains diagnose entry (simple safe insert if missing)
if '"diagnose": build_diagnose' not in s:
    s = s.replace(
        'BUILDERS = {\n',
        'BUILDERS = {\n    "diagnose": build_diagnose,\n'
    )
    print("OK: BUILDERS now includes diagnose")
else:
    print("OK: BUILDERS already includes diagnose")

p.write_text(s, encoding="utf-8")
PY

python3 -m py_compile runtime/core/projections.py
echo "OK: projections.py compiles"

# --- (4) Rewrite runtime/bin/rebuild_projections to correctly support rebuild_one ---
cat > runtime/bin/rebuild_projections <<'RB'
#!/usr/bin/env bash
set -euo pipefail

# usage:
#   rebuild_projections            -> rebuild_all registry-driven
#   rebuild_projections <name>     -> rebuild_one <name> (registry-driven output path)
#
# NOTE: ops auto-maintains chain; here we don't mutate logs, only projections.

NAME="${1:-}"

if [ -z "$NAME" ]; then
  python3 runtime/core/projections.py rebuild_all >/dev/null
  echo "OK: projections rebuilt (registry-driven)"
  exit 0
fi

python3 runtime/core/projections.py rebuild_one "$NAME" >/dev/null
echo "OK: projection rebuilt: $NAME"
RB

chmod +x runtime/bin/rebuild_projections
echo "OK: rebuild_projections rewritten with rebuild_one support"

echo "== patch9 complete =="
