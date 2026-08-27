#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="/root/erpnext-version-snapshots"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
VERSION="P-1.1.5"
DIR="$BASE_DIR/prod_${VERSION}_${STAMP}"
PURPOSE="Pre header overlap mobile/both UI fix rollback point"
IMPROVEMENTS="Rollback snapshot before promoting any Task header title/button vertical overlap fix to production."
mkdir -p "$DIR"

echo "Creating prod $VERSION at $DIR"
docker exec frappe-backend-1 bench --site 161.97.83.156 backup --with-files --compress --backup-path "/tmp/prod_${VERSION}_${STAMP}_bench_backup"
docker cp "frappe-backend-1:/tmp/prod_${VERSION}_${STAMP}_bench_backup" "$DIR/bench_backup"
docker exec frappe-backend-1 rm -rf "/tmp/prod_${VERSION}_${STAMP}_bench_backup"
docker exec frappe-db-1 mariadb-dump -uroot -pfd88f0ff7 --single-transaction --routines --triggers _f98256a6d2bdfda2 | gzip > "$DIR/database.sql.gz"
tar -C /var/lib/docker/volumes/frappe_sites/_data -czf "$DIR/site_files.tar.gz" 161.97.83.156/public 161.97.83.156/private 161.97.83.156/site_config.json
cat > "$DIR/manifest.txt" <<EOF
version=$VERSION
environment=prod
url=https://erpnext.am
created_utc=$STAMP
site=161.97.83.156
backend_container=frappe-backend-1
db_container=frappe-db-1
db_name=_f98256a6d2bdfda2
backup_type=bench_backup_plus_mariadb_dump_plus_site_files
purpose=$PURPOSE
improvements=$IMPROVEMENTS
backup_contents=bench_backup,database.sql.gz,site_files.tar.gz,manifest.txt,SHA256SUMS.txt
restore_note=Use only after confirming target environment. DB and files are included.
EOF
find "$DIR" -type f ! -name "SHA256SUMS*" -print0 | sort -z | xargs -0 sha256sum > "$DIR/SHA256SUMS.txt"
cat > "$BASE_DIR/VERSION_INDEX_${STAMP}_${VERSION}.txt" <<EOF
created_utc=$STAMP
prod_version=$VERSION
prod_dir=$DIR
prod_url=https://erpnext.am
prod_site=161.97.83.156
purpose=$PURPOSE
improvements=$IMPROVEMENTS
backup_contents=bench_backup,database.sql.gz,site_files.tar.gz,manifest.txt,SHA256SUMS.txt
EOF

du -sh "$DIR"
cat "$BASE_DIR/VERSION_INDEX_${STAMP}_${VERSION}.txt"
