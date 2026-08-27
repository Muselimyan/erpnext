#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="/root/erpnext-version-snapshots"
STAMP="20260810T163934Z"
PROD_DIR="$BASE_DIR/prod_P-1.1.1_$STAMP"
TEST_DIR="$BASE_DIR/test_T-1.1.1_$STAMP"

for dir in "$PROD_DIR" "$TEST_DIR"; do
  if [ ! -d "$dir" ]; then
    echo "missing_dir=$dir"
    exit 1
  fi
  find "$dir" -type f -print0 | sort -z | xargs -0 sha256sum > "$dir/SHA256SUMS.txt"
  du -sh "$dir"
  find "$dir" -maxdepth 2 -type f -printf '%p\t%s bytes\n' | sort
  echo
 done

cat > "$BASE_DIR/VERSION_INDEX_$STAMP.txt" <<EOF
created_utc=$STAMP
prod_version=P-1.1.1
prod_dir=$PROD_DIR
prod_url=https://erpnext.am
prod_site=161.97.83.156
test_version=T-1.1.1
test_dir=$TEST_DIR
test_url=https://test.erpnext.am
test_site=test.erpnext.am
backup_contents=bench_backup,database.sql.gz,site_files.tar.gz,manifest.txt,SHA256SUMS.txt
EOF

cat "$BASE_DIR/VERSION_INDEX_$STAMP.txt"
