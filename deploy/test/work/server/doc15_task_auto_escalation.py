# Name: doc15_task_auto_escalation
# Type: Scheduler Event
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

from frappe.utils import today, add_days, getdate

open_statuses = ["Open", "Working", "Pending Review", "Overdue"]
director_role = "Ops - Directors"
normal_cutoff = add_days(today(), -3)
high_cutoff = add_days(today(), -1)

users = frappe.get_all("Has Role", filters={"role": director_role, "parenttype": "User"}, pluck="parent")
directors = []
for user in users:
    enabled = frappe.db.get_value("User", user, "enabled")
    if enabled:
        directors.append(user)

if directors:
    tasks = frappe.get_all(
        "Task",
        filters={"status": ["in", open_statuses], "exp_end_date": ["is", "set"]},
        fields=["name", "subject", "priority", "exp_end_date", "owner"]
    )
    escalated = []
    for task in tasks:
        due_date = getdate(task.exp_end_date)
        high_priority = task.priority in ["High", "Urgent"]
        should_escalate = False
        if high_priority and due_date <= getdate(high_cutoff):
            should_escalate = True
        elif due_date <= getdate(normal_cutoff):
            should_escalate = True
        if not should_escalate:
            continue
        already_assigned = frappe.get_all(
            "ToDo",
            filters={"reference_type": "Task", "reference_name": task.name, "allocated_to": ["in", directors], "status": "Open"},
            limit=1
        )
        if already_assigned:
            continue
        for director in directors:
            frappe.get_doc({
                "doctype": "ToDo",
                "allocated_to": director,
                "reference_type": "Task",
                "reference_name": task.name,
                "description": "Auto-escalated overdue task: {0}".format(task.subject or task.name),
                "priority": "High" if high_priority else "Medium",
                "status": "Open"
            }).insert(ignore_permissions=True)
        if task.owner:
            frappe.get_doc({
                "doctype": "ToDo",
                "allocated_to": task.owner,
                "reference_type": "Task",
                "reference_name": task.name,
                "description": "This overdue task was auto-escalated to directors.",
                "priority": "High" if high_priority else "Medium",
                "status": "Open"
            }).insert(ignore_permissions=True)
        escalated.append(task.name)
    if escalated:
        frappe.db.commit()