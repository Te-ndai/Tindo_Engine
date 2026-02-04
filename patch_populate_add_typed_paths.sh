#!/usr/bin/env bash
set -euo pipefail

f="populate/01_populate.sh"
[ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }

# 1) Insert typed path generation BEFORE populated_files=(
# Only if not already present
if ! grep -q 'typed_path_contract.json' "$f"; then
  # Insert block right before "populated_files=("
  awk '
    BEGIN{inserted=0}
    /populated_files=\(/ && inserted==0 {
      print ""
      print "# -----------------------------"
      print "# Phase 0.3 — Typed Path Model"
      print "# -----------------------------"
      print ""
      print "cat > runtime/schema/typed_path_contract.json <<'\''EOT'\''"
      print "{"
      print "  \"schema_version\": \"0.1\","
      print "  \"contract\": \"typed_path\","
      print "  \"types\": {"
      print "    \"HostPath\": \"host-specific OS path representation\","
      print "    \"LogicalPath\": \"host-agnostic identifier (namespace, key)\","
      print "    \"MemoryPath\": \"resolved content with provenance (hash, loaded_at)\""
      print "  },"
      print "  \"allowed_transitions\": ["
      print "    { \"name\": \"adapt\",   \"from\": \"HostPath\",    \"to\": \"LogicalPath\" },"
      print "    { \"name\": \"resolve\", \"from\": \"LogicalPath\", \"to\": \"MemoryPath\" }"
      print "  ],"
      print "  \"forbidden_transitions\": ["
      print "    { \"from\": \"HostPath\", \"to\": \"MemoryPath\", \"reason\": \"No direct host-to-memory resolution allowed\" }"
      print "  ],"
      print "  \"rules\": {"
      print "    \"no_untyped_string_paths_in_runtime_execution\": true"
      print "  }"
      print "}"
      print "EOT"
      print ""
      print "cat > runtime/core/path_model.py <<'\''EOT'\''"
      print "from __future__ import annotations"
      print "from dataclasses import dataclass"
      print "from typing import Literal"
      print ""
      print ""
      print "@dataclass(frozen=True)"
      print "class HostPath:"
      print "    raw: str"
      print ""
      print ""
      print "@dataclass(frozen=True)"
      print "class LogicalPath:"
      print "    namespace: str"
      print "    key: str"
      print ""
      print ""
      print "@dataclass(frozen=True)"
      print "class MemoryPath:"
      print "    logical: LogicalPath"
      print "    sha256: str"
      print "    loaded_at_utc: str"
      print ""
      print ""
      print "TransitionName = Literal[\"adapt\", \"resolve\"]"
      print ""
      print ""
      print "def adapt(host: HostPath) -> LogicalPath:"
      print "    return LogicalPath(namespace=\"host\", key=host.raw)"
      print ""
      print ""
      print "def resolve(logical: LogicalPath, sha256: str, loaded_at_utc: str) -> MemoryPath:"
      print "    return MemoryPath(logical=logical, sha256=sha256, loaded_at_utc=loaded_at_utc)"
      print ""
      print ""
      print "def forbid_host_to_memory(_host: HostPath) -> None:"
      print "    raise RuntimeError(\"Forbidden transition: HostPath -> MemoryPath\")"
      print "EOT"
      print ""
      inserted=1
    }
    {print}
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
fi

# 2) Ensure populated_files includes typed path outputs
if ! grep -q 'runtime/schema/typed_path_contract.json' "$f"; then
  sed -i '/populated_files=(/a\  runtime/schema/typed_path_contract.json\n  runtime/core/path_model.py' "$f"
fi

echo "OK: populate/01_populate.sh patched for typed paths."
