#!/usr/bin/env bash
set -euo pipefail
DIR="/root/erpnext-version-snapshots/test_T-1.1.12_20260827T084750Z"
SITE="test.erpnext.am"
DB="_b9d33ed61d78a9f2"
DB_CONTAINER="frappe-test-db-1"
BACKEND_CONTAINER="frappe-test-backend-1"
DB_ROOT_PASSWORD="tSt7f92k1QzR"
SITES_ROOT="/var/lib/docker/volumes/frappe-test_sites/_data"

if ! grep -q '^environment=test$' "$DIR/manifest.txt"; then
  echo "Refusing restore: manifest is not environment=test" >&2
  exit 1
fi
if ! grep -q '^backend_container=frappe-test-backend-1$' "$DIR/manifest.txt"; then
  echo "Refusing restore: backend container mismatch" >&2
  exit 1
fi
if ! grep -q '^db_container=frappe-test-db-1$' "$DIR/manifest.txt"; then
  echo "Refusing restore: db container mismatch" >&2
  exit 1
fi
if docker ps --format '{{.Names}}' | grep -q '^frappe-backend-1$'; then
  echo "Prod container exists on host but will not be touched. Continuing test-only restore."
fi

echo "Verifying checksums"
cd "$DIR"
sha256sum -c SHA256SUMS.txt

echo "Enabling maintenance mode on test"
docker exec "$BACKEND_CONTAINER" bench --site "$SITE" set-maintenance-mode on || true

echo "Restoring test database $DB"
docker exec "$DB_CONTAINER" mariadb -uroot -p"$DB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS \`$DB\`; CREATE DATABASE \`$DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
gzip -dc "$DIR/database.sql.gz" | docker exec -i "$DB_CONTAINER" mariadb -uroot -p"$DB_ROOT_PASSWORD" "$DB"

echo "Restoring test site files"
rm -rf "$SITES_ROOT/$SITE/public" "$SITES_ROOT/$SITE/private" "$SITES_ROOT/$SITE/site_config.json"
tar -C "$SITES_ROOT" -xzf "$DIR/site_files.tar.gz"

echo "Clearing cache and disabling maintenance mode on test"
docker exec "$BACKEND_CONTAINER" bench --site "$SITE" clear-cache || true
docker exec "$BACKEND_CONTAINER" bench --site "$SITE" clear-website-cache || true
docker exec "$BACKEND_CONTAINER" bench --site "$SITE" set-maintenance-mode off || true

echo "Restarting test containers only"
docker restart frappe-test-backend-1 frappe-test-frontend-1 frappe-test-websocket-1 frappe-test-queue-short-1 frappe-test-queue-long-1 frappe-test-scheduler-1 >/dev/null

echo "Restored test to T-1.1.12 from $DIR"
