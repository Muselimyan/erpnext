#!/usr/bin/env bash
set -euo pipefail

PROD_PATH="/home/frappe/frappe-bench/sites/161.97.83.156/private/files"
TEST_PATH="/home/frappe/frappe-bench/sites/test.erpnext.am/private/files"
TMP="/tmp/private_file_sync_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TMP"

docker exec frappe-backend-1 sh -lc "cd '$PROD_PATH' && find . -type f -print | sort" > "$TMP/prod_files.txt"
docker exec frappe-test-backend-1 sh -lc "cd '$TEST_PATH' && find . -type f -print | sort" > "$TMP/test_files.txt"

comm -23 "$TMP/prod_files.txt" "$TMP/test_files.txt" > "$TMP/prod_extra.txt"
comm -13 "$TMP/prod_files.txt" "$TMP/test_files.txt" > "$TMP/prod_missing.txt"

echo "Extra prod private files to remove: $(wc -l < "$TMP/prod_extra.txt")"
cat "$TMP/prod_extra.txt"

echo "Missing prod private files to copy from test: $(wc -l < "$TMP/prod_missing.txt")"
cat "$TMP/prod_missing.txt"

if [ -s "$TMP/prod_extra.txt" ]; then
  docker cp "$TMP/prod_extra.txt" frappe-backend-1:/tmp/prod_extra_private_files.txt
  docker exec frappe-backend-1 sh -lc "cd '$PROD_PATH' && while IFS= read -r f; do rm -f -- \"\$f\"; done < /tmp/prod_extra_private_files.txt"
fi

if [ -s "$TMP/prod_missing.txt" ]; then
  while IFS= read -r f; do
    rel="${f#./}"
    mkdir -p "$TMP/copy/$(dirname "$rel")"
    docker cp "frappe-test-backend-1:${TEST_PATH}/${rel}" "$TMP/copy/${rel}"
    docker cp "$TMP/copy/${rel}" "frappe-backend-1:${PROD_PATH}/${rel}"
  done < "$TMP/prod_missing.txt"
fi

echo "After sync counts"
docker exec frappe-backend-1 sh -lc "cd '$PROD_PATH' && find . -type f -print | sort | wc -l"
docker exec frappe-test-backend-1 sh -lc "cd '$TEST_PATH' && find . -type f -print | sort | wc -l"
