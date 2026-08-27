#!/usr/bin/env bash
set -euo pipefail
docker cp /tmp/_live_Global_Mobile_Back_Button_List_test.js frappe-test-backend-1:/tmp/_live_Global_Mobile_Back_Button_List_test.js
docker cp /tmp/apply_task_toggle_owner_fix_test.py frappe-test-backend-1:/tmp/apply_task_toggle_owner_fix_test.py
docker exec frappe-test-backend-1 bash -lc "cd /home/frappe/frappe-bench && printf '%s\n' \"exec(open('/tmp/apply_task_toggle_owner_fix_test.py').read())\" | bench --site test.erpnext.am console"
