# Name: task_debt_panel
# Type: API
# DocType: 
# Event: 
# Disabled: 0
# ---

# ═══════════════════════════════════════════════════════════════════════
# Live customer debt, computed from the ledger. Stores nothing.
#
# Replaces the `open_invoices`, `payment_history`, `total_outstanding` and
# `available_advance_credit` fields that used to be kept on the Debt Collection
# task. Those were a hand-maintained second copy of the receivables ledger and
# they drifted: on test, Dispatch Cases showed an outstanding balance of
# millions against invoices the ledger reported as fully paid, and two debt
# tasks were closed while still carrying real outstanding amounts.
#
# A Task is a unit of work. What a customer owes is a fact about the business,
# not about the work, so it belongs in the ledger and is read from there.
#
# Returns, for the task's customer:
#   invoices   - submitted Sales Invoices with a non-zero outstanding
#   advances   - submitted Payment Entries with unallocated credit
#   payments   - submitted customer receipts, newest first
#   totals     - outstanding, unallocated credit, and the net figure
#
# Log tag: [DebtPanel]
# ═══════════════════════════════════════════════════════════════════════

task_name = frappe.form_dict.get("task_name")
customer = frappe.form_dict.get("customer")

if not task_name and not customer:
    frappe.throw("Task or Customer is required.")

if task_name and not customer:
    customer = frappe.db.get_value("Task", task_name, "customer")

if not customer:
    frappe.response["message"] = {
        "ok": True,
        "customer": None,
        "invoices": [],
        "advances": [],
        "payments": [],
        "totals": {"outstanding": 0, "unallocated_credit": 0, "net_receivable": 0},
        "note": "This task has no customer, so there is nothing to show.",
    }
    raise SystemExit

today = frappe.utils.nowdate()

# ── Unpaid submitted invoices ─────────────────────────────────────────
invoice_rows = frappe.get_all(
    "Sales Invoice",
    filters={"customer": customer, "docstatus": 1, "outstanding_amount": [">", 0]},
    fields=["name", "posting_date", "due_date", "currency", "grand_total",
            "outstanding_amount", "status"],
    order_by="posting_date asc, name asc",
    limit_page_length=0,
)

invoices = []
total_outstanding = 0
for inv in (invoice_rows or []):
    outstanding = float(inv.outstanding_amount or 0)
    total_outstanding += outstanding
    age = 0
    overdue = 0
    if inv.posting_date:
        age = frappe.utils.date_diff(today, inv.posting_date)
    if inv.due_date:
        overdue = frappe.utils.date_diff(today, inv.due_date)
    invoices.append({
        "sales_invoice": inv.name,
        "posting_date": str(inv.posting_date or ""),
        "due_date": str(inv.due_date or ""),
        "currency": inv.currency,
        "grand_total": float(inv.grand_total or 0),
        "paid_amount": float(inv.grand_total or 0) - outstanding,
        "outstanding_amount": outstanding,
        "status": inv.status,
        "age_days": age,
        "days_overdue": overdue if overdue > 0 else 0,
    })

# ── Unallocated advances (customer credit) ────────────────────────────
advance_rows = frappe.get_all(
    "Payment Entry",
    filters={"party_type": "Customer", "party": customer, "docstatus": 1,
             "payment_type": "Receive", "unallocated_amount": [">", 0]},
    fields=["name", "posting_date", "paid_amount", "unallocated_amount",
            "mode_of_payment", "reference_no", "dispatch_case", "source_task"],
    order_by="posting_date asc, name asc",
    limit_page_length=0,
)

advances = []
total_credit = 0
# Credit split by intent. KEEP IN SYNC WITH the shared definition in
# Scheduled-debt-collection.py -- only UNTAGGED credit reduces what the client
# owes, because task_commit_invoice will not spend case-tagged credit on any
# other case. Showing a single blended figure made an earmarked advance look
# like it had settled an unrelated invoice.
available_credit = 0
earmarked_credit = 0
for pe in (advance_rows or []):
    unallocated = float(pe.unallocated_amount or 0)
    total_credit += unallocated
    if pe.dispatch_case:
        earmarked_credit += unallocated
    else:
        available_credit += unallocated
    advances.append({
        "payment_entry": pe.name,
        "posting_date": str(pe.posting_date or ""),
        "paid_amount": float(pe.paid_amount or 0),
        "unallocated_amount": unallocated,
        "method": pe.mode_of_payment,
        "reference": pe.reference_no,
        # Business intent, read from the transaction rather than from a
        # Dispatch Case child table copy.
        "dispatch_case": pe.dispatch_case or "",
        "source_task": pe.source_task or "",
    })

# ── Payment history, from the ledger rather than a stored table ───────
payment_rows = frappe.get_all(
    "Payment Entry",
    filters={"party_type": "Customer", "party": customer, "docstatus": 1,
             "payment_type": "Receive"},
    fields=["name", "posting_date", "paid_amount", "unallocated_amount",
            "mode_of_payment", "reference_no", "owner"],
    order_by="posting_date desc, creation desc",
    limit_page_length=50,
)

# Allocations for ALL payments in one query, then bucketed, rather than one
# query per payment row. This panel renders on every Debt Collection and Debt
# Closure Approval task open, and the old shape cost up to 51 queries (1 + 50)
# for a screen that shows at most 50 rows.
alloc_by_parent = {}
pe_names = [pe.name for pe in (payment_rows or [])]
if pe_names:
    for a in (frappe.get_all(
        "Payment Entry Reference",
        filters={"parent": ["in", pe_names], "reference_doctype": "Sales Invoice"},
        fields=["parent", "reference_name", "allocated_amount"],
        limit_page_length=0,
    ) or []):
        # Read-modify-write: RestrictedPython forbids augmented assignment to a
        # subscript, so `alloc_by_parent[k] += [...]` is a compile error here.
        bucket = alloc_by_parent.get(a.parent) or []
        bucket.append({"sales_invoice": a.reference_name,
                       "allocated_amount": float(a.allocated_amount or 0)})
        alloc_by_parent[a.parent] = bucket

payments = []
for pe in (payment_rows or []):
    against = alloc_by_parent.get(pe.name) or []
    payments.append({
        "payment_entry": pe.name,
        "posting_date": str(pe.posting_date or ""),
        "amount": float(pe.paid_amount or 0),
        "method": pe.mode_of_payment,
        "reference": pe.reference_no,
        "recorded_by": pe.owner,
        "unallocated_amount": float(pe.unallocated_amount or 0),
        "against": against,
    })

print(f"[DebtPanel] {frappe.utils.now()} customer={customer} invoices={len(invoices)} outstanding={total_outstanding} credit={total_credit} available={available_credit} earmarked={earmarked_credit}")

frappe.response["message"] = {
    "ok": True,
    "customer": customer,
    "invoices": invoices,
    "advances": advances,
    "payments": payments,
    "totals": {
        "outstanding": total_outstanding,
        # Total credit held, kept so the figure on screen still matches the sum
        # of the advances table below it.
        "unallocated_credit": total_credit,
        # The part that can actually be set against these invoices.
        "available_credit": available_credit,
        # Held for a specific case, and not available to this one.
        "earmarked_credit": earmarked_credit,
        "net_receivable": total_outstanding - available_credit,
    },
}
