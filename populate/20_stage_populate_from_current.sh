#!/usr/bin/env bash
# populate/20_stage_populate_from_current.sh
# Phase 2 POPULATE (staged): copy populated runtime artifacts into stage runtime,
# then write stage populate logs (files + hashes).
#
# Source: ./runtime/...
# Target: logs/env/stage_build/runtime/...

set -euo pipefail

STAGE="logs/env/stage_build"
SRC_RUNTIME="runtime"
DST_RUNTIME="$STAGE/runtime"
STAGE_LOGS="$STAGE/logs"

[ -d "$STAGE" ] || { echo "ERROR: stage not found at $STAGE" >&2; exit 1; }
[ -f "$STAGE_LOGS/build.manifest.json" ] || { echo "ERROR: missing $STAGE_LOGS/build.manifest.json" >&2; exit 1; }

# Ensure destination skeleton exists
[ -d "$DST_RUNTIME" ] || { echo "ERROR: missing stage runtime at $DST_RUNTIME" >&2; exit 1; }

# List of files we are allowed to populate (must already exist in stage)
files=(
  # schema
  runtime/schema/host_adapter_contract.json
  runtime/schema/typed_path_contract.json
  runtime/schema/capability_lattice.json
  runtime/schema/command_registry.json

  # core
  runtime/core/__init__.py
  runtime/core/path_model.py
  runtime/core/capability.py
  runtime/core/executor.py

  # host adapters
  runtime/host_adapters/linux/manifest.json
  runtime/host_adapters/linux/install.sh
  runtime/host_adapters/linux/uninstall.sh
  runtime/host_adapters/linux/invoke.sh

  runtime/host_adapters/windows/manifest.json
  runtime/host_adapters/windows/install.ps1
  runtime/host_adapters/windows/uninstall.ps1
  runtime/host_adapters/windows/invoke.ps1

  runtime/host_adapters/macos/manifest.json
  runtime/host_adapters/macos/install.sh
  runtime/host_adapters/macos/uninstall.sh
  runtime/host_adapters/macos/invoke.sh

  # simulators
  runtime/simulators/README.md
  runtime/simulators/registry.json
)

# Validate: all sources exist, all destinations exist (no new files)
for rel in "${files[@]}"; do
  [ -f "$SRC_RUNTIME/${rel#runtime/}" ] || { echo "ERROR: source missing: $SRC_RUNTIME/${rel#runtime/}" >&2; exit 2; }
  [ -f "$DST_RUNTIME/${rel#runtime/}" ] || { echo "ERROR: stage placeholder missing: $DST_RUNTIME/${rel#runtime/}" >&2; exit 3; }
done

# Copy content (preserve mode where relevant)
for rel in "${files[@]}"; do
  src="$SRC_RUNTIME/${rel#runtime/}"
  dst="$DST_RUNTIME/${rel#runtime/}"
  cp -f "$src" "$dst"
done

# Ensure executable bits for stage sh files and app_entry
chmod +x "$STAGE/runtime/bin/app_entry" || true
chmod +x "$STAGE/runtime/host_adapters/linux/"*.sh "$STAGE/runtime/host_adapters/macos/"*.sh 2>/dev/null || true

# Write stage populate.files.json
mkdir -p "$STAGE_LOGS"
printf "%s\n" "${files[@]}" | sort | awk '
BEGIN{print "["}
{
  gsub(/\\/,"\\\\",$0); gsub(/"/,"\\\"",$0);
  printf "%s\"%s\"", (NR==1?"":","), $0
}
END{print "]"}
' > "$STAGE_LOGS/populate.files.json"

# Hashing
hash_cmd=""
if command -v sha256sum >/dev/null 2>&1; then
  hash_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  hash_cmd="shasum -a 256"
else
  echo "ERROR: Need sha256sum or shasum for hashing." >&2
  exit 4
fi

tmp="$(mktemp)"
for rel in "${files[@]}"; do
  # hashes from the stage target (so log reflects the staged build)
  $hash_cmd "$DST_RUNTIME/${rel#runtime/}" >> "$tmp"
done

awk '
BEGIN{print "["}
{
  hash=$1
  $1=""
  sub(/^ +/,"",$0)
  file=$0
  gsub(/\\/,"\\\\",file); gsub(/"/,"\\\"",file)
  printf "%s{\"file\":\"%s\",\"sha256\":\"%s\"}", (NR==1?"":","), file, hash
}
END{print "]"}
' "$tmp" > "$STAGE_LOGS/populate.hashes.json"

rm -f "$tmp"

echo "✅ Phase 2 POPULATE (staged) complete."
echo "Wrote: $STAGE_LOGS/populate.files.json"
echo "Wrote: $STAGE_LOGS/populate.hashes.json"
