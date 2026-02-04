#!/usr/bin/env bash
set -euo pipefail
die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo "==> $*" >&2; }

V="runtime/bin/verify_release_signatures"
DEF="runtime/state/keys/release_pub.pem"

[ -f "$V" ] || die "missing: $V"

note "Proof: show the exact guard line we will patch…"
grep -nF '[ -n "$PUB" ] || die "missing --pub"' "$V" | sed 's/^/   /' >&2 || die "guard line not found; refusing to patch"

cp -a "$V" "$V.bak.$(date -u +%Y%m%dT%H%M%SZ)"

note "Applying deterministic insert before the guard…"
python3 - <<'PY'
import sys

path="runtime/bin/verify_release_signatures"
needle='[ -n "$PUB" ] || die "missing --pub"'

lines=open(path,'r',encoding='utf-8').read().splitlines(True)
out=[]
inserted=False

block = (
  '# Phase 99A: default to repo public key if --pub not provided\n'
  'if [ -z "$PUB" ] && [ -f "runtime/state/keys/release_pub.pem" ]; then\n'
  '  PUB="runtime/state/keys/release_pub.pem"\n'
  'fi\n'
  '\n'
)

for line in lines:
    if (not inserted) and line.rstrip("\n") == needle:
        out.append(block)
        inserted=True
    out.append(line)

if not inserted:
    raise SystemExit("Refusing to patch: exact guard line not found during write pass.")

open(path,'w',encoding='utf-8').write("".join(out))
PY

chmod +x "$V"

note "Proof: show inserted block + guard line…"
grep -nE 'Phase 99A: default|\[ -n "\$PUB" \] \|\| die "missing --pub"' "$V" | sed 's/^/   /' >&2

note "✅ Patched verify_release_signatures default pubkey behavior"
