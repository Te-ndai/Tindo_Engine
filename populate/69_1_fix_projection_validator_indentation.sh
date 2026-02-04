#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import pathlib

p = pathlib.Path("runtime/core/projections.py")
lines = p.read_text(encoding="utf-8").splitlines()

out = []
i = 0
extracted = []
inside_broken = False

while i < len(lines):
    line = lines[i]

    # Detect broken sequence
    if line.startswith("def validate_projection_output") and i+1 < len(lines):
        if lines[i+1].startswith("def _validate_system_status_rows"):
            # Skip broken validate_projection_output header
            validate_sig = line
            i += 1

            # Extract helper function
            while i < len(lines) and not lines[i].startswith("def rebuild_projection"):
                extracted.append(lines[i])
                i += 1

            # Re-emit helper FIRST
            out.extend(extracted)
            out.append("")

            # Re-emit validate_projection_output properly
            out.append(validate_sig)
            out.extend([
                "    if not isinstance(data, dict):",
                "        raise ProjectionError(\"projection output must be an object\")",
                "",
                "    # Envelope validation",
                "    _validate_required_and_types(",
                "        data,",
                "        envelope.get(\"required_fields\", []),",
                "        envelope.get(\"field_types\", {}),",
                "    )",
                "",
                "    name = data.get(\"projection\")",
                "    contracts = payloads.get(\"contracts\", {})",
                "    pc = contracts.get(name)",
                "    if pc is None:",
                "        raise ProjectionError(f\"no payload contract for projection: {name}\")",
                "",
                "    # Payload validation",
                "    _validate_required_and_types(",
                "        data,",
                "        pc.get(\"required_fields\", []),",
                "        pc.get(\"field_types\", {}),",
                "    )",
                "",
                "    # Extra row validation for system_status",
                "    if name == \"system_status\":",
                "        _validate_system_status_rows(data)",
                "",
                "    # Optional last_n item validation",
                "    last_n_item_required = pc.get(\"last_n_item_required\")",
                "    if last_n_item_required is not None:",
                "        last_n = data.get(\"last_n\")",
                "        if not isinstance(last_n, list):",
                "            raise ProjectionError(\"last_n must be a list\")",
                "        for i, item in enumerate(last_n):",
                "            if not isinstance(item, dict):",
                "                raise ProjectionError(f\"last_n[{i}] must be an object\")",
                "            for k in last_n_item_required:",
                "                if k not in item:",
                "                    raise ProjectionError(f\"last_n[{i}] missing field: {k}\")",
                "",
            ])
            continue

    out.append(line)
    i += 1

p.write_text("\n".join(out) + "\n", encoding="utf-8")
print("OK: repaired projections.py validator structure")
PY
