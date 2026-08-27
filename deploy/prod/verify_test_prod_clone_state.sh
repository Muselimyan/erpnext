#!/usr/bin/env bash
set -euo pipefail

echo "containers"
docker ps --format '{{.Names}} {{.Status}}' | grep -E '^(frappe|frappe-test)-(backend|db|frontend|queue|scheduler|websocket)-1' || true

echo "restore processes"
ps aux | grep -E 'bench --site 161.97.83.156 restore|mariadb|mysql' | grep -v grep || true

echo "prod sql counts"
docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N <<'SQL'
select 'Task', count(*) from `_f98256a6d2bdfda2`.`tabTask`;
select 'Client Script', count(*) from `_f98256a6d2bdfda2`.`tabClient Script`;
select 'Server Script', count(*) from `_f98256a6d2bdfda2`.`tabServer Script`;
SQL

echo "test sql counts"
docker exec -i frappe-test-db-1 mariadb -uroot -ptSt7f92k1QzR -N <<'SQL'
select 'Task', count(*) from `_b9d33ed61d78a9f2`.`tabTask`;
select 'Client Script', count(*) from `_b9d33ed61d78a9f2`.`tabClient Script`;
select 'Server Script', count(*) from `_b9d33ed61d78a9f2`.`tabServer Script`;
SQL

echo "prod site config"
docker exec frappe-backend-1 cat /home/frappe/frappe-bench/sites/161.97.83.156/site_config.json
