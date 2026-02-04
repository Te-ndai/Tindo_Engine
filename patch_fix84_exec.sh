#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

F="test/84_test_restore_replay.sh"
[ -f "$F" ] || { echo "❌ missing $F" >&2; exit 1; }

b="${F}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
cp -f "$F" "$b"
echo "✅ backup: $b"

# Fix broken shebang variants:
# - '#!/usr/bin/envbash'  -> '#!/usr/bin/env bash'
# - '#!/usr/bin/env  bash' -> '#!/usr/bin/env bash' (collapse)
# Also ensure the first line starts with #!
first="$(head -n 1 "$F" | tr -d '\r')"
if [[ "$first" != '#!'* ]]; then
  echo "❌ first line is not a shebang: $first" >&2
  exit 1
fi

# Normalize the first line
sed -i '1s#^#!/usr/bin/envbash$#!/usr/bin/env bash#' "$F"
sed -i '1s#^#!/usr/bin/env[[:space:]]\+bash$#!/usr/bin/env bash#' "$F"

# Ensure there is a space after leading # in the first few comment lines (cosmetic, but helps grep)
# (Only apply to first 5 lines to avoid unintended changes)
tmp="${F}.tmp"
awk 'NR<=5 { gsub(/^#([^ ])/,"# \\1"); } { print }' "$F" > "$tmp"
mv "$tmp" "$F"

chmod +x "$F"
echo "✅ fixed shebang + normalized header"
echo "Now run:"
echo "  head -n 3 $F | cat -A"
echo "  ./test/84_test_restore_replay.sh"
