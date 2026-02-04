#!/usr/bin/env bash
# populate/50_populate_app_entry.sh
# Phase 5 POPULATE: implement runtime/bin/app_entry (minimal executor).
set -euo pipefail

[ -d runtime/bin ] || { echo "ERROR: runtime/bin missing" >&2; exit 1; }

cat > runtime/bin/app_entry <<'EOF'
#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

# Ensure imports work when invoked from host adapters
RUNTIME_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RUNTIME_ROOT))

from core.executor import (
    ExecutionContext,
    validate_command_request,
    capabilities_for_command,
    can_execute,
    RegistryError,
)
from core.capability import CapabilityLattice


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def error(msg: str, code: int = 2):
    payload = {"ok": False, "error": msg}
    print(json.dumps(payload, indent=2))
    raise SystemExit(code)


def main():
    # Accept either:
    # 1) app_entry '<json-string>'
    # 2) app_entry --file request.json
    if len(sys.argv) < 2:
        error("missing request: provide JSON string or --file <path>", 2)

    if sys.argv[1] == "--file":
        if len(sys.argv) < 3:
            error("missing --file <path>", 2)
        req_path = Path(sys.argv[2]).expanduser()
        request = load_json(req_path)
    else:
        try:
            request = json.loads(sys.argv[1])
        except json.JSONDecodeError as e:
            error(f"invalid JSON: {e}", 2)

    if not isinstance(request, dict):
        error("request must be an object", 2)

    command = request.get("command")
    args = request.get("args", {})
    if not isinstance(command, str):
        error("request.command must be a string", 2)
    if not isinstance(args, dict):
        error("request.args must be an object", 2)

    registry = load_json(RUNTIME_ROOT / "schema" / "command_registry.json")
    lattice_doc = load_json(RUNTIME_ROOT / "schema" / "capability_lattice.json")
    lattice = CapabilityLattice(lattice_doc["meet_table"])

    # Current execution context (Phase 5 minimal): read-only runtime, no network.
    ctx = ExecutionContext(host="none", context="none", runtime="read", command="read", financial="none")

    try:
        validate_command_request(registry, command, args)
        req_caps = capabilities_for_command(registry, command)
    except RegistryError as e:
        error(str(e), 3)

    if not can_execute(lattice, ctx, req_caps):
        error("capability check failed (meet is BOTTOM)", 4)

    # Execute supported commands
    if command == "noop":
        print(json.dumps({"ok": True, "command": "noop", "result": None}, indent=2))
        return

    if command == "validate":
        # validate nested command exists + args is object
        inner_cmd = args.get("command")
        inner_args = args.get("args", {})
        if not isinstance(inner_cmd, str):
            error("validate.args.command must be a string", 2)
        if not isinstance(inner_args, dict):
            error("validate.args.args must be an object", 2)
        try:
            validate_command_request(registry, inner_cmd, inner_args)
            print(json.dumps({"ok": True, "command": "validate", "valid": True, "target": inner_cmd}, indent=2))
            return
        except RegistryError as e:
            print(json.dumps({"ok": True, "command": "validate", "valid": False, "error": str(e)}, indent=2))
            return

    # If registry contains commands we haven't implemented yet, we fail explicitly.
    error(f"command implemented? no. '{command}' is registered but not implemented in app_entry", 5)


if __name__ == "__main__":
    main()
EOF

chmod +x runtime/bin/app_entry
echo "✅ Phase 5 POPULATE: runtime/bin/app_entry implemented"
