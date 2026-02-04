#!/usr/bin/env bash
# build/10_stage_clean_build.sh
# Phase 1 BUILD (staged): create a clean skeleton in logs/env/stage_build
# without touching current working runtime/.
#
# This proves the build is deterministic and matches specs/system.md.

set -euo pipefail

STAGE="logs/env/stage_build"
rm -rf "$STAGE"
mkdir -p "$STAGE"

# Factory skeleton
mkdir -p "$STAGE"/{build,populate,test,promote,specs,logs,runtime}

# Runtime skeleton
mkdir -p "$STAGE"/runtime/{bin,schema,core,host_adapters,simulators,state}
mkdir -p "$STAGE"/runtime/host_adapters/{linux,windows,macos}
mkdir -p "$STAGE"/runtime/simulators/slots
mkdir -p "$STAGE"/runtime/state/{logs,cache,projections}

# Placeholders (empty only)
: > "$STAGE/runtime/bin/app_entry"
chmod +x "$STAGE/runtime/bin/app_entry"

: > "$STAGE/runtime/schema/capability_lattice.json"
: > "$STAGE/runtime/schema/host_adapter_contract.json"
: > "$STAGE/runtime/schema/typed_path_contract.json"
: > "$STAGE/runtime/schema/command_registry.json"

: > "$STAGE/runtime/core/__init__.py"
: > "$STAGE/runtime/core/path_model.py"
: > "$STAGE/runtime/core/capability.py"
: > "$STAGE/runtime/core/executor.py"

: > "$STAGE/runtime/host_adapters/linux/manifest.json"
: > "$STAGE/runtime/host_adapters/linux/install.sh"
: > "$STAGE/runtime/host_adapters/linux/uninstall.sh"
: > "$STAGE/runtime/host_adapters/linux/invoke.sh"
chmod +x "$STAGE/runtime/host_adapters/linux/"*.sh

: > "$STAGE/runtime/host_adapters/windows/manifest.json"
: > "$STAGE/runtime/host_adapters/windows/install.ps1"
: > "$STAGE/runtime/host_adapters/windows/uninstall.ps1"
: > "$STAGE/runtime/host_adapters/windows/invoke.ps1"

: > "$STAGE/runtime/host_adapters/macos/manifest.json"
: > "$STAGE/runtime/host_adapters/macos/install.sh"
: > "$STAGE/runtime/host_adapters/macos/uninstall.sh"
: > "$STAGE/runtime/host_adapters/macos/invoke.sh"
chmod +x "$STAGE/runtime/host_adapters/macos/"*.sh

: > "$STAGE/runtime/simulators/README.md"
: > "$STAGE/runtime/simulators/registry.json"

# Build manifest (staged)
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
dirs_json="$(cd "$STAGE" && find . -type d -print | sort | awk 'BEGIN{print "["}{gsub(/\\/,"\\\\");gsub(/"/,"\\\"");printf "%s\"%s\"", (NR==1?"":","), $0}END{print "]"}')"
files_json="$(cd "$STAGE" && find . -type f -print | sort | awk 'BEGIN{print "["}{gsub(/\\/,"\\\\");gsub(/"/,"\\\"");printf "%s\"%s\"", (NR==1?"":","), $0}END{print "]"}')"

cat > "$STAGE/logs/build.manifest.json" <<EOF
{
  "phase": "1",
  "action": "BUILD",
  "timestamp_utc": "$ts",
  "stage_root": "$STAGE",
  "dirs": $dirs_json,
  "files": $files_json
}
EOF

echo "✅ Phase 1 BUILD (staged) complete at: $STAGE"
echo "Wrote: $STAGE/logs/build.manifest.json"
