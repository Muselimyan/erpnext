# Name: Sales-Invoice-after-submit-tender-update
# Type: DocType Event
# DocType: Sales Invoice
# Event: After Submit
# Disabled: 0
# ---

if doc.docstatus == 1:
    hospital = doc.customer
    active_tenders = frappe.get_all(
        "Tender Agreement",
        filters={"hospital": hospital, "status": "Active"},
        fields=["name", "valid_from", "valid_to"],
        order_by="valid_to asc, valid_from asc, name asc",
    )

    if active_tenders:
        tender_docs = [frappe.get_doc("Tender Agreement", tender.name) for tender in active_tenders]

        for inv_item in doc.items:
            item_code = inv_item.item_code
            qty = inv_item.qty or 0
            if not item_code or qty <= 0:
                continue

            matches = []
            for tender in tender_docs:
                for tender_item in tender.items:
                    if tender_item.item_code == item_code:
                        matches.append({"tender": tender, "item": tender_item})

            if len(matches) > 1:
                tender_names = ", ".join(match["tender"].name for match in matches)
                frappe.throw(
                    f"Multiple active Tender Agreements found for hospital {hospital} and item {item_code}: {tender_names}. "
                    "Only one active tender per hospital/item is allowed. Close or expire the duplicate tender before submitting this invoice."
                )

            if len(matches) == 1:
                match = matches[0]
                tender = match["tender"]
                tender_item = match["item"]
                remaining = (tender_item.won_quantity or 0) - (tender_item.supplied_quantity or 0)

                if qty > remaining:
                    frappe.throw(
                        f"Tender {tender.name} has only {remaining} remaining for item {item_code}, but this invoice has quantity {qty}. "
                        "Review with Accounting/Director before changing the invoice or tender quantity."
                    )

                tender_item.supplied_quantity = (tender_item.supplied_quantity or 0) + qty
                tender_item.remaining_quantity = (tender_item.won_quantity or 0) - tender_item.supplied_quantity
                tender.flags.ignore_permissions = True
                tender.save()
