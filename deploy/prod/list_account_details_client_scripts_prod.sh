#!/usr/bin/env bash
set -euo pipefail

docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N <<'SQL'
select name, enabled, length(script)
from `_f98256a6d2bdfda2`.`tabClient Script`
where dt='Task'
  and (name like '%Account%' or script like '%Account Details: Processing%' or script like '%Task-Account Details UI Cleanup%')
order by name;
SQL
