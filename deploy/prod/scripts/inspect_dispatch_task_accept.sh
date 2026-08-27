#!/usr/bin/env bash
set -euo pipefail

echo "=== PROD dispatch_task_accept ==="
docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N <<'SQL'
select script from `_f98256a6d2bdfda2`.`tabServer Script` where name='dispatch_task_accept';
SQL

echo "=== TEST dispatch_task_accept ==="
docker exec -i frappe-test-db-1 mariadb -uroot -ptSt7f92k1QzR -N <<'SQL'
select script from `_b9d33ed61d78a9f2`.`tabServer Script` where name='dispatch_task_accept';
SQL
