#!/usr/bin/env bash
set -euo pipefail

echo "=== PROD ==="
docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N <<'SQL'
select name,
       script like '%frappe.conf.get%' as uses_conf_get,
       script like '%frappe.utils.get_url%' as uses_get_url,
       script like '%https://erpnext.am%' as has_prod_url,
       script like '%https://test.erpnext.am/app/task%' as has_test_task_url
from `_f98256a6d2bdfda2`.`tabServer Script`
where name in ('Telegram Task Assignment Notification','Telegram Task Status Update')
order by name;
SQL

echo "=== TEST ==="
docker exec -i frappe-test-db-1 mariadb -uroot -ptSt7f92k1QzR -N <<'SQL'
select name,
       script like '%frappe.conf.get%' as uses_conf_get,
       script like '%frappe.utils.get_url%' as uses_get_url,
       script like '%https://test.erpnext.am%' as has_test_url,
       script like '%https://erpnext.am/app/task%' as has_prod_task_url
from `_b9d33ed61d78a9f2`.`tabServer Script`
where name in ('Telegram Task Assignment Notification','Telegram Task Status Update')
order by name;
SQL
