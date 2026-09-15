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
        "reference_date": frappe.utils.today(),
        "company": "InMED",
        "paid_to": paid_to_account,
    })
    pe.flags.ignore_permissions = True
    pe.insert()
    # SUBMIT the Payment Entry. It was previously left in Draft, which produces
    # no GL entries at all -- so the ledger never saw the money, while
    # DC.prepaid_amount was still written and still subtracted from the
    # invoice. The workflow was granting credit for cash the books had no
    # record of. On test this left customer D143 with a GL net receivable of
    # -4,486,950 while the workflow believed the case was owed 1,560,000, and
    # it fed that figure to the hourly Debt Alert scheduler.
    # An unallocated submitted Receive entry is exactly ERPNext's model for a
    # customer advance: real GL, real credit, allocated when an invoice exists.
    pe.submit()
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
        total_prepaid = 0
        for row in case.advance_payments:
            total_prepaid += row.amount or 0
        case.prepaid_amount = total_prepaid
        case.prepaid_payment_entry = pe.name
        case.flags.ignore_permissions = True
        case.flags.ignore_validate_update_after_submit = True
        case.save()
    # The running total that used to be pushed onto the Debt Collection task's
    # `available_advance_credit` field is gone. That field was write-only --
    # incremented here and never read, decremented or used in allocation by any
    # code. Unallocated customer credit is now read live from submitted Payment
    # Entries by the task_debt_panel API, so there is nothing to push.
    print(f"[Advance] {frappe.utils.now()} task={doc.name} customer={doc.customer} amount={doc.new_payment_amount} pe={pe.name} submitted")