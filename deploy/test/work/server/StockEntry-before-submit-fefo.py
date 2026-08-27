# Name: StockEntry-before-submit-fefo
# Type: DocType Event
# DocType: Stock Entry
# Event: Before Submit
# Disabled: 1
# ---

import frappe
from frappe.utils import today, add_months, getdate

def get_earliest_expiry_batch(item_code, warehouse):
    row = frappe.db.sql(
        """
        SELECT sle.batch_no, b.expiry_date
        FROM `tabStock Ledger Entry` sle
        INNER JOIN `tabBatch` b ON b.name = sle.batch_no
        WHERE sle.item_code = %s
          AND sle.warehouse = %s
          AND sle.is_cancelled = 0
          AND sle.batch_no IS NOT NULL
          AND b.expiry_date IS NOT NULL
        GROUP BY sle.batch_no, b.expiry_date
        HAVING SUM(sle.actual_qty) > 0
        ORDER BY b.expiry_date ASC
        LIMIT 1
        """,
        (item_code, warehouse),
        as_dict=True,
    )
    return row[0] if row else None

cutoff_date = getdate(add_months(today(), 1))

for d in doc.items:
    if not d.item_code or not d.s_warehouse or not d.batch_no:
        continue

    selected_expiry = frappe.db.get_value("Batch", d.batch_no, "expiry_date")
    if not selected_expiry:
        continue

    selected_expiry = getdate(selected_expiry)

    earliest = get_earliest_expiry_batch(d.item_code, d.s_warehouse)
    earliest_expiry = getdate(earliest.get("expiry_date")) if earliest and earliest.get("expiry_date") else None
    if earliest_expiry and selected_expiry > earliest_expiry:
        frappe.msgprint(
            f"FEFO warning: You selected batch '{d.batch_no}' (expiry {selected_expiry}) but an older-expiring batch '{earliest['batch_no']}' (expiry {earliest['expiry_date']}) is available in '{d.s_warehouse}'.",
            indicator="orange",
        )

    if selected_expiry <= cutoff_date:
        frappe.msgprint(
            f"Near-expiry warning: Batch '{d.batch_no}' expires on {selected_expiry} (<= 1 month).",
            indicator="orange",
        )