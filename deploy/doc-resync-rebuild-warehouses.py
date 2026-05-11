# -*- coding: utf-8 -*-
"""
doc-resync-rebuild-warehouses.py
1. Delete all existing H/D client warehouses
2. Create new warehouses from /home/frappe/wh.txt

wh.txt format:
  header line (skip)
  H### - <hospital_short_name>
  D### - <doctor_name> - <hospital_short_name>
"""
from __future__ import unicode_literals
import frappe
import re

ABBR    = "Inmed"
COMPANY = "InMED"
CLIENTS = "Clients - Inmed"
EM      = "\u2014"   # em-dash


def log(msg):
    print(msg)


# ── STEP 1a: Delete D warehouses (leaves) ────────────────────────────────────
log("\n=== Step 1a: Delete D warehouses ===")
all_wh = frappe.db.get_all("Warehouse", fields=["name", "warehouse_name"])

d_rows = [w for w in all_wh if re.match(r"^D\d{3}\b", w.warehouse_name or "")]
log(f"  Found {len(d_rows)}")
for row in sorted(d_rows, key=lambda w: w.warehouse_name):
    try:
        frappe.delete_doc("Warehouse", row.name, force=True, ignore_permissions=True)
        log(f"  Deleted: {row.name!r}")
    except Exception as e:
        log(f"  WARN: {row.name!r}: {e}")
frappe.db.commit()

# ── STEP 1b: Delete H warehouses (groups) ────────────────────────────────────
log("\n=== Step 1b: Delete H warehouses ===")
h_rows = [w for w in all_wh if re.match(r"^H\d{3}\b", w.warehouse_name or "")]
log(f"  Found {len(h_rows)}")
for row in sorted(h_rows, key=lambda w: w.warehouse_name):
    try:
        frappe.delete_doc("Warehouse", row.name, force=True, ignore_permissions=True)
        log(f"  Deleted: {row.name!r}")
    except Exception as e:
        log(f"  WARN: {row.name!r}: {e}")
frappe.db.commit()

# ── STEP 2: Parse wh.txt ─────────────────────────────────────────────────────
log("\n=== Step 2: Parse wh.txt ===")
with open("/home/frappe/wh.txt", encoding="utf-8") as f:
    lines = f.readlines()

hospitals = {}  # hosp_display_name -> code
doctors   = []  # [(code, doctor_name, hosp_display_name), ...]

for line in lines[1:]:     # skip header
    line = line.strip()
    if not line:
        continue
    parts = line.split(" - ", 2)
    code  = parts[0].strip()
    if re.match(r"^H\d{3}$", code) and len(parts) == 2:
        hospitals[parts[1].strip()] = code
    elif re.match(r"^D\d{3}$", code) and len(parts) == 3:
        doctors.append((code, parts[1].strip(), parts[2].strip()))
    else:
        log(f"  WARN unexpected line: {line!r}")

log(f"  Hospitals: {len(hospitals)}, Doctors: {len(doctors)}")

# ── STEP 3: Create hospital warehouses ───────────────────────────────────────
log("\n=== Step 3: Create hospitals ===")
hosp_full_map = {}  # hosp_display_name -> full warehouse doc name

for hosp_display, code in sorted(hospitals.items(), key=lambda x: x[1]):
    wh_name = f"{code} {EM} {hosp_display}"
    wh_full = f"{wh_name} - {ABBR}"
    hosp_full_map[hosp_display] = wh_full
    if frappe.db.exists("Warehouse", wh_full):
        log(f"  EXISTS: {wh_full!r}")
        continue
    frappe.get_doc({
        "doctype":          "Warehouse",
        "warehouse_name":   wh_name,
        "parent_warehouse": CLIENTS,
        "company":          COMPANY,
        "is_group":         1,
    }).insert(ignore_permissions=True)
    frappe.db.commit()
    log(f"  Created: {wh_full!r}")

# ── STEP 4: Create doctor warehouses ─────────────────────────────────────────
log("\n=== Step 4: Create doctors ===")
for code, doctor_name, hosp_display in doctors:
    parent_full = hosp_full_map.get(hosp_display)
    if not parent_full:
        log(f"  WARN hospital not found for {code}: {hosp_display!r}")
        continue
    wh_name = f"{code} {EM} {doctor_name} {hosp_display}"
    wh_full = f"{wh_name} - {ABBR}"
    if frappe.db.exists("Warehouse", wh_full):
        log(f"  EXISTS: {wh_full!r}")
        continue
    frappe.get_doc({
        "doctype":          "Warehouse",
        "warehouse_name":   wh_name,
        "parent_warehouse": parent_full,
        "company":          COMPANY,
        "is_group":         0,
    }).insert(ignore_permissions=True)
    frappe.db.commit()
    log(f"  Created: {wh_full!r}")

# ── Rebuild tree ──────────────────────────────────────────────────────────────
log("\n=== Rebuild tree ===")
from frappe.utils.nestedset import rebuild_tree as _rt
import inspect
if len(inspect.signature(_rt).parameters) >= 2:
    _rt("Warehouse", "parent_warehouse")
else:
    _rt("Warehouse")
frappe.db.commit()
log("Done.")
