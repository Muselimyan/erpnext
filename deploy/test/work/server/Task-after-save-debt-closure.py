# Name: Task-after-save-debt-closure
# Type: DocType Event
# DocType: Task
# Event: After Save
# Disabled: 1
# ---
# RETIRED. Superseded by Payment Entry-after-submit-debt-closure-check.
# This script should remain disabled.
#
# It had two halves and both were wrong in the same way: they treated the
# completion of a person's WORK as a statement about the customer's ACCOUNT.
#
# Half one raised a Debt Closure Approval when a Debt Collection task was
# completed. Completing a chase attempt says nothing about whether the customer
# paid -- two episodes on test were closed still carrying real outstanding
# balances, and an approval was raised anyway, asserting a closure that had not
# happened. Settlement is a ledger event, so the ledger now raises it: when a
# submitted Payment Entry leaves the customer with no unpaid invoice.
#
# Half two recomputed profit every time an approval was completed, by summing
# EVERY submitted Sales Invoice for the customer. Nothing stopped a second
# approval being raised for the same customer, and each one counted the same
# invoices again (Group 11 G10). Profit is now computed once, when the approval
# is created, over exactly the Dispatch Cases that settlement closed -- and a
# case reaches Closed only once, which makes that set idempotent by
# construction. Approving then means approving a figure rather than
# regenerating it.
#
# Its role check on completion is also redundant: dispatch_task_accept
# validates the accepter against the Task Access Policy, and
# Task-before-save-access-control reserves completion to the accepter, so only
# a policy-allowed user can ever complete the task.
#
# Both halves also read the Task child tables open_invoices and payment_history,
# which W2 deleted.

before = doc.get_doc_before_save()
before_status = before.status if before else None
is_completing = (doc.status == "Completed" and before_status != "Completed")

if is_completing:
    print(f"[Closure] {frappe.utils.now()} RETIRED SCRIPT reached for task={doc.name}; this should not happen while disabled=1")
