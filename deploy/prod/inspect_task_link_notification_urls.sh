#!/usr/bin/env bash
set -euo pipefail

echo "=== PROD host config ==="
docker exec frappe-backend-1 cat /home/frappe/frappe-bench/sites/161.97.83.156/site_config.json

echo "=== TEST host config ==="
docker exec frappe-test-backend-1 cat /home/frappe/frappe-bench/sites/test.erpnext.am/site_config.json

echo "=== PROD scripts mentioning URLs/tasks/telegram ==="
docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N <<'SQL'
select name from `_f98256a6d2bdfda2`.`tabServer Script`
where script like '%test.erpnext.am%' or script like '%erpnext.am%' or script like '%/app/task%' or script like '%telegram%' or script like '%Task%assigned%'
order by name;
SQL

echo "=== TEST scripts mentioning URLs/tasks/telegram ==="
docker exec -i frappe-test-db-1 mariadb -uroot -ptSt7f92k1QzR -N <<'SQL'
select name from `_b9d33ed61d78a9f2`.`tabServer Script`
where script like '%test.erpnext.am%' or script like '%erpnext.am%' or script like '%/app/task%' or script like '%telegram%' or script like '%Task%assigned%'
order by name;
SQL

echo "=== PROD matching script snippets ==="
docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N <<'SQL'
select concat('--- ', name, ' ---\n', substr(script, greatest(1, locate('test.erpnext.am', script)-500), 1400)) from `_f98256a6d2bdfda2`.`tabServer Script`
where script like '%test.erpnext.am%'
order by name;
SQL

echo "=== TEST matching script snippets ==="
docker exec -i frappe-test-db-1 mariadb -uroot -ptSt7f92k1QzR -N <<'SQL'
select concat('--- ', name, ' ---\n', substr(script, greatest(1, locate('test.erpnext.am', script)-500), 1400)) from `_b9d33ed61d78a9f2`.`tabServer Script`
where script like '%test.erpnext.am%'
order by name;
SQL
