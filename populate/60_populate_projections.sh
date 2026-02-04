#!/usr/bin/env bash
set -euo pipefail

# core logic
cat > runtime/core/projections.py <<'EOF'
from __future__ import annotations
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Any, Iterable, List


@dataclass(frozen=True)
class ExecSummary:
    total: int
    by_status: Dict[str, int]
    by_command: Dict[str, int]
    last_event_time_utc: str | None
    last_n: List[Dict[str, Any]]


def _iter_jsonl(path: Path) -> Iterable[Dict[str, Any]]:
    if not path.exists():
        return
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            yield json.loads(line)


def build_execution_summary(exec_log: Path, last_n: int = 10) -> ExecSummary:
    total = 0
    by_status: Dict[str, int] = {}
    by_command: Dict[str, int] = {}
    last_time: str | None = None
    tail: List[Dict[str, Any]] = []

    for ev in _iter_jsonl(exec_log):
        total += 1
        st = str(ev.get("status", "UNKNOWN"))
        by_status[st] = by_status.get(st, 0) + 1

        cmd = ev.get("command")
        if isinstance(cmd, str):
            by_command[cmd] = by_command.get(cmd, 0) + 1
        else:
            by_command["(none)"] = by_command.get("(none)", 0) + 1

        t = ev.get("event_time_utc")
        if isinstance(t, str):
            last_time = t

        tail.append(ev)
        if len(tail) > last_n:
            tail.pop(0)

    return ExecSummary(
        total=total,
        by_status=by_status,
        by_command=by_command,
        last_event_time_utc=last_time,
        last_n=tail,
    )


def write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, sort_keys=True)
        f.write("\n")
EOF

# CLI
cat > runtime/bin/rebuild_projections <<'EOF'
#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

RUNTIME_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RUNTIME_ROOT))

from core.projections import build_execution_summary, write_json


def main() -> int:
    exec_log = RUNTIME_ROOT / "state" / "logs" / "executions.jsonl"
    out = RUNTIME_ROOT / "state" / "projections" / "executions_summary.json"

    summary = build_execution_summary(exec_log, last_n=10)

    payload = {
        "projection": "executions_summary",
        "source": str(exec_log),
        "total": summary.total,
        "by_status": summary.by_status,
        "by_command": summary.by_command,
        "last_event_time_utc": summary.last_event_time_utc,
        "last_n": summary.last_n,
    }

    write_json(out, payload)
    print(f"Wrote: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
EOF

chmod +x runtime/bin/rebuild_projections
echo "✅ projections populated: runtime/core/projections.py + runtime/bin/rebuild_projections"
