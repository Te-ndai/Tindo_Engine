#!/usr/bin/env bash
set -euo pipefail

f="test/02_test.sh"
[ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }

# Show current block lines for sanity (optional)
# nl -ba "$f" | tail -n 40

# Replace line 155 and 156 exactly (those are the broken greps in your file)
# We use awk to rewrite by line number.
awk 'NR==155{$0="grep -qF \"\\\"contract\\\": \\\"command_registry\\\"\" runtime/schema/command_registry.json || fail \"command_registry missing contract tag\""}
     NR==156{$0="grep -qF \"\\\"commands\\\"\" runtime/schema/command_registry.json || fail \"command_registry missing commands\""}
     {print}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

chmod +x "$f"
echo "OK: replaced lines 155-156 with fixed-string greps."
