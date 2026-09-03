# Name: Task-after-save-debt-closure
# Type: DocType Event
# DocType: Task
# Event: After Save
# Disabled: 0
# ---

# Debt Closure Approval: creation and profit calculation

before = doc.get_doc_before_save()
before_status = before.status if before else None
is_completing = (doc.status == "Completed" and before_status != "Completed")

DEBT_CLOSURE_APPROVAL_KIND = "Debt Closure Approval"

# ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ 1. Debt Collection completed ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ create Debt Closure Approval ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ
if is_completing and doc.task_kind == "Debt Collection":
    total_paid = sum((r.paid_amount or 0) for r in (doc.open_invoices or []))
    inv_names = [r.sales_invoice for r in (doc.open_invoices or []) if r.sales_invoice]
    pe_names = [r.payment_entry for r in (doc.payment_history or []) if r.payment_entry]
    desc_lines = [
        f"Customer: {doc.customer}",
        f"Total Paid: {total_paid} AMD",
        f"Invoices: {', '.join(inv_names) if inv_names else 'N/A'}",
        f"Payment Entries: {', '.join(pe_names) if pe_names else 'N/A'}",
        "",
        "Payment History:",
    ]
    for ph in (doc.payment_history or []):
        desc_lines.append(f"  {ph.payment_date} | {ph.amount} AMD | {ph.method or ''} | Ref: {ph.reference or ''} | PE: {ph.payment_entry or ''}")

    t = frappe.get_doc({
        "doctype": "Task",
        "subject": f"Debt Closure Approval: {doc.customer}",
        "task_kind": DEBT_CLOSURE_APPROVAL_KIND,
        "task_access_policy": DEBT_CLOSURE_APPROVAL_KIND,
        "customer": doc.customer,
        "dispatch_case": (doc.open_invoices[0].dispatch_case if doc.open_invoices and doc.open_invoices[0].dispatch_case else ""),
        "sales_invoice": doc.sales_invoice or (inv_names[0] if inv_names else ""),
        "payment_entry": pe_names[0] if pe_names else "",
        "custom_total_amount_paid": total_paid,
        "description": "\n".join(desc_lines),
    })
    for ph in (doc.payment_history or []):
        t.append("payment_history", {
            "payment_date": ph.payment_date,
            "amount": ph.amount,
            "method": ph.method,
            "reference": ph.reference,
            "payment_entry": ph.payment_entry,
        })
    for oi in (doc.open_invoices or []):
        t.append("open_invoices", {
            "dispatch_case": oi.dispatch_case,
            "sales_invoice": oi.sales_invoice,
            "invoice_amount": oi.invoice_amount,
            "paid_amount": oi.paid_amount,
            "outstanding_amount": oi.outstanding_amount,
        })
    approval_policy = frappe.get_doc("Task Access Policy", DEBT_CLOSURE_APPROVAL_KIND)
    approval_assignee = approval_policy.default_team_user or ""
    if not approval_assignee:
        frappe.throw("Debt Closure Approval Task Access Policy must have a default team user.")

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

# ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ 2. Debt Closure Approval completed ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ calculate profit ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ
if is_completing and doc.task_kind == DEBT_CLOSURE_APPROVAL_KIND:
    approval_policy = frappe.get_doc("Task Access Policy", DEBT_CLOSURE_APPROVAL_KIND)
    allowed_roles = [r.role for r in (approval_policy.allowed_roles or []) if r.role]
    user_roles = frappe.get_all("Has Role", filters={"parent": frappe.session.user}, pluck="role")
    if frappe.session.user != "Administrator" and not set(allowed_roles).intersection(set(user_roles or [])):
        frappe.throw("Only users allowed by the Debt Closure Approval Task Access Policy can complete this approval task.")

    invoice_rows = []
    seen_invoices = set()
    for row in (doc.open_invoices or []):
        if row.sales_invoice and row.sales_invoice not in seen_invoices:
            invoice_rows.append({"sales_invoice": row.sales_invoice, "dispatch_case": row.dispatch_case})
            seen_invoices.add(row.sales_invoice)
    if not invoice_rows and doc.sales_invoice:
        invoice_rows.append({"sales_invoice": doc.sales_invoice, "dispatch_case": doc.dispatch_case})

    total_profit = 0
    missing_prices = []
    dispatch_case_profit = {}

    for row in invoice_rows:
        inv = frappe.get_doc("Sales Invoice", row.get("sales_invoice"))
        invoice_profit = 0
        for item in inv.items:
            selling = (item.rate or 0) * (item.qty or 0)
            buying_rate = frappe.db.get_value("Item Price", {"item_code": item.item_code, "price_list": "Standard Buying"}, "price_list_rate") or 0
            buying = buying_rate * (item.qty or 0)
            if buying_rate == 0:
                missing_prices.append(item.item_code)
            invoice_profit += selling - buying
        total_profit += invoice_profit
        if row.get("dispatch_case"):
            dispatch_case_profit[row.get("dispatch_case")] = (dispatch_case_profit.get(row.get("dispatch_case")) or 0) + invoice_profit

    doc.custom_case_profit = total_profit
    for dispatch_case, profit in dispatch_case_profit.items():
        frappe.db.set_value("Dispatch Case", dispatch_case, "profit", profit)
    if missing_prices:
        frappe.msgprint(f"Warning: Standard Buying price missing for: {', '.join(sorted(list(set(missing_prices))))}. Profit may be incomplete.", indicator="orange")