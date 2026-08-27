#!/usr/bin/env bash
set -euo pipefail

TMP="/tmp/prod_test_compare_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TMP"

PROD_DB="_f98256a6d2bdfda2"
TEST_DB="_b9d33ed61d78a9f2"
PROD_ROOT_PW="fd88f0ff7"
TEST_ROOT_PW="tSt7f92k1QzR"

normalize_dump() {
  sed -E \
    -e 's/AUTO_INCREMENT=[0-9]+/AUTO_INCREMENT=X/g' \
    -e '/^-- Dump completed/d' \
    -e '/^-- MariaDB dump/d' \
    -e '/^-- Host:/d'
}

echo "Creating normalized read-only DB dumps"
docker exec frappe-db-1 mariadb-dump -uroot -p"${PROD_ROOT_PW}" --single-transaction --routines --triggers --skip-comments --compact "${PROD_DB}" | normalize_dump > "$TMP/prod.sql"
docker exec frappe-test-db-1 mariadb-dump -uroot -p"${TEST_ROOT_PW}" --single-transaction --routines --triggers --skip-comments --compact "${TEST_DB}" | normalize_dump > "$TMP/test.sql"

PROD_DB_HASH=$(sha256sum "$TMP/prod.sql" | awk '{print $1}')
TEST_DB_HASH=$(sha256sum "$TMP/test.sql" | awk '{print $1}')

echo "DB_HASH_PROD=$PROD_DB_HASH"
echo "DB_HASH_TEST=$TEST_DB_HASH"
if [ "$PROD_DB_HASH" = "$TEST_DB_HASH" ]; then
  echo "DB_MATCH=yes"
else
  echo "DB_MATCH=no"
  diff -u "$TMP/prod.sql" "$TMP/test.sql" | head -200 || true
fi

hash_tree() {
  local container="$1"
  local path="$2"
  docker exec "$container" sh -lc "if [ -d '$path' ]; then cd '$path' && find . -type f -print | sort | while IFS= read -r f; do sha256sum \"\$f\"; done | sha256sum | cut -d' ' -f1; else echo MISSING; fi"
}

echo "File tree hashes"
PROD_PUBLIC=$(hash_tree frappe-backend-1 /home/frappe/frappe-bench/sites/161.97.83.156/public/files)
TEST_PUBLIC=$(hash_tree frappe-test-backend-1 /home/frappe/frappe-bench/sites/test.erpnext.am/public/files)
PROD_PRIVATE=$(hash_tree frappe-backend-1 /home/frappe/frappe-bench/sites/161.97.83.156/private/files)
TEST_PRIVATE=$(hash_tree frappe-test-backend-1 /home/frappe/frappe-bench/sites/test.erpnext.am/private/files)

echo "PUBLIC_HASH_PROD=$PROD_PUBLIC"
echo "PUBLIC_HASH_TEST=$TEST_PUBLIC"
[ "$PROD_PUBLIC" = "$TEST_PUBLIC" ] && echo "PUBLIC_FILES_MATCH=yes" || echo "PUBLIC_FILES_MATCH=no"

echo "PRIVATE_HASH_PROD=$PROD_PRIVATE"
echo "PRIVATE_HASH_TEST=$TEST_PRIVATE"
[ "$PROD_PRIVATE" = "$TEST_PRIVATE" ] && echo "PRIVATE_FILES_MATCH=yes" || echo "PRIVATE_FILES_MATCH=no"

echo "Required environment-specific differences"
echo "prod url/site/container/db credentials differ from test by design"
