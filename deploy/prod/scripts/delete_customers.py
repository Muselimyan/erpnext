"""
delete_customers.py  —  Delete all non-system customers and their blocking docs.
Run inside frappe-backend-1 container via run_step1.sh runner.
"""
import frappe

SKIP = {"Walk-In Customer"}

def log(msg):
    print(msg)

# ── 1. Cancel + delete blocking Sales Orders ──────────────────────────────────
log("=== Cancelling / deleting Sales Orders ===")
orders = frappe.db.get_all("Sales Order", fields=["name", "docstatus"])
for o in orders:
    try:
        if o.docstatus == 1:
            doc = frappe.get_doc("Sales Order", o.name)
            doc.cancel()
            frappe.db.commit()
            log(f"  Cancelled SO: {o.name}")
        frappe.delete_doc("Sales Order", o.name, force=True, ignore_permissions=True)
        frappe.db.commit()
        log(f"  Deleted  SO: {o.name}")
    except Exception as e:
        log(f"  ERROR SO {o.name}: {e}")

# ── 2. Delete Sales Invoices ───────────────────────────────────────────────────
log("\n=== Deleting Sales Invoices ===")
invoices = frappe.db.get_all("Sales Invoice", fields=["name", "docstatus"])
for inv in invoices:
    try:
        if inv.docstatus == 1:
            doc = frappe.get_doc("Sales Invoice", inv.name)
            doc.cancel()
            frappe.db.commit()
        frappe.delete_doc("Sales Invoice", inv.name, force=True, ignore_permissions=True)
        frappe.db.commit()
        log(f"  Deleted SI: {inv.name}")
    except Exception as e:
        log(f"  ERROR SI {inv.name}: {e}")

# ── 3. Delete Payment Entries ──────────────────────────────────────────────────
log("\n=== Deleting Payment Entries ===")
payments = frappe.db.get_all("Payment Entry", fields=["name", "docstatus"])
for p in payments:
    try:
        if p.docstatus == 1:
            doc = frappe.get_doc("Payment Entry", p.name)
            doc.cancel()
            frappe.db.commit()
        frappe.delete_doc("Payment Entry", p.name, force=True, ignore_permissions=True)
        frappe.db.commit()
        log(f"  Deleted PE: {p.name}")
    except Exception as e:
        log(f"  ERROR PE {p.name}: {e}")

# ── 4. Delete Customers ────────────────────────────────────────────────────────
log("\n=== Deleting Customers ===")
customers = frappe.db.get_all("Customer", fields=["name"])
deleted = 0
errors  = 0
for c in customers:
    if c.name in SKIP:
        log(f"  SKIP: {c.name}")
        continue
    try:
        frappe.delete_doc("Customer", c.name, force=True, ignore_permissions=True)
        frappe.db.commit()
        deleted += 1
    except Exception as e:
        log(f"  ERROR {c.name}: {e}")
        errors += 1

log(f"\nDone. Deleted={deleted}  Errors={errors}")
remaining = frappe.db.count("Customer")
log(f"Customers remaining: {remaining}")
