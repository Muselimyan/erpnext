#!/usr/bin/env bash
set -euo pipefail

echo "=== PROD ==="
docker exec -i frappe-db-1 mariadb -uroot -pfd88f0ff7 -N <<'SQL'
select name,
       script like '%https://test.erpnext.am/app/task/%' as has_test_task_url,
       script like '%frappe.conf.get(''host_name'')%' as uses_host_name,
       script like '%/app/task/{task_name}%' as assignment_url_dynamic,
       script like '%/app/task/{doc.name}%' as status_url_dynamic
from `_f98256a6d2bdfda2`.`tabServer Script`
where name in ('Telegram Task Assignment Notification','Telegram Task Status Update')
order by name;
SQL

echo "=== TEST ==="
docker exec -i frappe-test-db-1 mariadb -uroot -ptSt7f92k1QzR -N <<'SQL'
select name,
       script like '%https://test.erpnext.am/app/task/%' as has_test_task_url,
       script like '%frappe.conf.get(''host_name'')%' as uses_host_name,
       script like '%/app/task/{task_name}%' as assignment_url_dynamic,
       script like '%/app/task/{doc.name}%' as status_url_dynamic
from `_b9d33ed61d78a9f2`.`tabServer Script`
where name in ('Telegram Task Assignment Notification','Telegram Task Status Update')
order by name;
SQL

echo "=== HOST NAMES ==="
docker exec frappe-backend-1 bench --site 161.97.83.156 show-config | grep -E '^host_name|^server_script_enabled' || true
docker exec frappe-test-backend-1 bench --site test.erpnext.am show-config | grep -E '^host_name|^server_script_enabled' || true
