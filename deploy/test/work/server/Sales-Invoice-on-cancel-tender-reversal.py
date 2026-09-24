# Name: Sales-Invoice-on-cancel-tender-reversal
# Type: DocType Event
# DocType: Sales Invoice
# Event: After Cancel
# Disabled: 0
# ---

# NOTHING IN HERE MAY THROW.
#
# This runs on After Cancel, where an exception rolls back the cancellation
# itself. A missing tender, or a tender item row someone deleted, used to throw
# -- which made the INVOICE permanently uncancellable because of a data problem
# in a different document. The user is then stuck with an invoice they cannot
# cancel and cannot correct, and nothing in the message explains that the
# blockage is in the Tender Agreement.
#
# Failing to give quantity back is a smaller problem than failing to cancel:
# the tender shows more supplied than it should, which a human can correct on
# the tender itself. So every unreversible row is logged and skipped, and the
# cancellation proceeds.
if doc.docstatus == 2:
    unreversed = []
    for fulfillment in (doc.get("tender_fulfillments") or []):
        tender_name = fulfillment.tender_agreement
        item_code = fulfillment.item_code
        qty = fulfillment.quantity or 0

        if not tender_name or not item_code or qty <= 0:
            continue

        # The tender itself may have been deleted. get_doc would raise
        # DoesNotExistError before the loop even starts.
        if not frappe.db.exists("Tender Agreement", tender_name):
            unreversed.append(f"{item_code} x{qty}: Tender Agreement {tender_name} no longer exists")
            continue

        tender = frappe.get_doc("Tender Agreement", tender_name)
        matched = False
        for tender_item in tender.items:
            if tender_item.item_code == item_code:
                supplied = tender_item.supplied_quantity or 0
                new_supplied = supplied - qty
                if new_supplied < 0:
                    new_supplied = 0
                tender_item.supplied_quantity = new_supplied
                tender_item.remaining_quantity = (tender_item.won_quantity or 0) - tender_item.supplied_quantity
                matched = True
                break

        if not matched:
            unreversed.append(f"{item_code} x{qty}: no matching row in Tender Agreement {tender_name}")
            continue

        tender.flags.ignore_permissions = True
        tender.save()

    if unreversed:
        # Logged loudly, and left on the invoice so the trail survives the
        # session. The cancellation is NOT blocked.
        warning = ("Invoice cancelled, but tender quantity could not be returned for: "
                   + "; ".join(unreversed)
                   + ". Correct supplied_quantity on the tender by hand.")
        print(f"[Tender] {frappe.utils.now()} invoice={doc.name} UNREVERSED {warning}")
        frappe.log_error(warning, "Tender reversal incomplete on cancel")
