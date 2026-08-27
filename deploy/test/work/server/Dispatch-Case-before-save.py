# Name: Dispatch-Case-before-save
# Type: DocType Event
# DocType: Dispatch Case
# Event: Before Save
# Disabled: 0
# ---

for row in (doc.case_items or []):
    dispatched = row.dispatched_qty or 0
    returned = row.returned_qty or 0
    lost = row.lost_damaged_qty or 0
    row.used_qty = dispatched - returned - lost
    if row.used_qty < 0:
        frappe.throw(f"Row {row.idx}: used_qty cannot be negative (dispatched={dispatched}, returned={returned}, lost={lost}).")
if doc.status == "Draft":
    has_discount = any(float(row.discount_pct or 0) > 0 for row in (doc.case_items or []))
    if has_discount:
        doc.status = "Awaiting Approval"
        doc.discount_approval_status = "Pending"