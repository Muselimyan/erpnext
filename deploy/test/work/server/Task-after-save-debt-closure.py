# Name: Task-after-save-debt-closure
# Type: DocType Event
# DocType: Task
# Event: After Save
# Disabled: 0
# ---

# ═══════════════════════════════════════════════════════════════════════
# Debt Closure Approval: creation, and profit calculation on approval.
#
# WHAT CHANGED IN W2
# ------------------
# Both halves used to read the Debt Collection task's `open_invoices` and
# `payment_history` child tables. Those tables are gone: they were a second,
# hand-maintained copy of the receivables ledger. Invoices, payments and totals
# are now read from the ledger instead.
#
# The profit calculation is UNCHANGED in substance and is still based on
# `Item Price` / `Standard Buying`, which is the wrong basis -- Doc 17 makes the
# landed-cost valuation rate authoritative, and ERPNext already exposes it as
# `Sales Invoice Item.incoming_rate`. Replacing it is deliberately out of scope
# here; this change only rehomes where the invoice set comes from.
#
# Known remaining gap (Group 11 G10): nothing stops a second Debt Closure
# Approval being raised for the same customer, and each one recomputes profit.
# W5 moves creation to a ledger event with a dedup guard.
#
# Log tag: [Closure]
# ═══════════════════════════════════════════════════════════════════════

before = doc.get_doc_before_save()
before_status = before.status if before else None
is_completing = (doc.status == "Completed" and before_status != "Completed")

DEBT_CLOSURE_APPROVAL_KIND = "Debt Closure Approval"

# ── 1. Debt Collection completed -> raise a Debt Closure Approval ──────
if is_completing and doc.task_kind == "Debt Collection" and doc.customer:
    # Everything below is read from the ledger, not from the task.
    paid_rows = frappe.get_all(
        "Payment Entry",
        filters={"party_type": "Customer", "party": doc.customer, "docstatus": 1,
                 "payment_type": "Receive"},
        fields=["name", "posting_date", "paid_amount", "mode_of_payment", "reference_no"],
        order_by="posting_date asc, creation asc",
        limit_page_length=0,
    )
    settled_rows = frappe.get_all(
        "Sales Invoice",
        filters={"customer": doc.customer, "docstatus": 1},
        fields=["name", "grand_total", "outstanding_amount"],
        order_by="posting_date asc, name asc",
        limit_page_length=0,
    )

    total_paid = 0
    pe_names = []
    for p in (paid_rows or []):
        total_paid += float(p.paid_amount or 0)
        pe_names.append(p.name)

    inv_names = []
    for s in (settled_rows or []):
        inv_names.append(s.name)

    invoices_text = "N/A"
    if inv_names:
        invoices_text = ", ".join(inv_names)
    payment_entries_text = "N/A"
    if pe_names:
        payment_entries_text = ", ".join(pe_names)

    desc_lines = [
        f"Customer: {doc.customer}",
        f"Total Received (ledger): {total_paid} AMD",
        f"Invoices: {invoices_text}",
        f"Payment Entries: {payment_entries_text}",
        "",
        "Payment History (from submitted Payment Entries):",
    ]
    for p in (paid_rows or []):
        desc_lines.append(f"  {p.posting_date} | {p.paid_amount} AMD | {p.mode_of_payment or ''} | Ref: {p.reference_no or ''} | PE: {p.name}")

    approval_policy = frappe.get_doc("Task Access Policy", DEBT_CLOSURE_APPROVAL_KIND)
    approval_assignee = approval_policy.default_team_user or ""
    if not approval_assignee:
        frappe.throw("Debt Closure Approval Task Access Policy must have a default team user.")

    t = frappe.get_doc({
        "doctype": "Task",
        "subject": f"Debt Closure Approval: {doc.customer}",
        "task_kind": DEBT_CLOSURE_APPROVAL_KIND,
        "task_access_policy": DEBT_CLOSURE_APPROVAL_KIND,
        "customer": doc.customer,
        "dispatch_case": doc.dispatch_case or "",
        "sales_invoice": inv_names[0] if inv_names else "",
        "payment_entry": pe_names[0] if pe_names else "",
        "description": "\n".join(desc_lines),
    })
    t.flags.ignore_permissions = True
    t.insert()
    frappe.db.set_value("Task", t.name, "_assign", json.dumps([approval_assignee]), update_modified=False)
    if not frappe.db.exists("ToDo", {"reference_type": "Task", "reference_name": t.name, "allocated_to": approval_assignee, "status": "Open"}):
        todo = frappe.new_doc("ToDo")
        todo.status = "Open"
        todo.allocated_to = approval_assignee
        todo.reference_type = "Task"
        todo.reference_name = t.name
        todo.description = t.subject
        todo.assigned_by = frappe.session.user
        todo.insert(ignore_permissions=True)
    print(f"[Closure] {frappe.utils.now()} debt collection {doc.name} completed, raised approval {t.name} for {doc.customer}")

# ── 2. Debt Closure Approval completed -> calculate profit ─────────────
if is_completing and doc.task_kind == DEBT_CLOSURE_APPROVAL_KIND:
    approval_policy = frappe.get_doc("Task Access Policy", DEBT_CLOSURE_APPROVAL_KIND)
    allowed_roles = []
    for role_row in (approval_policy.allowed_roles or []):
        if role_row.role:
            allowed_roles.append(role_row.role)
    user_roles = frappe.get_all("Has Role", filters={"parent": frappe.session.user}, pluck="role")
    user_allowed = False
    for allowed_role in allowed_roles:
        for user_role in (user_roles or []):
            if allowed_role == user_role:
                user_allowed = True
    if frappe.session.user != "Administrator" and not user_allowed:
        frappe.throw("Only users allowed by the Debt Closure Approval Task Access Policy can complete this approval task.")

    # Invoice set comes from the customer's submitted invoices rather than a
    # stored child table.
    invoice_names = []
    if doc.customer:
        for s in (frappe.get_all("Sales Invoice",
                                 filters={"customer": doc.customer, "docstatus": 1},
                                 fields=["name"], limit_page_length=0) or []):
            invoice_names.append(s.name)
    if not invoice_names and doc.sales_invoice:
        invoice_names.append(doc.sales_invoice)

    total_profit = 0
    missing_prices = []

    for inv_name in invoice_names:
        inv = frappe.get_doc("Sales Invoice", inv_name)
        for item in inv.items:
            selling = (item.rate or 0) * (item.qty or 0)
            buying_rate = frappe.db.get_value("Item Price", {"item_code": item.item_code, "price_list": "Standard Buying"}, "price_list_rate") or 0
            buying = buying_rate * (item.qty or 0)
            if buying_rate == 0:
                missing_prices.append(item.item_code)
            total_profit += selling - buying

    frappe.db.set_value("Task", doc.name, "custom_case_profit", total_profit)
    print(f"[Closure] {frappe.utils.now()} approval {doc.name} customer={doc.customer} invoices={len(invoice_names)} profit={total_profit}")

    if missing_prices:
        unique_missing_prices = []
        for missing_price in missing_prices:
            if missing_price not in unique_missing_prices:
                unique_missing_prices.append(missing_price)
        frappe.msgprint(f"Warning: Standard Buying price missing for: {', '.join(sorted(unique_missing_prices))}. Profit may be incomplete.", indicator="orange")
