#!/usr/bin/env bash
set -euo pipefail

note(){ echo "==> $*" >&2; }

note "A) Which validate_manifest is actually being executed?"
ls -l runtime/bin/validate_manifest | sed 's/^/   /' >&2
sha256sum runtime/bin/validate_manifest | sed 's/^/   /' >&2
head -n 3 runtime/bin/validate_manifest | sed 's/^/   /' >&2

note "B) Show validator signing logic (lines 60-90)"
nl -ba runtime/bin/validate_manifest | sed -n '55,95p' >&2

note "C) Run release_bundle under trace and capture validate_manifest invocation"
RID="$(date -u +%Y%m%dT%H%M%SZ)"; export RELEASE_ID="$RID"
set +e
bash -x ./runtime/bin/release_bundle --release-id "$RELEASE_ID" 2>&1 | tee /tmp/trace_release_bundle.txt
rc=${PIPESTATUS[0]}
set -e
echo "release_bundle rc=$rc" >&2

note "D) Extract the manifest path that release_bundle passed to validate_manifest"
VM_LINE="$(grep -nE '\./runtime/bin/validate_manifest ' /tmp/trace_release_bundle.txt | tail -n 1 || true)"
echo "$VM_LINE" | sed 's/^/   /' >&2
MANIFEST="$(echo "$VM_LINE" | sed -E 's/.*validate_manifest[[:space:]]+"?([^"[:space:]]+)"?.*/\1/')"

if [[ -z "${MANIFEST:-}" || ! -f "$MANIFEST" ]]; then
  note "Could not parse manifest path from trace; falling back to expected path"
  MANIFEST="runtime/state/releases/release_${RELEASE_ID}.json"
fi

note "E) Inspect signing fields of the EXACT manifest being validated: $MANIFEST"
python3 - <<PY
import json
m=json.load(open("$MANIFEST","r",encoding="utf-8"))
for k in ["signing_alg","signing_pub_fingerprint_sha256","manifest_sig_b64_path","bundle_sig_b64_path"]:
    print(k, "=>", repr(m.get(k, "<ABSENT>")))
PY

note "F) Run validator on that same manifest and show stderr"
set +e
./runtime/bin/validate_manifest "$MANIFEST" 1>/tmp/val_out.txt 2>/tmp/val_err.txt
vrc=$?
set -e
echo "validate_manifest rc=$vrc" >&2
sed 's/^/   /' /tmp/val_err.txt >&2 || true
