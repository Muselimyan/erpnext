#!/usr/bin/env bash
set -euo pipefail

echo "=== PROD Client Scripts matching Account Details / Task UI ==="
docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N <<'SQL'
select name, dt, enabled, length(script) from `_f98256a6d2bdfda2`.`tabClient Script`
where dt='Task' and (name like '%Account%' or script like '%Account Details%' or script like '%task_kind%' or script like '%custom_photo%' or script like '%preview%')
order by name;
SQL

echo "=== Script snippets ==="
docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N <<'SQL'
select concat('--- ', name, ' ---\n', script) from `_f98256a6d2bdfda2`.`tabClient Script`
where dt='Task' and (name like '%Account%' or script like '%Account Details%' or script like '%custom_photo%' or script like '%preview%')
order by name;
SQL
