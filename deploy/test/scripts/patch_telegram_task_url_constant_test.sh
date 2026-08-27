#!/usr/bin/env bash
set -euo pipefail

docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console <<'PY'
import frappe
scripts = ["Telegram Task Assignment Notification", "Telegram Task Status Update"]
changed = []
for name in scripts:
    if not frappe.db.exists("Server Script", name):
        continue
    doc = frappe.get_doc("Server Script", name)
    script = doc.script or ""
    new_script = script
    new_script = new_script.replace(
        'task_url = f"{(frappe.conf.get(\'host_name\') or frappe.utils.get_url()).rstrip(\'/\')}/app/task/{task_name}"',
        'base_url = "https://test.erpnext.am"\ntask_url = f"{base_url}/app/task/{task_name}"'
    )
    new_script = new_script.replace(
        'task_url = f"{(frappe.conf.get(\'host_name\') or frappe.utils.get_url()).rstrip(\'/\')}/app/task/{doc.name}"',
        'base_url = "https://test.erpnext.am"\ntask_url = f"{base_url}/app/task/{doc.name}"'
    )
    if new_script != script:
        doc.script = new_script
        doc.save(ignore_permissions=True)
        changed.append(name)
frappe.db.commit()
print("changed=", changed)
for name in scripts:
    if frappe.db.exists("Server Script", name):
        script = frappe.db.get_value("Server Script", name, "script") or ""
        print(name, "uses_conf_get=", "frappe.conf.get" in script, "test_url=", "https://test.erpnext.am" in script, "prod_url=", "https://erpnext.am/app/task" in script)
PY

docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache
