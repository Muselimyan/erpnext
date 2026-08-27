#!/usr/bin/env bash
set -euo pipefail

docker exec -i frappe-backend-1 bench --site 161.97.83.156 console <<'PY'
import frappe
scripts = ["Telegram Task Assignment Notification", "Telegram Task Status Update"]
changed = []
for name in scripts:
    if not frappe.db.exists("Server Script", name):
        continue
    doc = frappe.get_doc("Server Script", name)
    script = doc.script or ""
    replacements = {
        'task_url = f"https://test.erpnext.am/app/task/{doc.name}"': 'task_url = f"{(frappe.conf.get(\'host_name\') or frappe.utils.get_url()).rstrip(\'/\')}/app/task/{doc.name}"',
        'task_url = f"https://test.erpnext.am/app/task/{task_name}"': 'task_url = f"{(frappe.conf.get(\'host_name\') or frappe.utils.get_url()).rstrip(\'/\')}/app/task/{task_name}"',
    }
    new_script = script
    for old, new in replacements.items():
        new_script = new_script.replace(old, new)
    if new_script != script:
        doc.script = new_script
        doc.save(ignore_permissions=True)
        changed.append(name)
frappe.db.commit()
print("changed=", changed)
for name in scripts:
    if frappe.db.exists("Server Script", name):
        script = frappe.db.get_value("Server Script", name, "script") or ""
        print(name, "has_test_url=", "https://test.erpnext.am/app/task/" in script, "uses_host_name=", "frappe.conf.get('host_name')" in script)
PY

docker exec frappe-backend-1 bench --site 161.97.83.156 clear-cache
