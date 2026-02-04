#!/usr/bin/env bash
set -euo pipefail

# Patch ops: add auto logchain_append + propagate failure
python3 - <<'PY'
import pathlib

p=pathlib.Path("runtime/bin/ops")
s=p.read_text(encoding="utf-8").splitlines()

out=[]
inserted=False
for line in s:
    out.append(line)
    if line.strip() == 'status_summary() {':
        out.append('  # Auto-maintain log chain (append-only). If this fails, status should FAIL.')
        out.append('  CHAIN_OK=1')
        out.append('  if ! ./runtime/bin/logchain_append >/dev/null 2>&1; then')
        out.append('    CHAIN_OK=0')
        out.append('  fi')
        inserted=True

# Now ensure python exit honors CHAIN_OK
txt="\n".join(out)
# Find the python block end where it exits based on FAIL/STALE/OK.
# We'll force FAIL if CHAIN_OK==0 by wrapping status_summary's return code.
# Easiest: after python block, if CHAIN_OK==0 and python returned 0/10, force 20.
if "CHAIN_OK=1" not in txt:
    raise SystemExit("ERROR: insertion point not found")

# Replace 'python3 - <<'PY'' invocation with capturing exit code
txt=txt.replace(
'  python3 - <<\'PY\'',
'  python3 - <<\'PY\''
)

# Append post-python adjustment: locate line containing 'PY' terminator and add adjustment after it.
lines=txt.splitlines()
final=[]
for i,line in enumerate(lines):
    final.append(line)
    if line.strip() == "PY" and i>0 and lines[i-1].strip() == "sys.exit(0)":
        # too specific; fallback: add after any PY line within status_summary by checking indentation
        pass

# Safer: inject after the python heredoc in status_summary by searching for 'PY' line with 2-space indent
final=[]
in_status=False
for line in lines:
    final.append(line)
    if line.strip()=="status_summary() {":
        in_status=True
    if in_status and line.strip()=="PY":
        # heredoc terminator
        final.append('  rc=$?')
        final.append('  if [ "${CHAIN_OK}" -eq 0 ] && [ "$rc" -ne 20 ]; then')
        final.append('    exit 20')
        final.append('  fi')
        final.append('  exit "$rc"')
        # The function should exit here, so subsequent '}' still ok but unreachable.
        in_status=False

p.write_text("\n".join(final)+ "\n", encoding="utf-8")
print("OK: patched ops with autochain")
PY

chmod +x runtime/bin/ops
echo "OK: phase 77 populate complete"
