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
        # Business intent, recorded on the transaction itself: which case the
        # money was paid for, and which task recorded it. Previously this
        # context lived only in a Dispatch Case child table, so the Payment
        # Entry -- the authoritative document -- had no idea why it existed.
        "dispatch_case": doc.dispatch_case or "",
        "source_task": doc.name,
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

    # NOTHING is written back to the Dispatch Case.
    #
    # This used to append a row to DC.advance_payments, re-sum it into
    # DC.prepaid_amount and stamp DC.prepaid_payment_entry. All three were
    # copies of a fact the Payment Entry already stated, and they were the
    # wrong shape for it:
    #
    #   - prepaid_amount was subtracted from the invoice total ONCE, at Invoice
    #     Preparation completion. An advance recorded after that moment changed
    #     prepaid_amount but nothing recomputed outstanding, so the case showed
    #     a balance the ledger disagreed with.
    #   - prepaid_payment_entry held a single link, so on the second advance for
    #     a case it silently pointed at only the latest one.
    #   - Task.available_advance_credit was incremented here and never read,
    #     decremented, or used in allocation by any code. Write-only.
    #
    # An advance is not a special kind of object -- it is a payment that
    # arrived before its invoice. Left unallocated on a submitted Payment
    # Entry it is exactly ERPNext's model for customer credit: real GL, real
    # credit, allocated by task_commit_invoice when the invoice is raised.
    # That is why the order the money and the invoice arrive in stopped
    # mattering.
    print(f"[Advance] {frappe.utils.now()} task={doc.name} customer={doc.customer} amount={doc.new_payment_amount} pe={pe.name} case={doc.dispatch_case or '-'} submitted, unallocated")