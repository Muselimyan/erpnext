# Name: Task-before-save-payment-recording
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

# ═══════════════════════════════════════════════════════════════════════
# Records a customer payment entered on a Debt Collection task.
#
# WHAT CHANGED IN W2
# ------------------
# Allocation used to walk the task's own `open_invoices` child table, then
# write back `paid_amount` / `outstanding_amount` / `total_outstanding` and
# append a `payment_history` row. That made the task a second copy of the
# receivables ledger, and the copy drifted.
#
# It now reads the live Sales Invoice outstanding amounts and writes NOTHING
# back to the task. The ledger is the only record of what is owed and what has
# been paid; the task is just the place a person types the three inputs.
#
# Consequences that fall out of this for free:
#   - the figures can no longer go stale
#   - an advance recorded after the invoice is handled identically to one
#     recorded before it, because allocation is a ledger operation rather than
#     a subtraction performed once at a fixed moment
#   - completing the task no longer needs to be inferred from a stored balance
#
# FIFO order is preserved: oldest posting date first, invoice name as the
# tie-breaker.
#
# Log tag: [Pay]
# ═══════════════════════════════════════════════════════════════════════

if doc.task_kind != "Debt Collection":
    pass
elif not (doc.new_payment_amount or 0) > 0:
    pass
else:
    before = doc.get_doc_before_save()
    before_amt = (before.new_payment_amount if before else None) or 0
    if doc.new_payment_amount == before_amt:
        pass
    elif not doc.customer:
        frappe.throw("This Debt Collection task has no Customer, so a payment cannot be recorded against it.")
    else:
        amount = float(doc.new_payment_amount or 0)
        method = doc.payment_method_dc or "Cash"
        paid_to_account = "Cash - Inmed"
        if method in ("Bank Transfer", "Card"):
            paid_to_account = "Bank - Inmed"
        ref = doc.payment_reference_dc or ""

        # Live receivables for this customer, oldest first.
        open_invoices = frappe.get_all(
            "Sales Invoice",
            filters={"customer": doc.customer, "docstatus": 1, "outstanding_amount": [">", 0]},
            fields=["name", "posting_date", "outstanding_amount"],
            order_by="posting_date asc, name asc",
            limit_page_length=0,
        )

        if not open_invoices:
            frappe.throw("There are no submitted unpaid invoices for " + str(doc.customer) + ", so this payment has nothing to settle. Record it as an advance on a Payment Received task instead.")

        total_outstanding = 0
        for inv in open_invoices:
            total_outstanding += float(inv.outstanding_amount or 0)

        if amount > total_outstanding:
            frappe.throw("Payment of " + str(amount) + " exceeds the total outstanding of " + str(total_outstanding) + " for " + str(doc.customer) + ". Reduce the amount, or record the excess as an advance on a Payment Received task.")

        allocations = []
        remaining = amount
        for inv in open_invoices:
            if remaining <= 0:
                continue
            available = float(inv.outstanding_amount or 0)
            to_apply = remaining
            if available < to_apply:
                to_apply = available
            if to_apply > 0:
                allocations.append({"sales_invoice": inv.name, "allocated_amount": to_apply})
                remaining = remaining - to_apply

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
            "paid_to": paid_to_account,
        })
        for allocation in allocations:
            pe.append("references", {
                "reference_doctype": "Sales Invoice",
                "reference_name": allocation.get("sales_invoice"),
                "allocated_amount": allocation.get("allocated_amount"),
            })
        pe.flags.ignore_permissions = True
        pe.insert()
        pe.submit()

        print(f"[Pay] {frappe.utils.now()} task={doc.name} customer={doc.customer} amount={amount} pe={pe.name} allocations={len(allocations)}")

        # Clear the input buffer. Nothing else is written back: the payment now
        # lives only on the Payment Entry and in the ledger.
        doc.new_payment_amount = 0
        doc.payment_method_dc = ""
        doc.payment_reference_dc = ""

        # Submitting the Payment Entry updates the referenced invoices, so the
        # question "is this customer square with us?" is answered by re-reading
        # the ledger rather than by a stored running total.
        still_open = frappe.get_all(
            "Sales Invoice",
            filters={"customer": doc.customer, "docstatus": 1, "outstanding_amount": [">", 0]},
            fields=["name"],
            limit_page_length=1,
        )
        if not still_open:
            print(f"[Pay] {frappe.utils.now()} task={doc.name} customer={doc.customer} fully settled, completing task")
            doc.status = "Completed"
