# Name: Sales-Invoice-on-cancel-tender-reversal
# Type: DocType Event
# DocType: Sales Invoice
# Event: On Cancel
# Disabled: 0
# ---

if doc.docstatus == 2:
    for fulfillment in (doc.get("tender_fulfillments") or []):
        tender_name = fulfillment.tender_agreement
        item_code = fulfillment.item_code
        qty = fulfillment.quantity or 0

        if not tender_name or not item_code or qty <= 0:
            continue

        tender = frappe.get_doc("Tender Agreement", tender_name)
        matched = False
        for tender_item in tender.items:
            if tender_item.item_code == item_code:
                supplied = tender_item.supplied_quantity or 0
                tender_item.supplied_quantity = max(supplied - qty, 0)
                tender_item.remaining_quantity = (tender_item.won_quantity or 0) - tender_item.supplied_quantity
                matched = True
                break

        if not matched:
            frappe.throw(
                f"Cannot reverse tender fulfillment for invoice {doc.name}: item {item_code} was not found in Tender Agreement {tender_name}."
            )

        tender.flags.ignore_permissions = True
        tender.save()
