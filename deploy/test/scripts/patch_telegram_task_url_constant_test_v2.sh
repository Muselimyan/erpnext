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
    out = []
    did = False
    for line in script.split("\n"):
        stripped = line.strip()
        indent = line[:len(line) - len(line.lstrip())]
        if stripped == 'task_url = f"{(frappe.conf.get(\'host_name\') or frappe.utils.get_url()).rstrip(\'/\')}/app/task/{task_name}"':
            out.append(indent + 'base_url = "https://test.erpnext.am"')
            out.append(indent + 'task_url = f"{base_url}/app/task/{task_name}"')
            did = True
        elif stripped == 'task_url = f"{(frappe.conf.get(\'host_name\') or frappe.utils.get_url()).rstrip(\'/\')}/app/task/{doc.name}"':
            out.append(indent + 'base_url = "https://test.erpnext.am"')
            out.append(indent + 'task_url = f"{base_url}/app/task/{doc.name}"')
            did = True
        else:
            out.append(line)
    new_script = "\n".join(out)
    if did:
        doc.script = new_script
        doc.save(ignore_permissions=True)
        changed.append(name)
frappe.db.commit()
print("changed=", changed)
for name in scripts:
    if frappe.db.exists("Server Script", name):
        script = frappe.db.get_value("Server Script", name, "script") or ""
        print(name, "uses_conf_get=", "frappe.conf.get" in script, "test_url=", "https://test.erpnext.am" in script, "hardcoded_prod_task_url=", "https://erpnext.am/app/task" in script)
PY

docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache
