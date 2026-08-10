#!/usr/bin/env bash
set -euo pipefail
PROD_DB="_f98256a6d2bdfda2"
TEST_DB="_b9d33ed61d78a9f2"
prod() { docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N "$PROD_DB"; }
testdb() { docker exec -i frappe-test-db-1 mariadb -uroot -ptSt7f92k1QzR -N "$TEST_DB"; }

echo "=== Approved Client Scripts hashes ==="
SQL_CLIENT="select name, sha2(coalesce(script,''),256) from \`tabClient Script\` where name in ('Task-Account Details UI Cleanup','Task-Other UI Cleanup') order by name;"
echo "-- prod"; echo "$SQL_CLIENT" | prod
echo "-- test"; echo "$SQL_CLIENT" | testdb

echo "=== Approved Server Scripts hashes ==="
SQL_SERVER="select name, sha2(coalesce(script,''),256) from \`tabServer Script\` where name in ('Task-after-save-other-processing','Task-Other Entry Default Subject') order by name;"
echo "-- prod"; echo "$SQL_SERVER" | prod
echo "-- test"; echo "$SQL_SERVER" | testdb

echo "=== Telegram URL markers on test must remain test URL ==="
echo "select name, script like '%https://test.erpnext.am%' as has_test_url, script like '%https://erpnext.am%' as has_prod_url from \`tabServer Script\` where name in ('Telegram Task Assignment Notification','Telegram Task Status Update') order by name;" | testdb

echo "=== Operational counts after sync ==="
for table in Task ToDo Comment File; do
  p=$(echo "select count(*) from \`tab$table\`;" | prod)
  t=$(echo "select count(*) from \`tab$table\`;" | testdb)
  echo "$table prod=$p test=$t"
done
