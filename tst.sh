cat > test/86_test_bundle_sha_runner.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

./test/86_test_bundle_sha.sh
EOF

chmod +x test/86_test_bundle_sha_runner.sh
./test/86_test_bundle_sha_runner.sh
