#!/usr/bin/env bash
set -euo pipefail

cat > runtime/core/projections.py <<'PY'
from __future__ import annotations

import json
import os
from typing import Any, Dict, List, Optional, Tuple

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

REGISTRY_PATH = os.path.join(ROOT, "runtime", "schema", "projection_registry.json")
ENVELOPE_PATH = os.path.join(ROOT, "runtime", "schema", "projection_envelope_contract.json")
PAYLOADS_PATH = os.path.join(ROOT, "runtime", "schema", "projection_payload_contracts.json")


class ProjectionError(Exception):
    pass


def _read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _write_json_deterministic(path: str, data: Any) -> None:
    tmp = path + ".tmp"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def _mtime_utc(path: str) -> str:
    from datetime import datetime, timezone
    ts = os.path.getmtime(path)
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _log_last_execution_time_utc(path: str) -> str:
    # Returns last event_time_utc among execution events, or "" if none/missing.
    if not path or not os.path.exists(path):
        return ""
    last = ""
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except Exception:
                continue
            if isinstance(ev, dict) and ev.get("event_type") == "execution":
                t = ev.get("event_time_utc") or ""
                if isinstance(t, str) and t:
                    last = t
    return last


def load_registry() -> Dict[str, Any]:
    reg = _read_json(REGISTRY_PATH)
    if not isinstance(reg, dict):
        raise ProjectionError("registry must be a JSON object")
    if reg.get("schema_version") != 1:
        raise ProjectionError("unsupported registry schema_version")
    if "projections" not in reg or not isinstance(reg["projections"], list):
        raise ProjectionError("registry.projections must be a list")
    return reg


def load_envelope_contract() -> Dict[str, Any]:
    c = _read_json(ENVELOPE_PATH)
    if not isinstance(c, dict):
        raise ProjectionError("envelope contract must be a JSON object")
    if c.get("schema_version") != 1:
        raise ProjectionError("unsupported envelope schema_version")
    return c


def load_payload_contracts() -> Dict[str, Any]:
    p = _read_json(PAYLOADS_PATH)
    if not isinstance(p, dict):
        raise ProjectionError("payload contracts must be a JSON object")
    if p.get("schema_version") != 1:
        raise ProjectionError("unsupported payload contracts schema_version")
    contracts = p.get("contracts")
    if not isinstance(contracts, dict):
        raise ProjectionError("payload contracts missing 'contracts' object")
    return p


def _type_ok(value: Any, t: str) -> bool:
    if t == "string":
        return isinstance(value, str)
    if t == "int":
        return isinstance(value, int)
    if t == "list":
        return isinstance(value, list)
    if t == "object":
        return isinstance(value, dict)
    return False


def _validate_required_and_types(data: Dict[str, Any], req: List[str], types: Dict[str, str]) -> None:
    for k in req:
        if k not in data:
            raise ProjectionError(f"projection missing required field: {k}")
    for k, t in types.items():
        if k in data and not _type_ok(data[k], t):
            raise ProjectionError(f"projection field has wrong type: {k} expected {t}")


def _validate_system_status_rows(data: Dict[str, Any]) -> None:
    rows = data.get("projections")
    if not isinstance(rows, list):
        raise ProjectionError("system_status.projections must be a list")

    for i, row in enumerate(rows):
        if not isinstance(row, dict):
            raise ProjectionError(f"system_status.projections[{i}] must be an object")

        if "name" not in row or not isinstance(row["name"], str):
            raise ProjectionError(f"system_status.projections[{i}].name missing/invalid")
        if "status" not in row or not isinstance(row["status"], str):
            raise ProjectionError(f"system_status.projections[{i}].status missing/invalid")

        status = row["status"]

        # For OK/STALE rows, we require the freshness fields
        if status in ("OK", "STALE"):
            for k in ("output_mtime_utc", "last_event_time_utc", "log_last_event_time_utc", "stale"):
                if k not in row:
                    raise ProjectionError(f"system_status.projections[{i}] missing {k}")
            if not isinstance(row["output_mtime_utc"], str):
                raise ProjectionError(f"system_status.projections[{i}].output_mtime_utc invalid")
            if not isinstance(row["last_event_time_utc"], str):
                raise ProjectionError(f"system_status.projections[{i}].last_event_time_utc invalid")
            if not isinstance(row["log_last_event_time_utc"], str):
                raise ProjectionError(f"system_status.projections[{i}].log_last_event_time_utc invalid")
            if row["stale"] not in (0, 1):
                raise ProjectionError(f"system_status.projections[{i}].stale must be 0/1")


def validate_projection_output(data: Dict[str, Any], envelope: Dict[str, Any], payloads: Dict[str, Any]) -> None:
    if not isinstance(data, dict):
        raise ProjectionError("projection output must be an object")

    # Envelope validation
    _validate_required_and_types(
        data,
        envelope.get("required_fields", []),
        envelope.get("field_types", {}),
    )

    name = data.get("projection")
    contracts = payloads.get("contracts", {})
    pc = contracts.get(name)
    if pc is None:
        raise ProjectionError(f"no payload contract for projection: {name}")

    # Payload validation
    _validate_required_and_types(
        data,
        pc.get("required_fields", []),
        pc.get("field_types", {}),
    )

    # Extra row validation for system_status
    if name == "system_status":
        _validate_system_status_rows(data)

    # Optional last_n item validation (only if contract defines it)
    last_n_item_required = pc.get("last_n_item_required")
    if last_n_item_required is not None:
        last_n = data.get("last_n")
        if not isinstance(last_n, list):
            raise ProjectionError("last_n must be a list")
        for i, item in enumerate(last_n):
            if not isinstance(item, dict):
                raise ProjectionError(f"last_n[{i}] must be an object")
            for k in last_n_item_required:
                if k not in item:
                    raise ProjectionError(f"last_n[{i}] missing field: {k}")


# -----------------------
# Projection builders
# -----------------------

def _iter_jsonl(path: str) -> List[Dict[str, Any]]:
    events: List[Dict[str, Any]] = []
    if not os.path.exists(path):
        return events
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            events.append(json.loads(line))
    return events


def build_executions_summary(source_log: str, last_n: int = 25) -> Dict[str, Any]:
    events = _iter_jsonl(source_log)

    total = 0
    by_command: Dict[str, int] = {}
    by_status: Dict[str, int] = {}
    last_events: List[Dict[str, Any]] = []

    for ev in events:
        if not isinstance(ev, dict):
            continue
        if ev.get("event_type") != "execution":
            continue
        total += 1
        cmd = ev.get("command", "UNKNOWN")
        status = ev.get("status", "UNKNOWN")
        by_command[cmd] = by_command.get(cmd, 0) + 1
        by_status[status] = by_status.get(status, 0) + 1
        last_events.append(ev)

    tail = last_events[-last_n:] if last_n > 0 else []
    last_time = tail[-1].get("event_time_utc") if tail else ""

    return {
        "projection": "executions_summary",
        "source": source_log,
        "total": total,
        "last_event_time_utc": last_time,
        "by_command": by_command,
        "by_status": by_status,
        "last_n": tail,
    }


def build_commands_summary(source_log: str) -> Dict[str, Any]:
    events = _iter_jsonl(source_log)

    total = 0
    by_command: Dict[str, int] = {}
    by_status: Dict[str, int] = {}
    last_time = ""

    for ev in events:
        if not isinstance(ev, dict):
            continue
        if ev.get("event_type") != "execution":
            continue

        total += 1
        cmd = ev.get("command", "UNKNOWN")
        status = ev.get("status", "UNKNOWN")
        by_command[cmd] = by_command.get(cmd, 0) + 1
        by_status[status] = by_status.get(status, 0) + 1
        last_time = ev.get("event_time_utc") or ""

    return {
        "projection": "commands_summary",
        "source": source_log,
        "total": total,
        "last_event_time_utc": last_time,
        "by_command": by_command,
        "by_status": by_status,
    }


def build_system_status(_: str) -> Dict[str, Any]:
    # Live status (allowed to use current time)
    from datetime import datetime, timezone

    checked_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    reg = load_registry()
    envelope = load_envelope_contract()
    payloads = load_payload_contracts()

    proj_rows: List[Dict[str, Any]] = []
    errors: List[str] = []
    overall_ok = 1

    for spec in reg["projections"]:
        if not isinstance(spec, dict):
            overall_ok = 0
            errors.append("registry contains non-object projection spec")
            continue

        name = spec.get("name", "UNKNOWN")
        enabled = spec.get("enabled", True)
        out = spec.get("output")
        src = spec.get("source_log") or ""

        if not enabled:
            proj_rows.append({"name": name, "status": "SKIPPED"})
            continue

        # system_status must not depend on its own prior output file
        if name == "system_status":
            proj_rows.append({
                "name": name,
                "status": "OK",
                "output_mtime_utc": "",
                "last_event_time_utc": "",
                "log_last_event_time_utc": "",
                "stale": 0
            })
            continue

        if not isinstance(out, str) or not out:
            proj_rows.append({"name": name, "status": "FAIL"})
            overall_ok = 0
            errors.append(f"{name}: missing output path in registry")
            continue

        abs_out = os.path.join(ROOT, out)
        if not os.path.exists(abs_out):
            proj_rows.append({"name": name, "status": "FAIL"})
            overall_ok = 0
            errors.append(f"{name}: output missing")
            continue

        try:
            data = _read_json(abs_out)
            if not isinstance(data, dict):
                raise ProjectionError("output not object")
            validate_projection_output(data, envelope, payloads)

            last_evt = data.get("last_event_time_utc", "") or ""
            mtime = _mtime_utc(abs_out)

            abs_src = os.path.join(ROOT, src) if isinstance(src, str) and src else ""
            log_last = _log_last_execution_time_utc(abs_src) if abs_src else ""

            stale = 1 if (log_last and last_evt and last_evt < log_last) else 0
            if stale:
                overall_ok = 0
                proj_rows.append({
                    "name": name, "status": "STALE",
                    "output_mtime_utc": mtime,
                    "last_event_time_utc": last_evt,
                    "log_last_event_time_utc": log_last,
                    "stale": 1
                })
            else:
                proj_rows.append({
                    "name": name, "status": "OK",
                    "output_mtime_utc": mtime,
                    "last_event_time_utc": last_evt,
                    "log_last_event_time_utc": log_last,
                    "stale": 0
                })
        except Exception as e:
            proj_rows.append({"name": name, "status": "FAIL"})
            overall_ok = 0
            errors.append(f"{name}: {type(e).__name__}: {e}")

    return {
        "projection": "system_status",
        "source": "",
        "total": 0,
        "last_event_time_utc": "",
        "ok": overall_ok,
        "checked_at_utc": checked_at,
        "projections": proj_rows,
        "errors": errors
    }


BUILDERS = {
    "system_status": build_system_status,
    "executions_summary": build_executions_summary,
    "commands_summary": build_commands_summary,
}


def rebuild_projection(spec: Dict[str, Any], envelope: Dict[str, Any], payloads: Dict[str, Any]) -> Tuple[str, str]:
    name = spec.get("name")
    enabled = spec.get("enabled", True)
    if not enabled:
        return (name or "UNKNOWN", "SKIPPED")

    if name not in BUILDERS:
        raise ProjectionError(f"no builder for projection: {name}")

    source_log = spec.get("source_log")
    output_path = spec.get("output")
    if not isinstance(source_log, str) or not isinstance(output_path, str):
        raise ProjectionError(f"projection spec invalid for {name}")

    abs_source = os.path.join(ROOT, source_log) if source_log else ""
    abs_output = os.path.join(ROOT, output_path)

    data = BUILDERS[name](abs_source)

    if data.get("projection") != name:
        raise ProjectionError(f"builder output projection mismatch: expected {name}")

    validate_projection_output(data, envelope, payloads)
    _write_json_deterministic(abs_output, data)
    return (name, "OK")


def rebuild_one(name: str) -> Dict[str, Any]:
    reg = load_registry()
    envelope = load_envelope_contract()
    payloads = load_payload_contracts()

    found = None
    for spec in reg["projections"]:
        if isinstance(spec, dict) and spec.get("name") == name:
            found = spec
            break
    if found is None:
        raise ProjectionError(f"unknown projection: {name}")

    n, status = rebuild_projection(found, envelope, payloads)
    return {"ok": True, "name": n, "status": status}


def rebuild_all() -> Dict[str, Any]:
    reg = load_registry()
    envelope = load_envelope_contract()
    payloads = load_payload_contracts()

    results: List[Dict[str, str]] = []
    for spec in reg["projections"]:
        if not isinstance(spec, dict):
            raise ProjectionError("registry projections must be objects")
        n, status = rebuild_projection(spec, envelope, payloads)
        results.append({"name": n, "status": status})

    return {"ok": True, "results": results}


def main(argv: Optional[List[str]] = None) -> int:
    import sys
    args = sys.argv[1:] if argv is None else argv

    if not args:
        print("usage: projections.py rebuild_all | rebuild_one <name>")
        return 2

    cmd = args[0]
    try:
        if cmd == "rebuild_all":
            out = rebuild_all()
            print(json.dumps(out, indent=2, sort_keys=True))
            return 0
        if cmd == "rebuild_one":
            if len(args) < 2:
                print("usage: projections.py rebuild_one <name>")
                return 2
            out = rebuild_one(args[1])
            print(json.dumps(out, indent=2, sort_keys=True))
            return 0

        print(f"unknown command: {cmd}")
        return 2
    except ProjectionError as e:
        print(f"ERROR: {e}")
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
PY

echo "OK: overwrote runtime/core/projections.py with canonical version"
