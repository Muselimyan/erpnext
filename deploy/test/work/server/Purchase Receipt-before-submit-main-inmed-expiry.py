# Name: Purchase Receipt-before-submit-main-inmed-expiry
# Type: DocType Event
# DocType: Purchase Receipt
# Event: Before Submit
# Disabled: 0
# ---

MAIN_WH = "Main - Inmed"

for row in (doc.items or []):
    if row.warehouse != MAIN_WH:
        frappe.throw(f"Receiving must be into {MAIN_WH}. Row warehouse is {row.warehouse or 'not set'}.")

    if not row.item_code:
        continue

    item = frappe.get_doc("Item", row.item_code)

    requires_expiry = bool(item.get("has_expiry_date"))
    has_batch = bool(item.get("has_batch_no"))

    if requires_expiry and has_batch:
        if not row.batch_no:
            frappe.throw(f"Row for item {row.item_code} requires Batch + Expiry. Batch No is missing.")

        batch = frappe.get_doc("Batch", row.batch_no)
        if not batch.expiry_date:
            frappe.throw(f"Batch {row.batch_no} must have Expiry Date for item {row.item_code}.")