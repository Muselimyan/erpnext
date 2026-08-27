# Name: Purchase Order-before-save-clear-approval
# Type: DocType Event
# DocType: Purchase Order
# Event: Before Save
# Disabled: 0
# ---

before = doc.get_doc_before_save()

if before and doc.docstatus == 0:
    was_approved = (before.director_approval_status == "Approved")

    if was_approved:
        header_changed = (
            (doc.supplier != before.supplier)
            or (doc.currency != before.currency)
            or (doc.transaction_date != before.transaction_date)
            or (doc.purchase_reason != before.purchase_reason)
            or (doc.requested_by != before.requested_by)
        )

        def normalize_rows(rows):
            out = []
            for r in (rows or []):
                out.append({
                    "item_code": r.item_code,
                    "uom": r.uom,
                    "conversion_factor": r.conversion_factor,
                    "qty": float(r.qty or 0),
                    "rate": float(r.rate or 0),
                    "schedule_date": str(r.schedule_date or ""),
                })
            return out

        rows_changed = (normalize_rows(doc.items) != normalize_rows(before.items))

        if header_changed or rows_changed:
            doc.director_approval_status = "Pending"
            doc.director_approved_by = None
            doc.director_approved_at = None
            doc.director_approval_task = None
            doc.director_approval_note = None

            frappe.msgprint("PO was edited after director approval. Approval was cleared and must be re-done.")