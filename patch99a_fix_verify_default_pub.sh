#!/usr/bin/env bash
set -euo pipefail
die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo "==> $*" >&2; }

V="runtime/bin/verify_release_signatures"
PUB_DEFAULT='runtime/state/keys/release_pub.pem'

[ -f "$V" ] || die "missing: $V"
[ -x "$V" ] || chmod +x "$V" || true

note "Proving current hard requirement exists (no guessing)…"
grep -nE 'PUB=""|\[\s*-n "\$PUB"\s*\]\s*\|\|\s*die "missing --pub"' "$V" | sed 's/^/   /' >&2

cp -a "$V" "$V.bak.$(date -u +%Y%m%dT%H%M%SZ)"

note "Patching: default to $PUB_DEFAULT when --pub omitted and file exists…"

python3 - <<'PY'
import re, sys
path="runtime/bin/verify_release_signatures"
s=open(path,'r',encoding='utf-8').read().splitlines(True)

out=[]
inserted=False

# We will insert a defaulting block immediately BEFORE the line that dies on missing --pub
target = re.compile(r'^\s*\[\s*-\s*n\s*"\$PUB"\s*\]\s*\|\|\s*die\s+"missing --pub"\s*$')

for line in s:
    if (not inserted) and target.match(line.rstrip("\n")):
        out.append(f'# Phase 99A: default to repo public key if --pub not provided\n')
        out.append(f'if [ -z "$PUB" ] && [ -f "{PUB_DEFAULT}" ]; then\n')
        out.append(f'  PUB="{PUB_DEFAULT}"\n')
        out.append(f'fi\n')
        out.append('\n')
        inserted=True
    out.append(line)

if not inserted:
    raise SystemExit("Could not find the exact 'missing --pub' guard line; refusing to patch.")

# Update usage line (best effort, safe): append note about default if present
txt="".join(out)
txt = re.sub(
    r'(usage:\s*verify_release_signatures[^\n]*\n)',
    lambda m: m.group(1).rstrip("\n") + f' (default pub: {PUB_DEFAULT} if present)\\n\n',
    txt,
    count=1
)
open(path,'w',encoding='utf-8').write(txt)
PY

chmod +x "$V"

note "Proof: show the new default block + the guard line…"
grep -nE 'Phase 99A: default|default to repo public key|PUB="runtime/state/keys/release_pub.pem"|\|\| die "missing --pub"' "$V" | sed 's/^/   /' >&2

note "✅ Phase 99A verifier default applied"
