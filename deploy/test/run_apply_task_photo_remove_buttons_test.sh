#!/usr/bin/env bash
set -euo pipefail
docker cp /tmp/task-photo-remove-buttons-test.js frappe-test-backend-1:/tmp/task-photo-remove-buttons-test.js
docker cp /tmp/apply_task_photo_remove_buttons_test.py frappe-test-backend-1:/tmp/apply_task_photo_remove_buttons_test.py
docker exec frappe-test-backend-1 bash -lc "cd /home/frappe/frappe-bench && printf '%s\n' \"exec(open('/tmp/apply_task_photo_remove_buttons_test.py').read())\" | bench --site test.erpnext.am console"
