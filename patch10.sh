#!/usr/bin/env bash
set -euo pipefail

OPS="runtime/bin/ops"

# Split ops into: before diagnose | diagnose | after diagnose
python3 - <<'PY'
import pathlib, sys

p = pathlib.Path("runtime/bin/ops")
lines = p.read_text(encoding="utf-8").splitlines()

out = []
i = 0
n = len(lines)

while i < n:
    line = lines[i]

    # Detect start of diagnose case
    if line.strip() == "diagnose)":
        # Write new diagnose case
        out.append("  diagnose)")
        out.append("    # Preflight: auto-append chain and refresh status")
        out.append("    CHAIN_OK=1")
        out.append("    if ! ./runtime/bin/logchain_append >/dev/null 2>&1; then")
        out.append("      CHAIN_OK=0")
        out.append("    fi")
        out.append("")
        out.append("    ./runtime/bin/rebuild_projections system_status >/dev/null || true")
        out.append("    ./runtime/bin/rebuild_projections diagnose >/dev/null || true")
        out.append("")
        out.append("    python3 - <<'PY'")
        out.append("import json, os, sys")
        out.append("path='runtime/state/projections/diagnose.json'")
        out.append("if not os.path.exists(path):")
        out.append("    print('FAIL: DIAGNOSE_MISSING - diagnose.json missing')")
        out.append("    print('  action: ./runtime/bin/rebuild_projections diagnose')")
        out.append("    sys.exit(20)")
        out.append("")
        out.append("d=json.load(open(path,'r',encoding='utf-8'))")
        out.append("findings=d.get('findings',[])")
        out.append("sev_rank={'FAIL':2,'WARN':1,'INFO':0}")
        out.append("worst=0")
        out.append("for f in findings:")
        out.append("    sev=f.get('severity','INFO')")
        out.append("    worst=max(worst, sev_rank.get(sev,0))")
        out.append("    print(f\"{sev}: {f.get('code')} - {f.get('message')}\")")
        out.append("    print(f\"  action: {f.get('action')}\")")
        out.append("if worst==2: sys.exit(20)")
        out.append("if worst==1: sys.exit(10)")
        out.append("sys.exit(0)")
        out.append("PY")
        out.append("    rc=$?")
        out.append("    if [ \"${CHAIN_OK}\" -eq 0 ] && [ \"$rc\" -ne 20 ]; then")
        out.append("      exit 20")
        out.append("    fi")
        out.append("    exit \"$rc\"")
        out.append("    ;;")

        # Skip old diagnose block
        i += 1
        while i < n and lines[i].strip() != ";;":
            i += 1
        i += 1
        continue

    out.append(line)
    i += 1

p.write_text("\n".join(out) + "\n", encoding="utf-8")
print("OK: ops diagnose replaced with preflight version")
PY

chmod +x runtime/bin/ops
echo "OK: patch10 applied"
