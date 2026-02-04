#!/usr/bin/env bash
set -euo pipefail

# Add ops diagnose subcommand
python3 - <<'PY'
import pathlib
p=pathlib.Path("runtime/bin/ops")
s=p.read_text(encoding="utf-8")

if "\n  diagnose)\n" not in s:
    # insert a new case before *)
    s=s.replace(
        "\n  *)\n",
        "\n  diagnose)\n"
        "    ./runtime/bin/rebuild_projections diagnose >/dev/null || true\n"
        "    python3 - <<'PY'\n"
        "import json, sys\n"
        "d=json.load(open('runtime/state/projections/diagnose.json','r',encoding='utf-8'))\n"
        "findings=d.get('findings',[])\n"
        "sev_rank={'FAIL':2,'WARN':1,'INFO':0}\n"
        "worst=0\n"
        "for f in findings:\n"
        "    sev=f.get('severity','INFO')\n"
        "    worst=max(worst, sev_rank.get(sev,0))\n"
        "    print(f\"{sev}: {f.get('code')} - {f.get('message')}\")\n"
        "    print(f\"  action: {f.get('action')}\")\n"
        "if worst==2: sys.exit(20)\n"
        "if worst==1: sys.exit(10)\n"
        "sys.exit(0)\n"
        "PY\n"
        "    ;;\n\n"
        "  *)\n"
    )

p.write_text(s, encoding="utf-8")
print("OK: ops patched with diagnose")
PY

chmod +x runtime/bin/ops
echo "OK: phase 78 ops populate complete"
