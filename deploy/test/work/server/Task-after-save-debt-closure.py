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

APPROVED_USERS = [
    "ghahramanyann@gmail.com",
    "karapetyansev@gmail.com",
    "vahe.muselimyan@gmail.com",
    "levonaghinyan77@gmail.com",
]

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
        "task_kind": "Debt Closure Approval",
        "task_access_policy": "Debt Closure Approval",
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
    t.flags.ignore_permissions = True
    t.insert()
    assign_list = json.dumps(APPROVED_USERS[:2])
    frappe.db.set_value("Task", t.name, "_assign", assign_list, update_modified=False)
    for user in APPROVED_USERS[:2]:
        if not frappe.db.exists("ToDo", {"reference_type": "Task", "reference_name": t.name, "allocated_to": user, "status": "Open"}):
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = user
            todo.reference_type = "Task"
            todo.reference_name = t.name
            todo.description = t.subject
            todo.assigned_by = frappe.session.user
            todo.insert(ignore_permissions=True)

# ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ 2. Debt Closure Approval completed ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ calculate profit ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ¢ÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂÃÂ
if is_completing and doc.task_kind == "Debt Closure Approval":
    if frappe.session.user not in APPROVED_USERS and frappe.session.user != "Administrator":
        frappe.throw("Only Norayr, Sevak, or Levon can complete this approval task.")

    inv_name = doc.sales_invoice
    if inv_name:
        inv = frappe.get_doc("Sales Invoice", inv_name)
        total_profit = 0
        missing_prices = []
        for item in inv.items:
            selling = (item.rate or 0) * (item.qty or 0)
            buying_rate = frappe.db.get_value("Item Price", {"item_code": item.item_code, "price_list": "Standard Buying"}, "price_list_rate") or 0
            buying = buying_rate * (item.qty or 0)
            if buying_rate == 0:
                missing_prices.append(item.item_code)
            total_profit += selling - buying
        doc.custom_case_profit = total_profit
        if doc.dispatch_case:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "profit", total_profit)
        if missing_prices:
            frappe.msgprint(f"Warning: Standard Buying price missing for: {', '.join(missing_prices)}. Profit may be incomplete.", indicator="orange")