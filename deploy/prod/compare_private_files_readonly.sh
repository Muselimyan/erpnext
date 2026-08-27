#!/usr/bin/env bash
set -euo pipefail
TMP="/tmp/private_file_compare_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TMP"

docker exec frappe-backend-1 sh -lc "cd /home/frappe/frappe-bench/sites/161.97.83.156/private/files && find . -type f -print | sort | while IFS= read -r f; do sha256sum \"\$f\"; done" > "$TMP/prod_private.txt" || true
docker exec frappe-test-backend-1 sh -lc "cd /home/frappe/frappe-bench/sites/test.erpnext.am/private/files && find . -type f -print | sort | while IFS= read -r f; do sha256sum \"\$f\"; done" > "$TMP/test_private.txt" || true

echo "prod_private_count=$(wc -l < "$TMP/prod_private.txt")"
echo "test_private_count=$(wc -l < "$TMP/test_private.txt")"
echo "diff first 200 lines"
diff -u "$TMP/prod_private.txt" "$TMP/test_private.txt" | head -200 || true
