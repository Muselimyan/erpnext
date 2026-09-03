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
    rows = frappe.db.sql(
        """
        select coalesce(sum(debit - credit), 0)
        from `tabGL Entry`
        where is_cancelled = 0
          and company = %s
          and party_type = 'Customer'
          and party = %s
        """,
        (company, customer),
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

        if existing:
            task = frappe.get_doc("Task", existing[0])
        else:
            task = frappe.new_doc("Task")
            task.subject = f"Debt Alert - {c.customer_name}"
            task.status = "Open"
            task.task_kind = DEBT_ALERT_KIND
            task.task_access_policy = DEBT_ALERT_KIND
            task.customer = c.name
            task.insert(ignore_permissions=True)
            assign_single_owner(task.name, debt_alert_assignee)

        task.current_debt_amd = debt
        task.debt_threshold_amd = threshold
        task.description = f"Client debt exceeded threshold. Current debt: {debt}. Threshold: {threshold}."
        task.save(ignore_permissions=True)