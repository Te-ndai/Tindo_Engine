#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

F="test/84_test_restore_replay.sh"
[ -f "$F" ] || { echo "❌ missing $F" >&2; exit 1; }

B="${F}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp -f "$F" "$B"
echo "✅ backup: $B"

python3 - <<'PY' "test/84_test_restore_replay.sh"
from pathlib import Path
p = Path(__import__("sys").argv[1])
raw = p.read_bytes()

# Normalize line endings to \n (safe)
txt = raw.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")
lines = txt.splitlines(True)
if not lines:
    raise SystemExit("empty file")

# Force correct shebang no matter what it was
lines[0] = "#!/usr/bin/env bash\n"

p.write_text("".join(lines), encoding="utf-8")
PY

chmod +x "$F"
echo "✅ fixed shebang"
echo "Check:"
head -n 2 "$F" | cat -A
