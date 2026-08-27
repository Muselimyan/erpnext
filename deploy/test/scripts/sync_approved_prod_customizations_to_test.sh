#!/usr/bin/env bash
set -euo pipefail

docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console <<'PY'
import frappe

SOURCE_DB = "_f98256a6d2bdfda2"
TARGET_DB = "_b9d33ed61d78a9f2"

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
    data = {}
    for field in meta.fields:
        if field.fieldname in row and field.fieldtype not in ("Table", "Table MultiSelect"):
            data[field.fieldname] = row[field.fieldname]
    data["doctype"] = doctype
    data["name"] = name
    data["__newname"] = name
    if frappe.db.exists(doctype, name):
        doc = frappe.get_doc(doctype, name)
        for key, value in data.items():
            if key not in ("doctype", "name", "__newname"):
                setattr(doc, key, value)
        doc.flags.ignore_permissions = True
        doc.save(ignore_permissions=True)
        action = "updated"
    else:
        doc = frappe.get_doc(data)
        doc.flags.ignore_permissions = True
        doc.insert(ignore_permissions=True)
        action = "inserted"
    return action

for name in client_scripts:
    print(f"Client Script {name}: {upsert_doc('Client Script', name)}")
for name in server_scripts:
    print(f"Server Script {name}: {upsert_doc('Server Script', name)}")

frappe.db.commit()
print("done")
PY

docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache
