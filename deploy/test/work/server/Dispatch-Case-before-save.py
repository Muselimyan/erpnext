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
# Discount detection removed from here — now handled in Order Entry completion gate
# (Task-before-save-dispatch-gates.py) to avoid premature Discount Approval tasks
# during item-by-item entry via Product Work Area.