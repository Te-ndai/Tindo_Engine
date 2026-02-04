#!/usr/bin/env bash
set -euo pipefail

cat > test/71_test_write_surface.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

# Snapshot helper: generate stable listing of file path + size + mtime + sha256
snap() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo "MISSING_DIR $dir"
    return 0
  fi
  (cd "$dir" && \
    find . -type f -print0 | sort -z | \
    xargs -0 -I{} sh -c '
      f="{}"
      # size + mtime epoch
      sz=$(stat -c "%s" "$f")
      mt=$(stat -c "%Y" "$f")
      h=$(sha256sum "$f" | awk "{print \$1}")
      printf "%s\t%s\t%s\t%s\n" "$f" "$sz" "$mt" "$h"
    ')
}

mkdir -p test/tmp

# Protected surfaces (must not change)
snap runtime/state/logs   > test/tmp/snap_logs_before.txt
snap runtime/schema       > test/tmp/snap_schema_before.txt
snap runtime/core         > test/tmp/snap_core_before.txt

# Allowed surfaces (may change)
snap runtime/state/projections > test/tmp/snap_proj_before.txt || true

# Run ops commands (should not mutate protected surfaces)
./runtime/bin/ops status   >/dev/null || true
./runtime/bin/ops rebuild all >/dev/null || true
./runtime/bin/ops freshen  >/dev/null || true

snap runtime/state/logs   > test/tmp/snap_logs_after.txt
snap runtime/schema       > test/tmp/snap_schema_after.txt
snap runtime/core         > test/tmp/snap_core_after.txt
snap runtime/state/projections > test/tmp/snap_proj_after.txt || true

# Compare protected surfaces
if ! diff -u test/tmp/snap_logs_before.txt test/tmp/snap_logs_after.txt >/dev/null; then
  echo "FAIL: runtime/state/logs changed (should be append-only by explicit test only)"
  diff -u test/tmp/snap_logs_before.txt test/tmp/snap_logs_after.txt | head -n 80
  exit 1
fi

if ! diff -u test/tmp/snap_schema_before.txt test/tmp/snap_schema_after.txt >/dev/null; then
  echo "FAIL: runtime/schema changed (should be immutable at runtime)"
  diff -u test/tmp/snap_schema_before.txt test/tmp/snap_schema_after.txt | head -n 80
  exit 1
fi

if ! diff -u test/tmp/snap_core_before.txt test/tmp/snap_core_after.txt >/dev/null; then
  echo "FAIL: runtime/core changed (runtime code mutated)"
  diff -u test/tmp/snap_core_before.txt test/tmp/snap_core_after.txt | head -n 80
  exit 1
fi

echo "PASS: protected surfaces unchanged"

# Projections can change; just assert they exist
test -d runtime/state/projections || { echo "FAIL: projections dir missing"; exit 1; }

echo "✅ Phase 71 TEST PASS"
SH

chmod +x test/71_test_write_surface.sh

echo "OK: phase 71 populate complete"
