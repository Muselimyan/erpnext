#!/usr/bin/env bash
set -euo pipefail

TEST_BACKEND="frappe-test-backend-1"
TEST_DB_CONTAINER="frappe-test-db-1"
PROD_BACKEND="frappe-backend-1"
PROD_SITE="161.97.83.156"
TEST_SITE="test.erpnext.am"
TEST_DB="_b9d33ed61d78a9f2"
TEST_DB_ROOT_PASSWORD="tSt7f92k1QzR"
PROD_DB_ROOT_PASSWORD="fd88f0ff7"
PROD_HOST_NAME="https://erpnext.am"

TS="$(date +%Y%m%d_%H%M%S)"
CLONE_DIR="/tmp/test_to_prod_clone_${TS}"
PROD_CONTAINER_DIR="/home/frappe/frappe-bench/sites/${PROD_SITE}/private/test_to_prod_clone_${TS}"

mkdir -p "${CLONE_DIR}"
echo "${CLONE_DIR}" > /tmp/test_to_prod_clone_latest

echo "Creating read-only export from test into ${CLONE_DIR}"
docker exec "${TEST_DB_CONTAINER}" mariadb-dump -uroot -p"${TEST_DB_ROOT_PASSWORD}" --single-transaction --routines --triggers "${TEST_DB}" | gzip > "${CLONE_DIR}/test-database.sql.gz"
docker exec "${TEST_BACKEND}" tar -C "/home/frappe/frappe-bench/sites/${TEST_SITE}/public" -cf - files > "${CLONE_DIR}/test-files.tar"
docker exec "${TEST_BACKEND}" tar -C "/home/frappe/frappe-bench/sites/${TEST_SITE}/private" -cf - files > "${CLONE_DIR}/test-private-files.tar"
ls -lh "${CLONE_DIR}"

echo "Copying export into prod backend container"
docker exec "${PROD_BACKEND}" mkdir -p "${PROD_CONTAINER_DIR}"
docker cp "${CLONE_DIR}/test-database.sql.gz" "${PROD_BACKEND}:${PROD_CONTAINER_DIR}/test-database.sql.gz"
docker cp "${CLONE_DIR}/test-files.tar" "${PROD_BACKEND}:${PROD_CONTAINER_DIR}/test-files.tar"
docker cp "${CLONE_DIR}/test-private-files.tar" "${PROD_BACKEND}:${PROD_CONTAINER_DIR}/test-private-files.tar"

echo "Restoring test export into prod site ${PROD_SITE}"
docker exec "${PROD_BACKEND}" bench --site "${PROD_SITE}" restore "${PROD_CONTAINER_DIR}/test-database.sql.gz" --mariadb-root-password "${PROD_DB_ROOT_PASSWORD}" --with-public-files "${PROD_CONTAINER_DIR}/test-files.tar" --with-private-files "${PROD_CONTAINER_DIR}/test-private-files.tar"

echo "Restoring prod-specific config"
docker exec "${PROD_BACKEND}" bench --site "${PROD_SITE}" set-config -g host_name "${PROD_HOST_NAME}"
docker exec "${PROD_BACKEND}" bench --site "${PROD_SITE}" set-config -g server_script_enabled 1
docker exec "${PROD_BACKEND}" bench --site "${PROD_SITE}" set-config -g developer_mode 1
docker exec "${PROD_BACKEND}" bench --site "${PROD_SITE}" clear-cache

echo "Final status"
docker exec "${PROD_BACKEND}" bench --site "${PROD_SITE}" execute frappe.client.get_count --kwargs '{"doctype":"Task"}'
docker exec "${PROD_BACKEND}" bench --site "${PROD_SITE}" execute frappe.client.get_count --kwargs '{"doctype":"Client Script"}'
docker exec "${PROD_BACKEND}" bench --site "${PROD_SITE}" execute frappe.client.get_count --kwargs '{"doctype":"Server Script"}'

echo "Completed full site clone: ${TEST_SITE} -> ${PROD_SITE}"
echo "Host export remains at: ${CLONE_DIR}"
echo "Prod container import copy remains at: ${PROD_CONTAINER_DIR}"
