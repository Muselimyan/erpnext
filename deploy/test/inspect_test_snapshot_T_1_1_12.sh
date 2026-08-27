#!/usr/bin/env bash
set -euo pipefail
DIR="/root/erpnext-version-snapshots/test_T-1.1.12_20260827T084750Z"
echo "--- test containers ---"
docker ps --format '{{.Names}}' | grep '^frappe-test-' | sort
echo "--- manifest ---"
cat "$DIR/manifest.txt"
echo "--- files ---"
ls -lah "$DIR"
echo "--- sha check ---"
cd "$DIR"
sha256sum -c SHA256SUMS.txt
