#!/usr/bin/env bash
set -euo pipefail

cat >/tmp/sync_approved_prod_to_test.py <<'PY'
import frappe

SOURCE_DB = "_f98256a6d2bdfda2"
client_scripts = [
    "Task-Account Details UI Cleanup",
    "Task-Other UI Cleanup",
]
server_scripts = [
    "Task-after-save-other-processing",
    "Task-Other Entry Default Subject",
]

def source_row(table, name):
    rows = frappe.db.sql(f"select * from `{SOURCE_DB}`.`tab{table}` where name=%s", name, as_dict=True)
    if not rows:
        raise Exception(f"Missing source {table}: {name}")
    return rows[0]

def upsert_doc(doctype, name):
    row = source_row(doctype, name)
    meta = frappe.get_meta(doctype)
    data = {"doctype": doctype, "name": name, "__newname": name}
    for field in meta.fields:
        if field.fieldname in row and field.fieldtype not in ("Table", "Table MultiSelect"):
            data[field.fieldname] = row[field.fieldname]
    if frappe.db.exists(doctype, name):
        doc = frappe.get_doc(doctype, name)
        for key, value in data.items():
            if key not in ("doctype", "name", "__newname"):
                setattr(doc, key, value)
        doc.flags.ignore_permissions = True
        doc.save(ignore_permissions=True)
        return "updated"
    doc = frappe.get_doc(data)
    doc.flags.ignore_permissions = True
    doc.insert(ignore_permissions=True)
    return "inserted"

for name in client_scripts:
    print(f"Client Script {name}: {upsert_doc('Client Script', name)}")
for name in server_scripts:
    print(f"Server Script {name}: {upsert_doc('Server Script', name)}")
frappe.db.commit()
PY

docker cp /tmp/sync_approved_prod_to_test.py frappe-test-backend-1:/tmp/sync_approved_prod_to_test.py
docker exec frappe-test-backend-1 bench --site test.erpnext.am execute frappe.utils.bench_helper.execute_in_shell --kwargs "{'commands': ['python /tmp/sync_approved_prod_to_test.py']}" || docker exec frappe-test-backend-1 bench --site test.erpnext.am console < /tmp/sync_approved_prod_to_test.py
docker exec frappe-test-backend-1 rm -f /tmp/sync_approved_prod_to_test.py
docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache
