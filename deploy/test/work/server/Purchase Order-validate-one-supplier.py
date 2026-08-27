# Name: Purchase Order-validate-one-supplier
# Type: DocType Event
# DocType: Purchase Order
# Event: Before Save
# Disabled: 1
# ---

if doc.supplier:
    for row in (doc.items or []):
        if not row.item_code:
            continue

        suppliers = frappe.get_all(
            "Item Supplier",
            filters={"parent": row.item_code, "parenttype": "Item"},
            pluck="supplier",
        )

        suppliers = [s for s in (suppliers or []) if s]

        if len(suppliers) != 1:
            frappe.throw(
                f"Item {row.item_code} must have exactly 1 Supplier (Doc 07 policy). Found: {', '.join(suppliers) or 'none'}."
            )

        if suppliers[0] != doc.supplier:
            frappe.throw(
                f"Item {row.item_code} supplier is {suppliers[0]} but PO supplier is {doc.supplier}. Do not mix suppliers on one PO."
            )