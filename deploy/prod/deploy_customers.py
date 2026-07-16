# -*- coding: utf-8 -*-
"""
deploy_customers.py
1. Delete all existing customers (and blocking SOs, SIs, PEs)
2. Create customers from /home/frappe/customers_preview.csv

CSV columns (tab-separated, UTF-8 BOM):
  client_code | customer_name | client_kind | customer_group |
  hospital    | doctor_name   | debt_threshold_amd | is_provisional
"""
from __future__ import unicode_literals
import frappe, csv

def log(msg):
    print(msg)


# ── PHASE 0: Ensure client_code is NOT unique ─────────────────────────────────
log("=== Removing unique constraint on client_code ===")
try:
    frappe.db.sql("ALTER TABLE `tabCustomer` DROP INDEX `client_code`")
    frappe.db.commit()
    log("  Dropped unique index on client_code")
except Exception as e:
    log(f"  (no index to drop or already gone: {e})")


# ── PHASE 1: Delete blocking docs + customers ─────────────────────────────────
log("=== Cancelling / deleting Sales Orders ===")
for o in frappe.db.get_all("Sales Order", fields=["name", "docstatus"]):
    try:
        if o.docstatus == 1:
            frappe.get_doc("Sales Order", o.name).cancel()
            frappe.db.commit()
        frappe.delete_doc("Sales Order", o.name, force=True, ignore_permissions=True)
        frappe.db.commit()
        log(f"  Deleted SO: {o.name}")
    except Exception as e:
        log(f"  WARN SO {o.name}: {e}")

log("\n=== Deleting Sales Invoices ===")
for inv in frappe.db.get_all("Sales Invoice", fields=["name", "docstatus"]):
    try:
        if inv.docstatus == 1:
            frappe.get_doc("Sales Invoice", inv.name).cancel()
            frappe.db.commit()
        frappe.delete_doc("Sales Invoice", inv.name, force=True, ignore_permissions=True)
        frappe.db.commit()
        log(f"  Deleted SI: {inv.name}")
    except Exception as e:
        log(f"  WARN SI {inv.name}: {e}")

log("\n=== Deleting Payment Entries ===")
for p in frappe.db.get_all("Payment Entry", fields=["name", "docstatus"]):
    try:
        if p.docstatus == 1:
            frappe.get_doc("Payment Entry", p.name).cancel()
            frappe.db.commit()
        frappe.delete_doc("Payment Entry", p.name, force=True, ignore_permissions=True)
        frappe.db.commit()
        log(f"  Deleted PE: {p.name}")
    except Exception as e:
        log(f"  WARN PE {p.name}: {e}")

log("\n=== Deleting Customers ===")
SKIP = {"Walk-In Customer"}
for c in frappe.db.get_all("Customer", fields=["name"]):
    if c.name in SKIP:
        continue
    try:
        frappe.delete_doc("Customer", c.name, force=True, ignore_permissions=True)
        frappe.db.commit()
        log(f"  Deleted: {c.name}")
    except Exception as e:
        log(f"  WARN {c.name}: {e}")


# ── PHASE 2: Parse CSV ────────────────────────────────────────────────────────
log("\n=== Parsing customers_preview.csv ===")
with open("/home/frappe/customers_preview.csv", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f, delimiter="\t")
    rows = [r for r in reader
            if r["client_code"].strip() not in ("", ".")]

h_rows = [r for r in rows if r["client_kind"].strip() == "Hospital"]
d_rows = [r for r in rows if r["client_kind"].strip() == "Doctor"]
log(f"  Hospitals: {len(h_rows)}, Doctors: {len(d_rows)}")


# ── PHASE 3: Create hospital customers ───────────────────────────────────────
log("\n=== Creating hospital customers ===")
# hosp_short (stripped hospital column) → customer doc name
hosp_map = {}

for r in h_rows:
    cname      = r["customer_name"].strip()
    ccode      = r["client_code"].strip()
    cgroup     = r["customer_group"].strip()
    hosp_short = r["hospital"].strip()
    debt       = float(r["debt_threshold_amd"].strip() or 0)
    is_prov    = int(r["is_provisional"].strip() or 0)

    existing = frappe.db.get_value("Customer", {"customer_name": cname}, "name")
    if existing:
        hosp_map[hosp_short] = existing
        log(f"  EXISTS: {cname!r}")
        continue

    doc = frappe.get_doc({
        "doctype":            "Customer",
        "customer_name":      cname,
        "customer_group":     cgroup,
        "customer_type":      "Company",
        "client_code":        ccode,
        "client_kind":        "Hospital",
        "debt_threshold_amd": debt,
        "is_provisional":     is_prov,
    }).insert(ignore_permissions=True)
    frappe.db.commit()
    hosp_map[hosp_short] = doc.name
    log(f"  Created: {doc.name!r}")


# ── PHASE 4: Create doctor customers ─────────────────────────────────────────
log("\n=== Creating doctor customers ===")
for r in d_rows:
    cname      = r["customer_name"].strip()
    ccode      = r["client_code"].strip()
    cgroup     = r["customer_group"].strip()
    hosp_short = r["hospital"].strip()
    dname      = r["doctor_name"].strip()
    debt       = float(r["debt_threshold_amd"].strip() or 0)
    is_prov    = int(r["is_provisional"].strip() or 0)
    hosp_link  = hosp_map.get(hosp_short)

    if not hosp_link:
        log(f"  WARN no hospital found for {ccode}: {hosp_short!r}")

    existing = frappe.db.get_value("Customer", {"customer_name": cname}, "name")
    if existing:
        log(f"  EXISTS: {cname!r}")
        continue

    doc = frappe.get_doc({
        "doctype":            "Customer",
        "customer_name":      cname,
        "customer_group":     cgroup,
        "customer_type":      "Individual",
        "client_code":        ccode,
        "client_kind":        "Doctor",
        "hospital":           hosp_link,
        "doctor_name":        dname,
        "debt_threshold_amd": debt,
        "is_provisional":     is_prov,
    }).insert(ignore_permissions=True)
    frappe.db.commit()
    log(f"  Created: {doc.name!r}")

log("\nDone.")
remaining = frappe.db.count("Customer")
log(f"Customers now: {remaining}")
