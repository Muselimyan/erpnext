#!/usr/bin/env bash
set -euo pipefail

docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console <<'PY'
import frappe
name = "dispatch_task_accept"
doc = frappe.get_doc("Server Script", name)
script = doc.script or ""
old = 'if allowed and not any(r in user_roles for r in allowed) and frappe.session.user != "Administrator" and "System Manager" not in user_roles:\n    frappe.throw("You are not allowed to accept this task kind. Required role: " + ", ".join(allowed))'
new = 'has_allowed_role = False\nfor r in allowed:\n    if r in user_roles:\n        has_allowed_role = True\n\nif allowed and not has_allowed_role and frappe.session.user != "Administrator" and "System Manager" not in user_roles:\n    frappe.throw("You are not allowed to accept this task kind. Required role: " + ", ".join(allowed))'
if old not in script and new not in script:
    raise Exception("Expected role check block not found")
if old in script:
    doc.script = script.replace(old, new, 1)
    doc.save(ignore_permissions=True)
    frappe.db.commit()
    print("patched")
else:
    print("already patched")
script = frappe.db.get_value("Server Script", name, "script") or ""
print("uses_any=", "any(r in user_roles for r in allowed)" in script)
print("uses_loop=", "has_allowed_role = False" in script)
PY

docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache
