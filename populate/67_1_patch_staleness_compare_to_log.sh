#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import pathlib, re

p = pathlib.Path("runtime/core/projections.py")
s = p.read_text(encoding="utf-8")

# Add helper to read last execution event time from a jsonl log
if "def _log_last_execution_time_utc(" not in s:
    helper = r'''

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
'''
    # Insert after _mtime_utc if present, else after _write_json_deterministic
    if "def _mtime_utc(" in s:
        s = re.sub(r'(def _mtime_utc\(.*?\n\s*return .*?\n)', r'\1' + helper, s, flags=re.S)
    else:
        s = re.sub(r'(def _write_json_deterministic\(.*?\n\s*os\.replace\(tmp, path\)\n)', r'\1' + helper, s, flags=re.S)

# Now patch the stale logic inside build_system_status
# We previously inserted block that computed stale using mtime < last_evt.
# Replace that block with log-tail comparison.
pattern = re.compile(
    r'last_evt = data\.get\("last_event_time_utc",""\)\n\s*mtime = _mtime_utc\(abs_out\)\n\s*# Stale if output mtime is older than last_event_time_utc \(lex compare works for Zulu ISO\)\n\s*stale = 1 if \(last_evt and mtime < last_evt\) else 0\n\s*if stale:\n\s*overall_ok = 0\n\s*proj_rows\.append\(\{"name": name, "status": "STALE", "output_mtime_utc": mtime, "last_event_time_utc": last_evt, "stale": 1\}\)\n\s*else:\n\s*proj_rows\.append\(\{"name": name, "status": "OK", "output_mtime_utc": mtime, "last_event_time_utc": last_evt, "stale": 0\}\)',
    re.S
)

replacement = (
    'last_evt = data.get("last_event_time_utc","")\n'
    '            mtime = _mtime_utc(abs_out)\n'
    '            # Determine staleness by comparing projection coverage vs log tail\n'
    '            src = spec.get("source_log") or ""\n'
    '            abs_src = os.path.join(ROOT, src) if isinstance(src, str) and src else ""\n'
    '            log_last = _log_last_execution_time_utc(abs_src) if abs_src else ""\n'
    '            stale = 1 if (log_last and last_evt and last_evt < log_last) else 0\n'
    '            if stale:\n'
    '                overall_ok = 0\n'
    '                proj_rows.append({"name": name, "status": "STALE", "output_mtime_utc": mtime, "last_event_time_utc": last_evt, "log_last_event_time_utc": log_last, "stale": 1})\n'
    '            else:\n'
    '                proj_rows.append({"name": name, "status": "OK", "output_mtime_utc": mtime, "last_event_time_utc": last_evt, "log_last_event_time_utc": log_last, "stale": 0})'
)

if pattern.search(s):
    s = pattern.sub(replacement, s)
else:
    raise SystemExit("ERROR: could not find previous staleness block to replace")

p.write_text(s, encoding="utf-8")
print("OK: patched staleness to compare projection vs log tail")
PY
