#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="/root/erpnext-version-snapshots"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
VERSION="T-1.1.13"
DIR="$BASE_DIR/test_${VERSION}_${STAMP}"
PURPOSE="Current test working state after restoring backup and adding Order entry next-task assignment visibility"
IMPROVEMENTS="Snapshot after restoring test to T-1.1.12 and reapplying the stable Order entry Next Task: Assign To visibility fix on test. Custom Field Task-custom_next_task_assign_to now includes Order entry in depends_on so the next-task assignment box appears in Order entry tasks on desktop and mobile. No photo-delete or packing-dashboard experiments are included."
mkdir -p "$DIR"

if docker ps --format '{{.Names}}' | grep -q '^frappe-backend-1$'; then
  echo "Prod container exists on host but will not be touched. Creating test-only snapshot."
fi
if ! docker ps --format '{{.Names}}' | grep -q '^frappe-test-backend-1$'; then
  echo "Missing frappe-test-backend-1; refusing snapshot." >&2
  exit 1
fi
if ! docker ps --format '{{.Names}}' | grep -q '^frappe-test-db-1$'; then
  echo "Missing frappe-test-db-1; refusing snapshot." >&2
  exit 1
fi

echo "Creating test $VERSION at $DIR"
docker exec frappe-test-backend-1 bench --site test.erpnext.am backup --with-files --compress --backup-path "/tmp/test_${VERSION}_${STAMP}_bench_backup"
docker cp "frappe-test-backend-1:/tmp/test_${VERSION}_${STAMP}_bench_backup" "$DIR/bench_backup"
docker exec frappe-test-backend-1 rm -rf "/tmp/test_${VERSION}_${STAMP}_bench_backup"
docker exec frappe-test-db-1 mariadb-dump -uroot -ptSt7f92k1QzR --single-transaction --routines --triggers _b9d33ed61d78a9f2 | gzip > "$DIR/database.sql.gz"
tar -C /var/lib/docker/volumes/frappe-test_sites/_data -czf "$DIR/site_files.tar.gz" test.erpnext.am/public test.erpnext.am/private test.erpnext.am/site_config.json
cat > "$DIR/manifest.txt" <<EOF
version=$VERSION
environment=test
url=https://test.erpnext.am
created_utc=$STAMP
site=test.erpnext.am
backend_container=frappe-test-backend-1
db_container=frappe-test-db-1
db_name=_b9d33ed61d78a9f2
backup_type=bench_backup_plus_mariadb_dump_plus_site_files
purpose=$PURPOSE
improvements=$IMPROVEMENTS
backup_contents=bench_backup,database.sql.gz,site_files.tar.gz,manifest.txt,SHA256SUMS.txt
restore_note=Use only after confirming target environment. DB and files are included.
EOF
find "$DIR" -type f ! -name "SHA256SUMS*" -print0 | sort -z | xargs -0 sha256sum > "$DIR/SHA256SUMS.txt"
cat > "$BASE_DIR/VERSION_INDEX_${STAMP}_${VERSION}.txt" <<EOF
created_utc=$STAMP
test_version=$VERSION
test_dir=$DIR
test_url=https://test.erpnext.am
test_site=test.erpnext.am
purpose=$PURPOSE
improvements=$IMPROVEMENTS
backup_contents=bench_backup,database.sql.gz,site_files.tar.gz,manifest.txt,SHA256SUMS.txt
EOF

cd "$DIR"
sha256sum -c SHA256SUMS.txt
du -sh "$DIR"
cat "$BASE_DIR/VERSION_INDEX_${STAMP}_${VERSION}.txt"
