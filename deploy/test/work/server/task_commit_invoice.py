# Name: task_commit_invoice
# Type: API
# DocType: 
# Event: 
# Disabled: 0
# ---

# ═══════════════════════════════════════════════════════════════════════
# Creates AND submits the Sales Invoice for a Dispatch Case, in one action, from
# the Invoice Preparation task.
#
# WHY THERE IS NO LONGER A DRAFT
# ------------------------------
# A draft invoice used to be created automatically the moment goods were
# delivered or returns were inspected, and Accounting was expected to find it,
# check it and submit it by hand. Two failure modes followed from that:
#
#   - If no line qualified (the client returned everything unused, which is a
#     routine outcome), create_invoice() returned without creating anything --
#     but the Invoice Preparation task was created regardless, and its gate
#     demands a submitted invoice. The result was a task no user, not even an
#     Administrator, could ever clear.
#   - The draft could drift from the case, and a cancelled-then-amended invoice
#     left the case pointing at the cancelled document.
#
# Nothing is created until the accountant commits. The task shows a preview; the
# commit builds, values and submits the invoice in a single step. If there is
# nothing to bill, task_close_case_nothing_to_invoice records that explicitly
# instead of leaving a task behind that cannot be finished.
#
# Prices are NOT computed here. They were resolved server-side when the items
# were added (tender -> customer price -> Standard Selling), which is what stops
# the tender validator refusing the invoice at submission.
#
# Log tag: [Invoice]
# ═══════════════════════════════════════════════════════════════════════

TAX_TEMPLATE = "Armenia Tax - Inmed"
PAYMENT_TERMS = "Net 30"

task_name = frappe.form_dict.get("task_name")
if not task_name:
    frappe.throw("Task is required.")

task = frappe.get_doc("Task", task_name)

if (task.get("custom_accepted_by") or "") != frappe.session.user:
    frappe.throw("You must accept this task before creating the invoice.")
if (task.get("task_kind") or "") != "Invoice preparation / create invoice":
    frappe.throw("The invoice can only be created from an Invoice preparation task.")
if not task.get("dispatch_case"):
    frappe.throw("This task has no Dispatch Case.")

case = frappe.get_doc("Dispatch Case", task.dispatch_case)

# ── Idempotency ───────────────────────────────────────────────────────
# Keyed on Sales Invoice.dispatch_case rather than Dispatch Case.sales_invoice,
# so an amended invoice (which carries the same dispatch_case) is found too.
existing = frappe.get_all(
    "Sales Invoice",
    filters={"dispatch_case": case.name, "docstatus": ["!=", 2]},
    fields=["name", "docstatus"],
    limit_page_length=0,
)
if existing:
    frappe.throw("Dispatch Case " + case.name + " already has invoice " + existing[0].name + ". Cancel it first if it needs replacing.")

# ── Lines: what was actually consumed ─────────────────────────────────
# used_qty is computed on every case save as dispatched - returned - lost, so on
# the no-return path it equals the dispatched quantity, and on the return path it
# is what the client kept. Lost/damaged is deliberately not billed; it needs a
# human decision (Group 11 G12).
items_rows = []
unpriced = []
for r in (case.case_items or []):
    qty = float(r.used_qty or 0)
    if qty <= 0:
        continue
    rate = float(r.unit_price or 0) * (1 - float(r.discount_pct or 0) / 100)
    if rate <= 0:
        unpriced.append(r.item_code or "Unknown")
        continue
    items_rows.append({"item_code": r.item_code, "qty": qty, "rate": rate})

if unpriced:
    frappe.throw("These products have no price and cannot be invoiced: " + ", ".join(unpriced)
                 + ". Set an Item Price on the Standard Selling price list, then re-add them to the order.")

if not items_rows:
    frappe.throw("There is nothing to invoice on this case: no item has a used quantity above zero. "
                 + "If the client returned everything unused, use 'Nothing to Invoice' to close the case instead.")

# ── Clinical metadata, from the Customer ──────────────────────────────
# Never populated before, so every dispatch invoice was flagged by
# RPT - Data Quality - Missing Doctor or Hospital, and doctor-level sales
# analysis was impossible.
cust = frappe.get_doc("Customer", case.customer)
inv_hospital = ""
inv_doctor = cust.get("doctor_name") or ""
if (cust.get("client_kind") or "") == "Hospital":
    inv_hospital = cust.name
else:
    inv_hospital = cust.get("hospital") or ""

# ── Build ─────────────────────────────────────────────────────────────
si_doc = {
    "doctype": "Sales Invoice",
    "customer": case.customer,
    "company": "InMED",
    "currency": "AMD",
    "update_stock": 0,
    "dispatch_case": case.name,
    "items": items_rows,
}
if inv_hospital:
    si_doc["hospital"] = inv_hospital
if inv_doctor:
    si_doc["doctor_name"] = inv_doctor
if frappe.db.exists("Sales Taxes and Charges Template", TAX_TEMPLATE):
    si_doc["taxes_and_charges"] = TAX_TEMPLATE
if frappe.db.exists("Payment Terms Template", PAYMENT_TERMS):
    si_doc["payment_terms_template"] = PAYMENT_TERMS

si = frappe.get_doc(si_doc)
si.flags.ignore_permissions = True
si.insert()

# ── Apply the VAT template rows ───────────────────────────────────────
# Setting taxes_and_charges alone does not populate the tax rows; the template
# has to be expanded. Without this the invoice submits at net total, which is
# how 36 of 36 invoices on test ended up with zero VAT.
if si_doc.get("taxes_and_charges") and not si.taxes:
    for t in (frappe.get_all("Sales Taxes and Charges",
                             filters={"parent": TAX_TEMPLATE, "parenttype": "Sales Taxes and Charges Template"},
                             fields=["charge_type", "account_head", "rate", "description", "cost_center", "included_in_print_rate"],
                             order_by="idx asc", limit_page_length=0) or []):
        si.append("taxes", {
            "charge_type": t.charge_type,
            "account_head": t.account_head,
            "rate": t.rate,
            "description": t.description,
            "cost_center": t.cost_center,
            "included_in_print_rate": t.included_in_print_rate,
        })
    si.flags.ignore_permissions = True
    si.save()

# ── Consume any unallocated customer credit ───────────────────────────
# An advance is the same transaction arriving early, so it is applied here
# rather than tracked as a separate prepaid figure on the case. Allocation is a
# ledger operation, which is why the order the money and the invoice arrive in
# no longer matters.
advance_applied = 0
try:
    si.set_advances()
    for adv in (si.advances or []):
        advance_applied += float(adv.allocated_amount or 0)
    if advance_applied > 0:
        si.flags.ignore_permissions = True
        si.save()
except Exception as e:
    print(f"[Invoice] {frappe.utils.now()} case={case.name} advance allocation skipped: {str(e)[:120]}")
    advance_applied = 0

si.flags.ignore_permissions = True
si.submit()

# Convenience pointer for the form and existing reports. Logic reads
# Sales Invoice.dispatch_case, never this field, so it cannot become a source of
# truth that drifts.
frappe.db.set_value("Dispatch Case", case.name, "sales_invoice", si.name)

print(f"[Invoice] {frappe.utils.now()} case={case.name} invoice={si.name} net={si.net_total} tax={si.total_taxes_and_charges} total={si.grand_total} advances={advance_applied} outstanding={si.outstanding_amount}")

frappe.response["message"] = {
    "ok": True,
    "sales_invoice": si.name,
    "net_total": si.net_total,
    "total_taxes_and_charges": si.total_taxes_and_charges,
    "grand_total": si.grand_total,
    "advance_applied": advance_applied,
    "outstanding_amount": si.outstanding_amount,
    "due_date": str(si.due_date or ""),
}
