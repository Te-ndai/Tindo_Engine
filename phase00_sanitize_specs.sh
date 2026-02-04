#!/usr/bin/env bash
# phase00_sanitize_specs.sh
# Cleans specs/*.md by removing :contentReference[...] noise (metadata leakage)
# and optionally enforces Phase 0 "clean root": only specs/ and logs/ exist.

set -euo pipefail

ENFORCE_CLEAN_ROOT="0"
ALLOW_DIRTY_ROOT="0"

for arg in "${@:-}"; do
  case "$arg" in
    --enforce-clean-root) ENFORCE_CLEAN_ROOT="1" ;;
    --allow-dirty-root)   ALLOW_DIRTY_ROOT="1" ;;
    -h|--help)
      cat <<'EOF'
Usage:
  bash phase00_sanitize_specs.sh [--enforce-clean-root] [--allow-dirty-root]

Flags:
  --enforce-clean-root  Fail if root contains directories other than specs/ and logs/
  --allow-dirty-root    Do not fail on extra dirs (still warns). Overrides enforce.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

if [ ! -d "specs" ]; then
  echo "ERROR: specs/ not found in current directory: $(pwd)" >&2
  exit 1
fi

mkdir -p logs

# Optional: enforce Phase 0 root cleanliness
if [ "$ALLOW_DIRTY_ROOT" = "0" ]; then
  extra_dirs="$(find . -maxdepth 1 -mindepth 1 -type d \
    ! -name "specs" ! -name "logs" -printf "%f\n" | sort || true)"

  if [ -n "$extra_dirs" ]; then
    echo "WARNING: Root contains extra directories (Phase 0 purity violated):"
    echo "$extra_dirs" | sed 's/^/  - /'

    if [ "$ENFORCE_CLEAN_ROOT" = "1" ]; then
      echo "ERROR: --enforce-clean-root set. Aborting." >&2
      exit 3
    fi
  fi
fi

# Backup specs before editing (append-only mindset)
ts="$(date +%Y%m%d_%H%M%S)"
backup_dir="logs/phase00_backup_${ts}"
mkdir -p "$backup_dir"
cp -a specs "$backup_dir/"

# Sanitize each markdown file in specs/
shopt -s nullglob
spec_files=(specs/*.md)

if [ "${#spec_files[@]}" -eq 0 ]; then
  echo "ERROR: No specs/*.md files found to sanitize." >&2
  exit 4
fi

echo "Sanitizing specs files:"
for f in "${spec_files[@]}"; do
  echo "  - $f"

  # Remove tokens like: :contentReference[oaicite:1]{index=1}
  # and any preceding spaces before the token.
  # Safe: does not alter normal text structure beyond removing these markers.
  sed -E -i \
    -e 's/[[:space:]]*:contentReference\[[^]]*\]\{[^}]*\}//g' \
    -e 's/[[:space:]]+$//g' \
    "$f"
done

# Verify no remaining :contentReference markers
remaining="$(grep -RIn -- ':contentReference\[' specs || true)"
if [ -n "$remaining" ]; then
  echo "ERROR: Some :contentReference markers remain after sanitization:" >&2
  echo "$remaining" >&2
  echo "Restoring from backup: $backup_dir/specs" >&2
  rm -rf specs
  cp -a "$backup_dir/specs" ./specs
  exit 5
fi

echo "OK: specs sanitized successfully."
echo "Backup stored at: $backup_dir/specs"

echo ""
echo "Quick proof:"
echo "  find . -maxdepth 2 -type d -print"
echo "  find specs -maxdepth 1 -type f -print"
echo "  grep -RIn -- ':contentReference\\[' specs || echo 'No markers found'"
