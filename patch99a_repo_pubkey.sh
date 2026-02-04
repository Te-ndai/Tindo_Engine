#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo "==> $*" >&2; }

ROOT="$(pwd)"
KEYDIR="runtime/state/keys"
PRIV="$KEYDIR/release_priv.pem"
PUB="$KEYDIR/release_pub.pem"
V="runtime/bin/verify_release_signatures"
GI=".gitignore"

[ -x "$V" ] || die "missing executable: $V"

note "0) Prove openssl exists (required for keygen)…"
command -v openssl >/dev/null 2>&1 || die "openssl not found in PATH"

note "1) Ensure key directory exists…"
mkdir -p "$KEYDIR"

note "2) If pubkey already exists, do not overwrite (proof)…"
if [ -f "$PUB" ]; then
  note "Public key already present: $PUB (leaving unchanged)"
else
  note "Generating new RSA keypair (private stays local; public is committable)…"
  # Generate private key (local secret)
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$PRIV" >/dev/null 2>&1
  # Derive public key
  openssl pkey -in "$PRIV" -pubout -out "$PUB" >/dev/null 2>&1

  chmod 600 "$PRIV" || true
  chmod 644 "$PUB" || true

  note "Wrote:"
  ls -l "$PRIV" "$PUB" | sed 's/^/   /' >&2
fi

note "3) Ensure private key is gitignored (no leaks)…"
touch "$GI"
if ! grep -qE '^\s*runtime/state/keys/release_priv\.pem\s*$' "$GI"; then
  {
    echo ""
    echo "# Phase 99A: local private release signing key (DO NOT COMMIT)"
    echo "runtime/state/keys/release_priv.pem"
  } >> "$GI"
  note "Appended private key ignore rule to $GI"
else
  note "$GI already ignores release_priv.pem"
fi

note "4) Inspect verify_release_signatures for pubkey handling…"
grep -nE 'pub|PUB|pubkey|--pub' "$V" | head -n 60 | sed 's/^/   /' >&2 || true

note "5) Patch verify_release_signatures to default to repo pubkey if none provided…"
# We patch conservatively:
# - If script already defines a default PUB path, we do nothing.
# - Else we inject a default PUB assignment near the top after die().

if grep -qE 'runtime/state/keys/release_pub\.pem' "$V"; then
  note "verify_release_signatures already references repo pubkey path; no change"
else
  # backup
  cp -a "$V" "$V.bak.$(date -u +%Y%m%dT%H%M%SZ)"

  # inject after die() definition (first occurrence)
  python3 - <<'PY'
import re
path="runtime/bin/verify_release_signatures"
s=open(path,'r',encoding='utf-8').read().splitlines(True)

out=[]
inserted=False
for i,line in enumerate(s):
    out.append(line)
    if (not inserted) and re.search(r'^\s*die\(\)\s*\{', line):
        # wait until function ends (next line containing "}" on its own is not reliable in bash),
        # so instead inject right after the die() function definition block ends by detecting the first blank line after it.
        pass

# Second pass: inject after the first blank line following the die() block.
out=[]
state=0  # 0=before die,1=in die,2=after die waiting blank injected
inserted=False
for line in s:
    out.append(line)
    if state==0 and re.search(r'^\s*die\(\)\s*\{', line):
        state=1
        continue
    if state==1 and re.search(r'^\s*\}\s*$', line):
        state=2
        continue
    if state==2 and (line.strip()=="" ) and not inserted:
        out.append('PUB_DEFAULT="runtime/state/keys/release_pub.pem"\n')
        out.append('PUB="${SIGNING_PUB_PATH:-${PUB:-$PUB_DEFAULT}}"\n')
        out.append('# Phase 99A: if no pub key argument is provided, verifier tools may default to this path.\n')
        out.append('\n')
        inserted=True
        state=3

if not inserted:
    raise SystemExit("Refusing to patch: could not find safe injection point after die() block")

open(path,'w',encoding='utf-8').write("".join(out))
PY

  chmod +x "$V"
  note "Patched: $V (default PUB path injected)"
fi

note "6) Proof: show the injected/default lines (if present)…"
grep -nE 'PUB_DEFAULT=|release_pub\.pem|SIGNING_PUB_PATH' "$V" | sed 's/^/   /' >&2 || true

note "✅ Phase 99A complete"
note "Public key path (commit this): $PUB"
note "Private key path (do NOT commit): $PRIV"
