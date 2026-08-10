#!/usr/bin/env bash
set -euo pipefail
TMP="/tmp/approved_prod_to_test_customizations_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TMP"

CLIENT_WHERE="name in ('Task-Account Details UI Cleanup','Task-Other UI Cleanup')"
SERVER_WHERE="name in ('Task-after-save-other-processing','Task-Other Entry Default Subject')"

docker exec frappe-db-1 mariadb-dump -uroot -pfd88f0ff7 --single-transaction --no-create-info --skip-triggers --replace _f98256a6d2bdfda2 "tabClient Script" --where="$CLIENT_WHERE" > "$TMP/client_scripts.sql"
docker exec frappe-db-1 mariadb-dump -uroot -pfd88f0ff7 --single-transaction --no-create-info --skip-triggers --replace _f98256a6d2bdfda2 "tabServer Script" --where="$SERVER_WHERE" > "$TMP/server_scripts.sql"

docker exec -i frappe-test-db-1 mariadb -uroot -ptSt7f92k1QzR _b9d33ed61d78a9f2 < "$TMP/client_scripts.sql"
docker exec -i frappe-test-db-1 mariadb -uroot -ptSt7f92k1QzR _b9d33ed61d78a9f2 < "$TMP/server_scripts.sql"

docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache

echo "imported_sql_dir=$TMP"
