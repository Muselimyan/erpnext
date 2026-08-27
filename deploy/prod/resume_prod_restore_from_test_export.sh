#!/usr/bin/env bash
set -euo pipefail

PROD_BACKEND="frappe-backend-1"
PROD_SITE="161.97.83.156"
PROD_DB_ROOT_PASSWORD="fd88f0ff7"
PROD_HOST_NAME="https://erpnext.am"
CLONE_DIR="$(cat /tmp/test_to_prod_clone_latest)"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="/tmp/resume_prod_restore_from_test_${TS}.log"
PROD_CONTAINER_DIR="/home/frappe/frappe-bench/sites/${PROD_SITE}/private/test_to_prod_clone_resume_${TS}"

cat > /tmp/resume_prod_restore_inner_${TS}.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec > >(tee -a "${LOG}") 2>&1

echo "Started restore at \$(date)"
echo "Using clone dir: ${CLONE_DIR}"
ls -lh "${CLONE_DIR}"

docker exec "${PROD_BACKEND}" mkdir -p "${PROD_CONTAINER_DIR}"
docker cp "${CLONE_DIR}/test-database.sql.gz" "${PROD_BACKEND}:${PROD_CONTAINER_DIR}/test-database.sql.gz"
docker cp "${CLONE_DIR}/test-files.tar" "${PROD_BACKEND}:${PROD_CONTAINER_DIR}/test-files.tar"
docker cp "${CLONE_DIR}/test-private-files.tar" "${PROD_BACKEND}:${PROD_CONTAINER_DIR}/test-private-files.tar"

echo "Running bench restore into prod site ${PROD_SITE}"
docker exec "${PROD_BACKEND}" bench --site "${PROD_SITE}" restore "${PROD_CONTAINER_DIR}/test-database.sql.gz" --mariadb-root-password "${PROD_DB_ROOT_PASSWORD}" --with-public-files "${PROD_CONTAINER_DIR}/test-files.tar" --with-private-files "${PROD_CONTAINER_DIR}/test-private-files.tar" --force

echo "Restoring prod-specific config"
docker exec "${PROD_BACKEND}" bench --site "${PROD_SITE}" set-config -g host_name "${PROD_HOST_NAME}"
docker exec "${PROD_BACKEND}" bench --site "${PROD_SITE}" set-config -g server_script_enabled 1
docker exec "${PROD_BACKEND}" bench --site "${PROD_SITE}" set-config -g developer_mode 1
docker exec "${PROD_BACKEND}" bench --site "${PROD_SITE}" clear-cache

echo "Completed restore at \$(date)"
EOF

chmod +x /tmp/resume_prod_restore_inner_${TS}.sh
nohup /tmp/resume_prod_restore_inner_${TS}.sh >/tmp/resume_prod_restore_nohup_${TS}.out 2>&1 &
echo "$!" > /tmp/resume_prod_restore_latest.pid
echo "${LOG}" > /tmp/resume_prod_restore_latest.log
echo "Started detached restore PID $(cat /tmp/resume_prod_restore_latest.pid)"
echo "Log: ${LOG}"
