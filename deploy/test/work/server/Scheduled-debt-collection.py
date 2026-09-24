# Name: Scheduled-debt-collection
# Type: Scheduler Event
# DocType: 
# Event: 
# Disabled: 0
# ---

DEBT_ALERT_KIND = "Debt Alert"

def assign_single_owner(task_name, user):
    frappe.db.set_value("Task", task_name, "_assign", json.dumps([user]), update_modified=False)

    other_todos = frappe.get_all(
        "ToDo",
        filters={
            "reference_type": "Task",
            "reference_name": task_name,
            "allocated_to": ["!=", user],
            "status": "Open",
        },
        pluck="name",
    )

    for td in (other_todos or []):
        frappe.db.set_value("ToDo", td, "status", "Cancelled")

    if not frappe.db.exists(
        "ToDo",
        {
            "reference_type": "Task",
            "reference_name": task_name,
            "allocated_to": user,
            "status": "Open",
        },
    ):
        todo = frappe.new_doc("ToDo")
        todo.status = "Open"
        todo.allocated_to = user
        todo.reference_type = "Task"
        todo.reference_name = task_name
        todo.description = frappe.db.get_value("Task", task_name, "subject") or task_name
        todo.assigned_by = frappe.session.user
        todo.insert(ignore_permissions=True)

def get_net_receivable_amd(customer, company):
    # ── THE SINGLE DEFINITION OF DEBT (A7) ────────────────────────────────
    # KEEP IN SYNC WITH:
    #   Scheduled-debt-collection-episodes.py   (threshold test)
    #   task_debt_panel.py                      (net_receivable)
    #   RPT - Clients Exceeding Debt Threshold  (SQL)
    # RestrictedPython has no module system, so this formula is duplicated
    # rather than shared. A verification script asserts all four agree on the
    # same fixtures -- drift is caught by test, not by discipline.
    #
    #   net = unpaid submitted invoices - UNTAGGED unallocated credit
    #
    # Two deliberate choices.
    #
    # Invoice-based, not GL-based. This was sum(debit - credit) over GL Entry,
    # which sweeps in every customer-party ledger movement regardless of origin.
    # docs/implementation-questions.md specifies outstanding from submitted
    # Sales Invoices, and it is what the collector's own panel displays.
    #
    # ONLY UNTAGGED CREDIT OFFSETS. A Payment Entry carrying a dispatch_case is
    # earmarked for that case, and task_commit_invoice already refuses to spend
    # it on any other -- so counting it as an offset here contradicts a rule the
    # system enforces elsewhere, and it under-reports risk: a client sitting on
    # a large advance for next month's surgery would appear to owe nothing on
    # this month's unpaid invoice.
    rows = frappe.db.sql(
        """
        select
            coalesce((
                select sum(outstanding_amount) from `tabSales Invoice`
                where docstatus = 1 and outstanding_amount > 0
                  and customer = %(cust)s and company = %(co)s
            ), 0)
          - coalesce((
                select sum(unallocated_amount) from `tabPayment Entry`
                where docstatus = 1 and payment_type = 'Receive'
                  and party_type = 'Customer' and party = %(cust)s
                  and company = %(co)s and unallocated_amount > 0
                  and (dispatch_case is null or dispatch_case = '')
            ), 0)
        """,
        {"cust": customer, "co": company},
    )
    return float(rows[0][0] or 0)

company = frappe.db.get_single_value("Global Defaults", "default_company")
if not company:
    companies = frappe.get_all("Company", pluck="name")
    company = companies[0] if companies else None

debt_alert_assignee = ""
if company:
    policy = frappe.get_doc("Task Access Policy", DEBT_ALERT_KIND)
    debt_alert_assignee = policy.default_team_user or ""

    customers = frappe.get_all(
        "Customer",
        filters={"disabled": 0},
        fields=["name", "customer_name", "debt_threshold_amd"],
    )

if company and debt_alert_assignee:
    for c in customers:
        threshold = float(c.debt_threshold_amd or 0)
        if threshold <= 0:
            continue

        debt = get_net_receivable_amd(c.name, company)

        if debt <= threshold:
            continue

        existing = frappe.get_all(
            "Task",
            filters={
                "task_kind": DEBT_ALERT_KIND,
                "customer": c.name,
                "status": ["!=", "Completed"],
            },
            pluck="name",
        )

        description = f"Client debt exceeded threshold. Current debt: {debt}. Threshold: {threshold}."
        if existing:
            task_name = existing[0]
            frappe.db.set_value("Task", task_name, "current_debt_amd", debt)
            frappe.db.set_value("Task", task_name, "debt_threshold_amd", threshold)
            frappe.db.set_value("Task", task_name, "description", description)
            assign_single_owner(task_name, debt_alert_assignee)
        else:
            task = frappe.new_doc("Task")
            task.subject = f"Debt Alert - {c.customer_name}"
            task.status = "Open"
            task.task_kind = DEBT_ALERT_KIND
            task.task_access_policy = DEBT_ALERT_KIND
            task.customer = c.name
            task.current_debt_amd = debt
            task.debt_threshold_amd = threshold
            task.description = description
            task.insert(ignore_permissions=True)
            assign_single_owner(task.name, debt_alert_assignee)