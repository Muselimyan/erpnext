# Name: Task-after-save-advance-payment
# Type: DocType Event
# DocType: Task
# Event: After Save
# Disabled: 0
# ---

before = doc.get_doc_before_save()
before_status = before.status if before else None
is_completing = (doc.status == "Completed" and before_status != "Completed")
if not (is_completing and doc.task_kind == "Payment Received"):
    pass
elif not (doc.new_payment_amount or 0) > 0:
    pass
else:
    pe = frappe.get_doc({
        "doctype": "Payment Entry",
        "payment_type": "Receive",
        "party_type": "Customer",
        "party": doc.customer,
        "paid_amount": doc.new_payment_amount,
        "received_amount": doc.new_payment_amount,
        "mode_of_payment": doc.payment_method_dc or "Cash",
        "reference_no": doc.payment_reference_dc or "",
        "reference_date": today(),
        "company": "InMED",
        "paid_to": "Cash - Inmed",
    })
    pe.flags.ignore_permissions = True
    pe.insert()
    if doc.dispatch_case:
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"prepaid_amount": doc.new_payment_amount, "prepaid_payment_entry": pe.name})
    existing_dc = frappe.db.get_value("Task", {"customer": doc.customer, "task_kind": "Debt Collection", "status": ["not in", ["Completed", "Cancelled"]]}, "name")
    if existing_dc:
        current_credit = frappe.db.get_value("Task", existing_dc, "available_advance_credit") or 0
        frappe.db.set_value("Task", existing_dc, "available_advance_credit", current_credit + doc.new_payment_amount)