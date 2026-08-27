# Name: Delivery Note-before-submit-delivery-gate
# Type: DocType Event
# DocType: Delivery Note
# Event: Before Submit
# Disabled: 0
# ---

DELIVERY_IN_TRANSIT_WH = "Delivery In-Transit - Inmed"

for row in (doc.items or []):
    if row.warehouse != DELIVERY_IN_TRANSIT_WH:
        frappe.throw(
            f"Standard sales Delivery Note must issue from {DELIVERY_IN_TRANSIT_WH}. "
            f"Row warehouse is {row.warehouse or 'not set'}."
        )

sales_orders = sorted(list(set([r.against_sales_order for r in (doc.items or []) if r.against_sales_order])))
for so_name in sales_orders:
    so = frappe.get_doc("Sales Order", so_name)

    if so.discount_approval_status in ("Pending", "Rejected"):
        frappe.throw("Discount approval is required before delivery.")

    if so.is_prepaid:
        if not so.prepayment_payment_entry:
            frappe.throw("Prepaid order requires Prepayment Payment Entry before delivery.")

        pe = frappe.get_doc("Payment Entry", so.prepayment_payment_entry)
        if pe.docstatus != 1:
            frappe.throw("Prepayment Payment Entry must be submitted before delivery.")