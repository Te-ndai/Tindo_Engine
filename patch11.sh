#!/usr/bin/env bash
set -euo pipefail

OPS="runtime/bin/ops"

python3 - <<'PY'
import pathlib

p = pathlib.Path("runtime/bin/ops")
lines = p.read_text(encoding="utf-8").splitlines()

out = []
i = 0
n = len(lines)

while i < n:
    line = lines[i]

    # Replace diagnose block
    if line.strip() == "diagnose)":
        out.extend([
            "  diagnose)",
            "    CHAIN_OK=1",
            "    if ! ./runtime/bin/logchain_append >/dev/null 2>&1; then",
            "      CHAIN_OK=0",
            "    fi",
            "",
            "    ./runtime/bin/rebuild_projections system_status >/dev/null || true",
            "    ./runtime/bin/rebuild_projections diagnose >/dev/null || true",
            "",
            "    python3 - <<'PY'",
            "import json, os, sys",
            "from datetime import datetime, timezone",
            "",
            "path='runtime/state/projections/diagnose.json'",
            "now=datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')",
            "",
            "if not os.path.exists(path):",
            "    print(f'DIAGNOSE {now} STATUS=FAIL')",
            "    print('FAIL=1 WARN=0 INFO=0')",
            "    print('[FAIL] DIAGNOSE_MISSING: diagnose.json missing')",
            "    print('  action: ./runtime/bin/rebuild_projections diagnose')",
            "    sys.exit(20)",
            "",
            "d=json.load(open(path,'r',encoding='utf-8'))",
            "findings=d.get('findings',[])",
            "sev_order={'FAIL':0,'WARN':1,'INFO':2}",
            "findings=sorted(findings, key=lambda f:(sev_order.get(f.get('severity','INFO'),2), f.get('code','')))",
            "",
            "counts={'FAIL':0,'WARN':0,'INFO':0}",
            "sev_rank={'FAIL':2,'WARN':1,'INFO':0}",
            "worst=0",
            "",
            "for f in findings:",
            "    sev=f.get('severity','INFO')",
            "    counts[sev]=counts.get(sev,0)+1",
            "    worst=max(worst, sev_rank.get(sev,0))",
            "",
            "status='OK' if worst==0 else ('WARN' if worst==1 else 'FAIL')",
            "print(f'DIAGNOSE {now} STATUS={status}')",
            "print(f\"FAIL={counts.get('FAIL',0)} WARN={counts.get('WARN',0)} INFO={counts.get('INFO',0)}\")",
            "",
            "for f in findings:",
            "    print(f\"[{f.get('severity')}] {f.get('code')}: {f.get('message')}\")",
            "    print(f\"  action: {f.get('action')}\")",
            "",
            "if worst==2: sys.exit(20)",
            "if worst==1: sys.exit(10)",
            "sys.exit(0)",
            "PY",
            "    rc=$?",
            "    if [ \"${CHAIN_OK}\" -eq 0 ] && [ \"$rc\" -ne 20 ]; then",
            "      exit 20",
            "    fi",
            "    exit \"$rc\"",
            "    ;;"
        ])
        i += 1
        while i < n and lines[i].strip() != ";;":
            i += 1
        i += 1
        continue

    # Insert report block before default case
    if line.strip() == "*)":
        out.extend([
            "  report)",
            "    mkdir -p runtime/state/reports",
            "    ./runtime/bin/ops diagnose > runtime/state/reports/diagnose.txt || true",
            "    cp -f runtime/state/projections/diagnose.json runtime/state/reports/diagnose.json 2>/dev/null || true",
            "    echo \"OK: wrote runtime/state/reports/diagnose.txt + diagnose.json\"",
            "    exit 0",
            "    ;;",
            "",
            "  *)"
        ])
        i += 1
        continue

    out.append(line)
    i += 1

p.write_text(\"\\n\".join(out) + \"\\n\", encoding=\"utf-8\")
print(\"OK: ops patched with stable diagnose + report\")
PY

chmod +x runtime/bin/ops
echo "OK: patch11 applied"
