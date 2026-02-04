#!/usr/bin/env bash
# populate/01_populate.sh
# Phase 0.2 POPULATE: write inert contract content + adapter stubs only.
# Writes:
#   logs/populate.files.json
#   logs/populate.hashes.json
#
# Forbidden:
# - creating new files outside BUILD skeleton
# - executing runtime
# - modifying specs

set -euo pipefail

# Preconditions
req=(
  "logs/build.manifest.json"
  "specs/system.md"
  "specs/constraints.md"
  "specs/phases.md"
  "runtime/schema/host_adapter_contract.json"
)

for f in "${req[@]}"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: Missing required precondition: $f" >&2
    exit 1
  fi
done

mkdir -p logs

# --- Populate: host_adapter_contract.json (inert JSON schema-like contract) ---
cat > runtime/schema/host_adapter_contract.json <<'EOF'
{
  "schema_version": "0.1",
  "contract": "host_adapter",
  "rules": {
    "canonical_entrypoint": "runtime/bin/app_entry",
    "purity": "Adapters are pure translators. No business logic. No semantic changes.",
    "typed_paths": "Adapters must not introduce untyped string paths into core execution.",
    "no_os_detection_outside_adapters": true
  },
  "required_files": {
    "linux":   ["manifest.json", "install.sh", "uninstall.sh", "invoke.sh"],
    "windows": ["manifest.json", "install.ps1", "uninstall.ps1", "invoke.ps1"],
    "macos":   ["manifest.json", "install.sh", "uninstall.sh", "invoke.sh"]
  },
  "manifest_schema": {
    "type": "object",
    "required": ["host", "entrypoint", "capabilities", "args_policy"],
    "properties": {
      "host": { "type": "string", "enum": ["linux", "windows", "macos"] },
      "entrypoint": { "type": "string", "const": "runtime/bin/app_entry" },
      "capabilities": {
        "type": "object",
        "required": ["filesystem", "network"],
        "properties": {
          "filesystem": { "type": "string", "enum": ["none", "read", "write"] },
          "network": { "type": "string", "enum": ["none", "outbound"] }
        }
      },
      "args_policy": {
        "type": "object",
        "required": ["allow_untyped_paths"],
        "properties": {
          "allow_untyped_paths": { "type": "boolean", "const": false }
        }
      }
    }
  }
}
EOF

# --- Populate: adapter manifests + inert scripts (no real logic) ---

# Linux
cat > runtime/host_adapters/linux/manifest.json <<'EOF'
{
  "host": "linux",
  "entrypoint": "runtime/bin/app_entry",
  "capabilities": { "filesystem": "read", "network": "none" },
  "args_policy": { "allow_untyped_paths": false }
}
EOF

cat > runtime/host_adapters/linux/install.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "install: linux adapter (stub)"
EOF

cat > runtime/host_adapters/linux/uninstall.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "uninstall: linux adapter (stub)"
EOF

cat > runtime/host_adapters/linux/invoke.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Pure translator: invoke canonical entrypoint only.
exec ../../bin/app_entry "$@"
EOF

# Windows
cat > runtime/host_adapters/windows/manifest.json <<'EOF'
{
  "host": "windows",
  "entrypoint": "runtime/bin/app_entry",
  "capabilities": { "filesystem": "read", "network": "none" },
  "args_policy": { "allow_untyped_paths": false }
}
EOF

cat > runtime/host_adapters/windows/install.ps1 <<'EOF'
Write-Output "install: windows adapter (stub)"
EOF

cat > runtime/host_adapters/windows/uninstall.ps1 <<'EOF'
Write-Output "uninstall: windows adapter (stub)"
EOF

cat > runtime/host_adapters/windows/invoke.ps1 <<'EOF'
# Pure translator: invoke canonical entrypoint only.
& "$PSScriptRoot\..\..\bin\app_entry" @args
EOF

# macOS
cat > runtime/host_adapters/macos/manifest.json <<'EOF'
{
  "host": "macos",
  "entrypoint": "runtime/bin/app_entry",
  "capabilities": { "filesystem": "read", "network": "none" },
  "args_policy": { "allow_untyped_paths": false }
}
EOF

cat > runtime/host_adapters/macos/install.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "install: macos adapter (stub)"
EOF

cat > runtime/host_adapters/macos/uninstall.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "uninstall: macos adapter (stub)"
EOF

cat > runtime/host_adapters/macos/invoke.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Pure translator: invoke canonical entrypoint only.
exec ../../bin/app_entry "$@"
EOF

# Ensure executable bits for sh files
chmod +x runtime/host_adapters/linux/*.sh runtime/host_adapters/macos/*.sh runtime/host_adapters/linux/invoke.sh runtime/host_adapters/macos/invoke.sh

# --- Logging: files populated + sha256 hashes ---

# -----------------------------
# Phase 0.3 — Typed Path Model
# -----------------------------

cat > runtime/schema/typed_path_contract.json <<'EOT'
{
  "schema_version": "0.1",
  "contract": "typed_path",
  "types": {
    "HostPath": "host-specific OS path representation",
    "LogicalPath": "host-agnostic identifier (namespace, key)",
    "MemoryPath": "resolved content with provenance (hash, loaded_at)"
  },
  "allowed_transitions": [
    { "name": "adapt",   "from": "HostPath",    "to": "LogicalPath" },
    { "name": "resolve", "from": "LogicalPath", "to": "MemoryPath" }
  ],
  "forbidden_transitions": [
    { "from": "HostPath", "to": "MemoryPath", "reason": "No direct host-to-memory resolution allowed" }
  ],
  "rules": {
    "no_untyped_string_paths_in_runtime_execution": true
  }
}
EOT

cat > runtime/core/path_model.py <<'EOT'
from __future__ import annotations
from dataclasses import dataclass
from typing import Literal


@dataclass(frozen=True)
class HostPath:
    raw: str


@dataclass(frozen=True)
class LogicalPath:
    namespace: str
    key: str


@dataclass(frozen=True)
class MemoryPath:
    logical: LogicalPath
    sha256: str
    loaded_at_utc: str


TransitionName = Literal["adapt", "resolve"]


def adapt(host: HostPath) -> LogicalPath:
    return LogicalPath(namespace="host", key=host.raw)


def resolve(logical: LogicalPath, sha256: str, loaded_at_utc: str) -> MemoryPath:
    return MemoryPath(logical=logical, sha256=sha256, loaded_at_utc=loaded_at_utc)


def forbid_host_to_memory(_host: HostPath) -> None:
    raise RuntimeError("Forbidden transition: HostPath -> MemoryPath")
EOT


# -----------------------------
# Phase 0.4 — Capability Lattice
# -----------------------------

cat > runtime/schema/capability_lattice.json <<'EOT'
{
  "schema_version": "0.1",
  "contract": "capability_lattice",
  "description": "Meet-semilattice for execution capability validation.",
  "elements": ["BOTTOM", "none", "read", "write"],
  "order": {
    "BOTTOM": [],
    "none": ["BOTTOM"],
    "read": ["none", "BOTTOM"],
    "write": ["read", "none", "BOTTOM"]
  },
  "meet_table": {
    "BOTTOM": {"BOTTOM":"BOTTOM","none":"BOTTOM","read":"BOTTOM","write":"BOTTOM"},
    "none":   {"BOTTOM":"BOTTOM","none":"none","read":"none","write":"none"},
    "read":   {"BOTTOM":"BOTTOM","none":"none","read":"read","write":"read"},
    "write":  {"BOTTOM":"BOTTOM","none":"none","read":"read","write":"write"}
  },
  "rule": {
    "execution_valid_iff_meet_not_bottom": true
  }
}
EOT

cat > runtime/core/capability.py <<'EOT'
from __future__ import annotations
from dataclasses import dataclass
from typing import Dict


@dataclass(frozen=True)
class CapabilityLattice:
    """Simple meet-semilattice implementation (pure, no IO)."""
    meet_table: Dict[str, Dict[str, str]]
    bottom: str = "BOTTOM"

    def meet(self, a: str, b: str) -> str:
        return self.meet_table.get(a, {}).get(b, self.bottom)


def meet_all(lattice: CapabilityLattice, *caps: str) -> str:
    """Meet of many elements; returns BOTTOM if any pair is undefined."""
    if not caps:
        return lattice.bottom
    acc = caps[0]
    for c in caps[1:]:
        acc = lattice.meet(acc, c)
    return acc


def execution_allowed(lattice: CapabilityLattice, *caps: str) -> bool:
    return meet_all(lattice, *caps) != lattice.bottom
EOT


# -----------------------------
# Phase 0.5 — Command Registry
# -----------------------------

cat > runtime/schema/command_registry.json <<'EOT'
{
  "schema_version": "0.1",
  "contract": "command_registry",
  "commands": {
    "noop": {
      "description": "No operation. Validation-only.",
      "required_capabilities": {
        "host": "none",
        "context": "none",
        "runtime": "read",
        "command": "none",
        "financial": "none"
      },
      "args_schema": {
        "type": "object",
        "additionalProperties": false,
        "properties": {}
      }
    },
    "validate": {
      "description": "Validate a request against schemas only.",
      "required_capabilities": {
        "host": "none",
        "context": "none",
        "runtime": "read",
        "command": "read",
        "financial": "none"
      },
      "args_schema": {
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "command": {"type": "string"},
          "args": {"type": "object"}
        },
        "required": ["command", "args"]
      }
    }
  }
}
EOT

# runtime/core/executor.py — validation-only stub (no IO, no external calls)
cat > runtime/core/executor.py <<'EOT'
from __future__ import annotations
from dataclasses import dataclass
from typing import Dict, Any

from .capability import CapabilityLattice, execution_allowed


@dataclass(frozen=True)
class ExecutionContext:
    host: str
    context: str
    runtime: str
    command: str
    financial: str


class RegistryError(Exception):
    pass


def validate_command_request(registry: Dict[str, Any], name: str, args: Dict[str, Any]) -> None:
    if name not in registry.get("commands", {}):
        raise RegistryError(f"Unknown command: {name}")
    # Args schema validation is deferred (no jsonschema dependency in Phase 0).
    if not isinstance(args, dict):
        raise RegistryError("args must be an object")


def capabilities_for_command(registry: Dict[str, Any], name: str) -> Dict[str, str]:
    cmd = registry["commands"][name]
    return cmd["required_capabilities"]


def can_execute(lattice: CapabilityLattice, ctx: ExecutionContext, req: Dict[str, str]) -> bool:
    return execution_allowed(lattice, ctx.host, ctx.context, ctx.runtime, ctx.command, ctx.financial) and \
           execution_allowed(lattice, req["host"], req["context"], req["runtime"], req["command"], req["financial"])
EOT

populated_files=(
  runtime/schema/host_adapter_contract.json
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
)

# Write logs/populate.files.json
printf "%s\n" "${populated_files[@]}" | sort | awk '
BEGIN{print "["}
{
  gsub(/\\/,"\\\\",$0); gsub(/"/,"\\\"",$0);
  printf "%s\"%s\"", (NR==1?"":","), $0
}
END{print "]"}
' > logs/populate.files.json

# Write logs/populate.hashes.json
# Use sha256sum if available; fallback to shasum -a 256
hash_cmd=""
if command -v sha256sum >/dev/null 2>&1; then
  hash_cmd="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  hash_cmd="shasum -a 256"
else
  echo "ERROR: Need sha256sum or shasum for hashing." >&2
  exit 2
fi

tmp="$(mktemp)"
for f in "${populated_files[@]}"; do
  $hash_cmd "$f" >> "$tmp"
done

# Convert to JSON: { "file": "...", "sha256": "..." } list
awk '
BEGIN{print "["}
{
  # sha256sum format: HASH  FILE
  hash=$1
  $1=""
  sub(/^ +/,"",$0)
  file=$0
  gsub(/\\/,"\\\\",file); gsub(/"/,"\\\"",file)
  printf "%s{\"file\":\"%s\",\"sha256\":\"%s\"}", (NR==1?"":","), file, hash
}
END{print "]"}
' "$tmp" > logs/populate.hashes.json

rm -f "$tmp"

echo "✅ Phase 0.2 POPULATE complete."
echo "Wrote: logs/populate.files.json"
echo "Wrote: logs/populate.hashes.json"
