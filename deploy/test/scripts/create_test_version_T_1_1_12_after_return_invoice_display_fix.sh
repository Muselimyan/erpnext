#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="/root/erpnext-version-snapshots"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
VERSION="T-1.1.12"
DIR="$BASE_DIR/test_${VERSION}_${STAMP}"
PURPOSE="Current test working state after return restocking and invoice preparation display fixes"
IMPROVEMENTS="Snapshot after Task product display fixes on test: Returns restocking shows only Dispatch Case rows with returned_qty greater than 0 and Invoice preparation shows only rows with used_qty greater than 0 or lost_damaged_qty greater than 0, with no checkboxes in either review/restock display. Full return path DC-2026-00133 was completed through debt closure approval."
mkdir -p "$DIR"

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

du -sh "$DIR"
cat "$BASE_DIR/VERSION_INDEX_${STAMP}_${VERSION}.txt"
