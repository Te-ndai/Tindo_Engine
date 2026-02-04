#!/usr/bin/env bash
set -euo pipefail

[ -x runtime/bin/app_entry ] || { echo "ERROR: app_entry missing/not executable" >&2; exit 1; }

python3 - <<'PY'
from pathlib import Path
p = Path("runtime/bin/app_entry")
src = p.read_text(encoding="utf-8")

# Avoid double patching
if "executions.jsonl" in src:
    print("OK: app_entry already has execution logging.")
    raise SystemExit(0)

needle = "def error(msg: str, code: int = 2):"
insert = '''
import hashlib
import datetime

EXEC_LOG = RUNTIME_ROOT / "state" / "logs" / "executions.jsonl"
EXEC_LOG.parent.mkdir(parents=True, exist_ok=True)

def _utc_now() -> str:
    return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"

def _sha256_text(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()

def _append_exec(event: dict) -> None:
    # append-only JSONL
    with EXEC_LOG.open("a", encoding="utf-8") as f:
        f.write(json.dumps(event, separators=(",", ":")) + "\\n")
'''

# Insert right before error()
idx = src.find(needle)
if idx == -1:
    raise SystemExit("ERROR: could not find insertion point in app_entry")

src2 = src[:idx] + insert + "\n" + src[idx:]

# Patch error() to log failures
src2 = src2.replace(
    'def error(msg: str, code: int = 2):\n    payload = {"ok": False, "error": msg}\n    print(json.dumps(payload, indent=2))\n    raise SystemExit(code)\n',
    'def error(msg: str, code: int = 2):\n'
    '    payload = {"ok": False, "error": msg}\n'
    '    print(json.dumps(payload, indent=2))\n'
    '    try:\n'
    '        _append_exec({\n'
    '            "event_type": "execution",\n'
    '            "event_time_utc": _utc_now(),\n'
    '            "request_sha256": _sha256_text(json.dumps(payload, sort_keys=True)),\n'
    '            "status": "FAIL",\n'
    '            "exit_code": code,\n'
    '            "response": payload\n'
    '        })\n'
    '    except Exception:\n'
    '        pass\n'
    '    raise SystemExit(code)\n'
)

# Patch the success paths by adding a single append before return in noop and validate blocks.
# We do minimal injection: after printing success JSON, append an event.
def inject_after_print(block_marker: str) -> str:
    nonlocal_src = src2
    pos = nonlocal_src.find(block_marker)
    if pos == -1:
        raise SystemExit(f"ERROR: cannot find marker: {block_marker}")
    return nonlocal_src

# Add logging right before each `return` in noop and validate sections:
src2 = src2.replace(
    'print(json.dumps({"ok": True, "command": "noop", "result": None}, indent=2))\n        return\n',
    'resp = {"ok": True, "command": "noop", "result": None}\n'
    '        print(json.dumps(resp, indent=2))\n'
    '        _append_exec({\n'
    '            "event_type":"execution",\n'
    '            "event_time_utc": _utc_now(),\n'
    '            "request_sha256": _sha256_text(json.dumps(request, sort_keys=True)),\n'
    '            "status":"PASS",\n'
    '            "exit_code": 0,\n'
    '            "command": command,\n'
    '            "response": resp\n'
    '        })\n'
    '        return\n'
)

src2 = src2.replace(
    'print(json.dumps({"ok": True, "command": "validate", "valid": True, "target": inner_cmd}, indent=2))\n            return\n',
    'resp = {"ok": True, "command": "validate", "valid": True, "target": inner_cmd}\n'
    '            print(json.dumps(resp, indent=2))\n'
    '            _append_exec({\n'
    '                "event_type":"execution",\n'
    '                "event_time_utc": _utc_now(),\n'
    '                "request_sha256": _sha256_text(json.dumps(request, sort_keys=True)),\n'
    '                "status":"PASS",\n'
    '                "exit_code": 0,\n'
    '                "command": command,\n'
    '                "response": resp\n'
    '            })\n'
    '            return\n'
)

src2 = src2.replace(
    'print(json.dumps({"ok": True, "command": "validate", "valid": False, "error": str(e)}, indent=2))\n            return\n',
    'resp = {"ok": True, "command": "validate", "valid": False, "error": str(e)}\n'
    '            print(json.dumps(resp, indent=2))\n'
    '            _append_exec({\n'
    '                "event_type":"execution",\n'
    '                "event_time_utc": _utc_now(),\n'
    '                "request_sha256": _sha256_text(json.dumps(request, sort_keys=True)),\n'
    '                "status":"PASS",\n'
    '                "exit_code": 0,\n'
    '                "command": command,\n'
    '                "response": resp\n'
    '            })\n'
    '            return\n'
)

p.write_text(src2, encoding="utf-8")
print("✅ app_entry patched with append-only execution logging")
PY
