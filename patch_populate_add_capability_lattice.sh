#!/usr/bin/env bash
set -euo pipefail

f="populate/01_populate.sh"
[ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }

# Insert capability lattice block before populated_files=( if not present
if ! grep -q 'capability_lattice.json' "$f"; then
  awk '
    BEGIN{inserted=0}
    /populated_files=\(/ && inserted==0 {
      print ""
      print "# -----------------------------"
      print "# Phase 0.4 — Capability Lattice"
      print "# -----------------------------"
      print ""
      print "cat > runtime/schema/capability_lattice.json <<'\''EOT'\''"
      print "{"
      print "  \"schema_version\": \"0.1\","
      print "  \"contract\": \"capability_lattice\","
      print "  \"description\": \"Meet-semilattice for execution capability validation.\","
      print "  \"elements\": [\"BOTTOM\", \"none\", \"read\", \"write\"],"
      print "  \"order\": {"
      print "    \"BOTTOM\": [],"
      print "    \"none\": [\"BOTTOM\"],"
      print "    \"read\": [\"none\", \"BOTTOM\"],"
      print "    \"write\": [\"read\", \"none\", \"BOTTOM\"]"
      print "  },"
      print "  \"meet_table\": {"
      print "    \"BOTTOM\": {\"BOTTOM\":\"BOTTOM\",\"none\":\"BOTTOM\",\"read\":\"BOTTOM\",\"write\":\"BOTTOM\"},"
      print "    \"none\":   {\"BOTTOM\":\"BOTTOM\",\"none\":\"none\",\"read\":\"none\",\"write\":\"none\"},"
      print "    \"read\":   {\"BOTTOM\":\"BOTTOM\",\"none\":\"none\",\"read\":\"read\",\"write\":\"read\"},"
      print "    \"write\":  {\"BOTTOM\":\"BOTTOM\",\"none\":\"none\",\"read\":\"read\",\"write\":\"write\"}"
      print "  },"
      print "  \"rule\": {"
      print "    \"execution_valid_iff_meet_not_bottom\": true"
      print "  }"
      print "}"
      print "EOT"
      print ""
      print "cat > runtime/core/capability.py <<'\''EOT'\''"
      print "from __future__ import annotations"
      print "from dataclasses import dataclass"
      print "from typing import Dict"
      print ""
      print ""
      print "@dataclass(frozen=True)"
      print "class CapabilityLattice:"
      print "    \"\"\"Simple meet-semilattice implementation (pure, no IO).\"\"\""
      print "    meet_table: Dict[str, Dict[str, str]]"
      print "    bottom: str = \"BOTTOM\""
      print ""
      print "    def meet(self, a: str, b: str) -> str:"
      print "        return self.meet_table.get(a, {}).get(b, self.bottom)"
      print ""
      print ""
      print "def meet_all(lattice: CapabilityLattice, *caps: str) -> str:"
      print "    \"\"\"Meet of many elements; returns BOTTOM if any pair is undefined.\"\"\""
      print "    if not caps:"
      print "        return lattice.bottom"
      print "    acc = caps[0]"
      print "    for c in caps[1:]:"
      print "        acc = lattice.meet(acc, c)"
      print "    return acc"
      print ""
      print ""
      print "def execution_allowed(lattice: CapabilityLattice, *caps: str) -> bool:"
      print "    return meet_all(lattice, *caps) != lattice.bottom"
      print "EOT"
      print ""
      inserted=1
    }
    {print}
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
fi

# Ensure populated_files includes the new outputs
if ! grep -q 'runtime/schema/capability_lattice.json' "$f"; then
  sed -i '/populated_files=(/a\  runtime/schema/capability_lattice.json\n  runtime/core/capability.py' "$f"
fi

echo "OK: populate/01_populate.sh patched for capability lattice."
