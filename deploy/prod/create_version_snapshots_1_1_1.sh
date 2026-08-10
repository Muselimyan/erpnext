#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/root/erpnext-version-snapshots"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BASE_DIR"

snapshot_env() {
  local env="$1"
  local version="$2"
  local site="$3"
  local backend="$4"
  local db_container="$5"
  local db_name="$6"
  local db_password="$7"
  local sites_volume_mount="$8"
  local url="$9"
  local dir="$BASE_DIR/${env}_${version}_${STAMP}"
  mkdir -p "$dir"

  echo "Creating $env $version at $dir"

  docker exec "$backend" bench --site "$site" backup --with-files --compress --backup-path "/tmp/${env}_${version}_${STAMP}_bench_backup"
  docker cp "$backend:/tmp/${env}_${version}_${STAMP}_bench_backup" "$dir/bench_backup"
  docker exec "$backend" rm -rf "/tmp/${env}_${version}_${STAMP}_bench_backup"

  docker exec "$db_container" mariadb-dump -uroot -p"$db_password" --single-transaction --routines --triggers "$db_name" | gzip > "$dir/database.sql.gz"

  tar -C "$sites_volume_mount" -czf "$dir/site_files.tar.gz" "$site/public" "$site/private" "$site/site_config.json"

  cat > "$dir/manifest.txt" <<EOF
version=$version
environment=$env
url=$url
created_utc=$STAMP
site=$site
backend_container=$backend
db_container=$db_container
db_name=$db_name
backup_type=bench_backup_plus_mariadb_dump_plus_site_files
restore_note=Use only after confirming target environment. DB and files are included.
EOF

  sha256sum "$dir"/* > "$dir/SHA256SUMS.txt"
  echo "$dir"
}

PROD_DIR=$(snapshot_env "prod" "P-1.1.1" "161.97.83.156" "frappe-backend-1" "frappe-db-1" "_f98256a6d2bdfda2" "fd88f0ff7" "/var/lib/docker/volumes/frappe_sites/_data" "https://erpnext.am")
TEST_DIR=$(snapshot_env "test" "T-1.1.1" "test.erpnext.am" "frappe-test-backend-1" "frappe-test-db-1" "_b9d33ed61d78a9f2" "tSt7f92k1QzR" "/var/lib/docker/volumes/frappe-test_sites/_data" "https://test.erpnext.am")

cat > "$BASE_DIR/VERSION_INDEX_${STAMP}.txt" <<EOF
created_utc=$STAMP
prod_version=P-1.1.1
prod_dir=$PROD_DIR
test_version=T-1.1.1
test_dir=$TEST_DIR
EOF

cat "$BASE_DIR/VERSION_INDEX_${STAMP}.txt"
