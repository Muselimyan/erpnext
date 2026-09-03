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
    method = doc.payment_method_dc or "Cash"
    paid_to_account = "Cash - Inmed"
    if method in ("Bank Transfer", "Card"):
        paid_to_account = "Bank - Inmed"

    pe = frappe.get_doc({
        "doctype": "Payment Entry",
        "payment_type": "Receive",
        "party_type": "Customer",
        "party": doc.customer,
        "paid_amount": doc.new_payment_amount,
        "received_amount": doc.new_payment_amount,
        "mode_of_payment": method,
        "reference_no": doc.payment_reference_dc or "",
        "reference_date": today(),
        "company": "InMED",
        "paid_to": paid_to_account,
    })
    pe.flags.ignore_permissions = True
    pe.insert()
    if doc.dispatch_case:
        case = frappe.get_doc("Dispatch Case", doc.dispatch_case)
        case.append("advance_payments", {
            "payment_date": frappe.utils.now_datetime(),
            "amount": doc.new_payment_amount,
            "method": method,
            "reference": doc.payment_reference_dc or "",
            "payment_entry": pe.name,
            "source_task": doc.name,
        })
        case.prepaid_amount = sum((row.amount or 0) for row in case.advance_payments)
        case.prepaid_payment_entry = pe.name
        case.flags.ignore_permissions = True
        case.save()
    existing_dc = frappe.db.get_value("Task", {"customer": doc.customer, "task_kind": "Debt Collection", "status": ["not in", ["Completed", "Cancelled"]]}, "name")
    if existing_dc:
        current_credit = frappe.db.get_value("Task", existing_dc, "available_advance_credit") or 0
        frappe.db.set_value("Task", existing_dc, "available_advance_credit", current_credit + doc.new_payment_amount)