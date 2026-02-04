#!/usr/bin/env bash
set -euo pipefail

cat > runtime/bin/app_entry <<'EOF'
#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import hashlib
import datetime
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


EXEC_LOG = RUNTIME_ROOT / "state" / "logs" / "executions.jsonl"
EXEC_LOG.parent.mkdir(parents=True, exist_ok=True)


def _utc_now() -> str:
    # timezone-aware UTC, ISO8601 with Z
    return (
        datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def _sha256_text(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def _append_exec(event: dict) -> None:
    # append-only JSONL
    with EXEC_LOG.open("a", encoding="utf-8") as f:
        f.write(json.dumps(event, separators=(",", ":")) + "\n")


def _print(payload: dict) -> None:
    print(json.dumps(payload, indent=2))


def error(msg: str, code: int, req_sha: str = "", command: str | None = None) -> None:
    payload = {"ok": False, "error": msg}
    _print(payload)
    try:
        _append_exec(
            {
                "event_type": "execution",
                "event_time_utc": _utc_now(),
                "request_sha256": req_sha,
                "status": "FAIL",
                "exit_code": code,
                **({"command": command} if command else {}),
                "response": payload,
            }
        )
    except Exception:
        pass
    raise SystemExit(code)


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main() -> None:
    req_sha = ""
    command_name: str | None = None

    # Accept either:
    # 1) app_entry '<json-string>'
    # 2) app_entry --file request.json
    if len(sys.argv) < 2:
        error("missing request: provide JSON string or --file <path>", 2, req_sha)

    # Parse request
    if sys.argv[1] == "--file":
        if len(sys.argv) < 3:
            error("missing --file <path>", 2, req_sha)
        req_path = Path(sys.argv[2]).expanduser()
        try:
            request = load_json(req_path)
        except Exception as e:
            error(f"failed to load request file: {e}", 2, req_sha)
    else:
        try:
            request = json.loads(sys.argv[1])
        except json.JSONDecodeError as e:
            error(f"invalid JSON: {e}", 2, req_sha)

    if not isinstance(request, dict):
        error("request must be an object", 2, req_sha)

    # Compute request hash as early as possible (used for PASS + FAIL)
    try:
        req_sha = _sha256_text(json.dumps(request, sort_keys=True))
    except Exception:
        req_sha = ""

    command_name = request.get("command")
    args = request.get("args", {})

    if not isinstance(command_name, str):
        error("request.command must be a string", 2, req_sha)
    if not isinstance(args, dict):
        error("request.args must be an object", 2, req_sha, command_name)

    # Load contracts
    try:
        registry = load_json(RUNTIME_ROOT / "schema" / "command_registry.json")
        lattice_doc = load_json(RUNTIME_ROOT / "schema" / "capability_lattice.json")
        lattice = CapabilityLattice(lattice_doc["meet_table"])
    except Exception as e:
        error(f"failed to load runtime schemas: {e}", 2, req_sha, command_name)

    # Execution context (Phase 5 minimal): read-only runtime, no network
    ctx = ExecutionContext(host="none", context="none", runtime="read", command="read", financial="none")

    # Validate against registry
    try:
        validate_command_request(registry, command_name, args)
        req_caps = capabilities_for_command(registry, command_name)
    except RegistryError as e:
        error(str(e), 3, req_sha, command_name)

    # Capability check
    if not can_execute(lattice, ctx, req_caps):
        error("capability check failed (meet is BOTTOM)", 4, req_sha, command_name)

    # Execute supported commands
    if command_name == "noop":
        resp = {"ok": True, "command": "noop", "result": None}
        _print(resp)
        _append_exec(
            {
                "event_type": "execution",
                "event_time_utc": _utc_now(),
                "request_sha256": req_sha,
                "status": "PASS",
                "exit_code": 0,
                "command": command_name,
                "response": resp,
            }
        )
        return

    if command_name == "validate":
        inner_cmd = args.get("command")
        inner_args = args.get("args", {})
        if not isinstance(inner_cmd, str):
            error("validate.args.command must be a string", 2, req_sha, command_name)
        if not isinstance(inner_args, dict):
            error("validate.args.args must be an object", 2, req_sha, command_name)

        try:
            validate_command_request(registry, inner_cmd, inner_args)
            resp = {"ok": True, "command": "validate", "valid": True, "target": inner_cmd}
        except RegistryError as e:
            resp = {"ok": True, "command": "validate", "valid": False, "error": str(e)}

        _print(resp)
        _append_exec(
            {
                "event_type": "execution",
                "event_time_utc": _utc_now(),
                "request_sha256": req_sha,
                "status": "PASS",
                "exit_code": 0,
                "command": command_name,
                "response": resp,
            }
        )
        return

    # Registered but not implemented
    error(f"command implemented? no. '{command_name}' is registered but not implemented in app_entry", 5, req_sha, command_name)


if __name__ == "__main__":
    main()
EOF

chmod +x runtime/bin/app_entry
echo "✅ runtime/bin/app_entry rewritten cleanly (logging + timezone-aware UTC + correct req sha)"
