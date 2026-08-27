#!/usr/bin/env bash
set -euo pipefail
docker cp /tmp/_live_Task_Packing_Checkboxes_current.js frappe-test-backend-1:/tmp/_live_Task_Packing_Checkboxes_current.js
docker cp /tmp/apply_task_packing_mobile_dashboard_test.py frappe-test-backend-1:/tmp/apply_task_packing_mobile_dashboard_test.py
docker exec frappe-test-backend-1 bash -lc "cd /home/frappe/frappe-bench && printf '%s\n' \"exec(open('/tmp/apply_task_packing_mobile_dashboard_test.py').read())\" | bench --site test.erpnext.am console"
docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache
