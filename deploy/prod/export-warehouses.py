# -*- coding: utf-8 -*-
"""Export tabWarehouse to /tmp/warehouses.csv with headers."""
import frappe, csv

fields = [
    "name", "owner", "creation", "modified", "modified_by",
    "docstatus", "idx", "warehouse_name", "company",
    "disabled", "is_group", "lft", "rgt", "parent_warehouse",
]

rows = frappe.db.sql(
    f"SELECT {', '.join(f'`{f}`' for f in fields)} FROM `tabWarehouse` ORDER BY lft",
    as_dict=False,
)

with open("/tmp/warehouses.csv", "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f, quoting=csv.QUOTE_ALL)
    w.writerow(fields)
    w.writerows(rows)

print(f"Exported {len(rows)} rows")
