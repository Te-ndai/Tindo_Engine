#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import pathlib, re

p=pathlib.Path("runtime/core/projections.py")
s=p.read_text(encoding="utf-8")

# Replace old _verify_chain_file with a stronger verifier.
# We'll inject a new function and have build_system_status call it.
if "def _verify_log_integrity(" not in s:
    verifier = r'''

def _verify_log_integrity() -> Tuple[bool, str]:
    """
    Verifies:
    - executions.chain.jsonl cryptographic continuity
    - executions.chain.checkpoint.json matches chain tail and source prefix
    """
    import hashlib

    src = os.path.join(ROOT, "runtime", "state", "logs", "executions.jsonl")
    chain = os.path.join(ROOT, "runtime", "state", "logs", "executions.chain.jsonl")
    cp = os.path.join(ROOT, "runtime", "state", "logs", "executions.chain.checkpoint.json")

    if not os.path.exists(src):
        return (False, "source log missing")
    if not os.path.exists(chain):
        return (False, "chain log missing")
    if not os.path.exists(cp):
        return (False, "checkpoint missing (run logchain_init)")

    try:
        ck = _read_json(cp)
        if not isinstance(ck, dict):
            return (False, "checkpoint not an object")
        lines_expected = int(ck.get("lines", 0))
        tail_expected = str(ck.get("last_line_sha256", ""))
        prefix_expected = str(ck.get("source_prefix_sha256", ""))

        # Read source non-empty lines
        raw = [l for l in open(src, "r", encoding="utf-8").read().splitlines() if l.strip()]
        if lines_expected != len(raw):
            return (False, f"checkpoint lines mismatch: cp={lines_expected} src={len(raw)}")

        def canon(ev: dict) -> bytes:
            ev2 = dict(ev)
            ev2.pop("prev_sha256", None)
            ev2.pop("line_sha256", None)
            return json.dumps(ev2, sort_keys=True, separators=(",", ":")).encode("utf-8")

        # Verify source prefix hash
        pref = hashlib.sha256()
        for i in range(lines_expected):
            ev = json.loads(raw[i])
            pref.update(canon(ev))
        got_prefix = pref.hexdigest()
        if prefix_expected and got_prefix != prefix_expected:
            return (False, "source prefix hash mismatch (rewrite detected)")

        # Verify chain continuity and count, compute tail
        prev = "0"*64
        n = 0
        tail = prev
        with open(chain, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                ev = json.loads(line)
                got_prev = ev.get("prev_sha256")
                got_h = ev.get("line_sha256")
                if got_prev != prev:
                    return (False, f"chain prev mismatch at line {n+1}")
                ev2 = dict(ev)
                ev2.pop("prev_sha256", None)
                ev2.pop("line_sha256", None)
                payload = json.dumps(ev2, sort_keys=True, separators=(",", ":")).encode("utf-8")
                h = hashlib.sha256(prev.encode("utf-8") + payload).hexdigest()
                if got_h != h:
                    return (False, f"chain hash mismatch at line {n+1}")
                prev = h
                tail = h
                n += 1

        if n != lines_expected:
            return (False, f"chain lines mismatch: chain={n} cp={lines_expected}")

        if tail_expected and tail != tail_expected:
            return (False, "checkpoint tail hash mismatch")

        return (True, f"ok lines={n}")
    except Exception as e:
        return (False, f"exception: {type(e).__name__}: {e}")
'''
    # Insert verifier near other helpers, before BUILDERS
    s = re.sub(r'\nBUILDERS\s*=\s*{', verifier + r'\n\nBUILDERS = {', s, count=1)

# Update build_system_status to call _verify_log_integrity instead of _verify_chain_file
s = re.sub(
    r'ok_chain, detail = _verify_chain_file\(chain_path\)',
    'ok_chain, detail = _verify_log_integrity()',
    s
)

# Also remove now-unused chain_path assignment if present
s = s.replace(
    '    chain_path = os.path.join(ROOT, "runtime", "state", "logs", "executions.chain.jsonl")\n    ok_chain, detail = _verify_log_integrity()\n',
    '    ok_chain, detail = _verify_log_integrity()\n'
)

p.write_text(s, encoding="utf-8")
print("OK: patched projections.py to verify checkpoint + chain + source")
PY

echo "OK: phase 76 populate complete"
