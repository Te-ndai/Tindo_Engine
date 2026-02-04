#!/usr/bin/env bash
# build/00_build.sh
# Phase 0.1 BUILD: create structure + empty placeholder files ONLY.
# Writes logs/build.manifest.json

set -euo pipefail

# Must be run from ROOT/
ROOT="."
SPECS_DIR="$ROOT/specs"
LOGS_DIR="$ROOT/logs"

req_specs=(
  "$SPECS_DIR/system.md"
  "$SPECS_DIR/constraints.md"
  "$SPECS_DIR/phases.md"
)

# Preconditions: Phase 0 must exist and be clean enough
for f in "${req_specs[@]}"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: Missing required contract: $f" >&2
    exit 1
  fi
done

mkdir -p "$LOGS_DIR"

# Enforce: relative paths only (we won't use any absolute paths)
# Enforce: Phase 0 purity (warn-only; do NOT destroy user data)
extra_dirs="$(find "$ROOT" -maxdepth 1 -mindepth 1 -type d \
  ! -name "specs" ! -name "logs" -printf "%f\n" | sort || true)"
if [ -n "$extra_dirs" ]; then
  echo "WARNING: Extra root dirs exist before BUILD (Phase 0 purity already broken):"
  echo "$extra_dirs" | sed 's/^/  - /'
fi

# --- Create factory skeleton (from specs/system.md) ---
mkdir -p build populate test promote specs logs runtime

# --- Create runtime skeleton (empty placeholders only) ---
mkdir -p runtime/bin runtime/schema runtime/core runtime/host_adapters runtime/simulators runtime/state
mkdir -p runtime/host_adapters/linux runtime/host_adapters/windows runtime/host_adapters/macos
mkdir -p runtime/simulators/slots
mkdir -p runtime/state/logs runtime/state/cache runtime/state/projections

# --- Create required placeholder files (EMPTY) ---
# runtime/bin
: > runtime/bin/app_entry
chmod +x runtime/bin/app_entry

# runtime/schema (immutable after promote, but now placeholders)
: > runtime/schema/capability_lattice.json
: > runtime/schema/host_adapter_contract.json
: > runtime/schema/typed_path_contract.json
: > runtime/schema/command_registry.json

# runtime/core (host-agnostic placeholders)
: > runtime/core/__init__.py
: > runtime/core/path_model.py
: > runtime/core/capability.py
: > runtime/core/executor.py

# runtime/host_adapters placeholders
# linux
: > runtime/host_adapters/linux/manifest.json
: > runtime/host_adapters/linux/install.sh
: > runtime/host_adapters/linux/uninstall.sh
: > runtime/host_adapters/linux/invoke.sh
chmod +x runtime/host_adapters/linux/install.sh runtime/host_adapters/linux/uninstall.sh runtime/host_adapters/linux/invoke.sh

# windows
: > runtime/host_adapters/windows/manifest.json
: > runtime/host_adapters/windows/install.ps1
: > runtime/host_adapters/windows/uninstall.ps1
: > runtime/host_adapters/windows/invoke.ps1

# macos
: > runtime/host_adapters/macos/manifest.json
: > runtime/host_adapters/macos/install.sh
: > runtime/host_adapters/macos/uninstall.sh
: > runtime/host_adapters/macos/invoke.sh
chmod +x runtime/host_adapters/macos/install.sh runtime/host_adapters/macos/uninstall.sh runtime/host_adapters/macos/invoke.sh

# runtime/simulators placeholders
: > runtime/simulators/README.md
: > runtime/simulators/registry.json

# --- Write logs/build.manifest.json deterministically ---
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

dirs_json="$(find . -type d -print | sort | awk '
BEGIN{print "["}
{
  gsub(/\\/,"\\\\",$0); gsub(/"/,"\\\"",$0);
  printf "%s\"%s\"", (NR==1?"":","), $0
}
END{print "]"}
')"

files_json="$(find . -type f -print | sort | awk '
BEGIN{print "["}
{
  gsub(/\\/,"\\\\",$0); gsub(/"/,"\\\"",$0);
  printf "%s\"%s\"", (NR==1?"":","), $0
}
END{print "]"}
')"

cat > logs/build.manifest.json <<EOF
{
  "phase": "0.1",
  "action": "BUILD",
  "timestamp_utc": "$ts",
  "notes": "Structure + empty placeholders only. No contents populated.",
  "dirs": $dirs_json,
  "files": $files_json
}
EOF

echo "✅ Phase 0.1 BUILD complete."
echo "Wrote: logs/build.manifest.json"
