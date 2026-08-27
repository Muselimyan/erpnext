# Name: Sales-Invoice-after-submit-tender-update
# Type: DocType Event
# DocType: Sales Invoice
# Event: After Submit
# Disabled: 0
# ---

if doc.docstatus == 1:
    hospital = doc.customer
    tenders = frappe.get_all("Tender Agreement", 
        filters={"hospital": hospital, "status": "Active"},
        fields=["name"])
    if tenders:
        for inv_item in doc.items:
            item_code = inv_item.item_code
            qty = inv_item.qty or 0
            for tender_doc_name in [t.name for t in tenders]:
                tender = frappe.get_doc("Tender Agreement", tender_doc_name)
                for tender_item in tender.items:
                    if tender_item.item_code == item_code:
                        tender_item.supplied_quantity = (tender_item.supplied_quantity or 0) + qty
                        tender_item.remaining_quantity = (tender_item.won_quantity or 0) - tender_item.supplied_quantity
                tender.flags.ignore_permissions = True
                tender.save()
                frappe.db.commit()