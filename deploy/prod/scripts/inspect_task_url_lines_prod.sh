#!/usr/bin/env bash
set -euo pipefail

docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N <<'SQL'
select concat('--- ', name, ' ---\n', script) from `_f98256a6d2bdfda2`.`tabServer Script`
where name in ('Telegram Task Assignment Notification','Telegram Task Status Update');
SQL
