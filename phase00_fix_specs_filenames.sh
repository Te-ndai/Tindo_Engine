#!/usr/bin/env bash
# phase00_fix_specs_filenames.sh
# Fixes common specs filename typos deterministically (script sovereignty).

set -euo pipefail

if [ ! -d "specs" ]; then
  echo "ERROR: specs/ not found in $(pwd)" >&2
  exit 1
fi

# Fix contsraints.md -> constraints.md
if [ -f "specs/contsraints.md" ] && [ ! -f "specs/constraints.md" ]; then
  mv "specs/contsraints.md" "specs/constraints.md"
  echo "Renamed: specs/contsraints.md -> specs/constraints.md"
elif [ -f "specs/contsraints.md" ] && [ -f "specs/constraints.md" ]; then
  echo "ERROR: Both specs/contsraints.md and specs/constraints.md exist. Resolve manually." >&2
  exit 2
else
  echo "OK: No typo filename to fix."
fi

# Verify required Phase 0 contracts exist
for f in specs/system.md specs/constraints.md specs/phases.md; do
  if [ ! -f "$f" ]; then
    echo "ERROR: Missing required contract: $f" >&2
    exit 3
  fi
done

echo "OK: Phase 0 contracts present with correct filenames."
