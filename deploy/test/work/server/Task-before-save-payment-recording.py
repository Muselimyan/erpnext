# Name: Task-before-save-payment-recording
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

if doc.task_kind != "Debt Collection":
    pass
elif not (doc.new_payment_amount or 0) > 0:
    pass
else:
    before = doc.get_doc_before_save()
    before_amt = (before.new_payment_amount if before else None) or 0
    if doc.new_payment_amount == before_amt:
        pass
    else:
        amount = doc.new_payment_amount
        method = doc.payment_method_dc or "Cash"
        ref = doc.payment_reference_dc or ""
        remaining = amount
        invoice_dates = {}
        for row in doc.open_invoices:
            row.allocated_now = 0
            if (row.outstanding_amount or 0) > 0 and not row.sales_invoice:
                frappe.throw(f"Debt Collection row {row.idx} has outstanding amount but no Sales Invoice. Fix the Open Invoices table before recording payment.")
            if row.sales_invoice:
                invoice_dates[row.sales_invoice] = frappe.db.get_value("Sales Invoice", row.sales_invoice, "posting_date") or frappe.db.get_value("Sales Invoice", row.sales_invoice, "creation") or ""
        allocations = []
        for row in sorted(doc.open_invoices, key=lambda r: (str(invoice_dates.get(r.sales_invoice) or ""), r.sales_invoice or "")):
            to_apply = min(remaining, row.outstanding_amount or 0)
            if to_apply > 0:
                row.allocated_now = to_apply
                allocations.append({"sales_invoice": row.sales_invoice, "allocated_amount": to_apply})
                remaining -= to_apply
            if remaining <= 0:
                break
        for row in doc.open_invoices:
            apply = row.allocated_now or 0
            if apply > 0:
                row.paid_amount = (row.paid_amount or 0) + apply
                row.outstanding_amount = (row.outstanding_amount or 0) - apply
                row.allocated_now = 0
        doc.total_outstanding = sum((r.outstanding_amount or 0) for r in doc.open_invoices)
        doc.append("payment_history", {
            "payment_date": frappe.utils.now_datetime(),
            "amount": amount,
            "method": method,
            "reference": ref,
        })
        pe = frappe.get_doc({
            "doctype": "Payment Entry",
            "payment_type": "Receive",
            "party_type": "Customer",
            "party": doc.customer,
            "paid_amount": amount,
            "received_amount": amount,
            "mode_of_payment": method,
            "reference_no": ref,
            "reference_date": frappe.utils.nowdate(),
            "company": "InMED",
            "paid_to": "Cash - Inmed",
        })
        for allocation in allocations:
            if allocation.get("sales_invoice") and (allocation.get("allocated_amount") or 0) > 0:
                pe.append("references", {
                    "reference_doctype": "Sales Invoice",
                    "reference_name": allocation.get("sales_invoice"),
                    "allocated_amount": allocation.get("allocated_amount"),
                })
        pe.flags.ignore_permissions = True
        pe.insert()
        pe.submit()
        if doc.payment_history:
            frappe.db.set_value("Debt Collection Payment", doc.payment_history[-1].name, "payment_entry", pe.name)
        doc.new_payment_amount = 0
        doc.payment_method_dc = ""
        doc.payment_reference_dc = ""
        if doc.total_outstanding <= 0:
            doc.status = "Completed"