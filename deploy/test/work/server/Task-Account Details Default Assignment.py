# Name: Task-Account Details Default Assignment
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

if doc.get("task_kind") == "Account details":
    if not doc.get("subject"):
        doc.subject = "Account details"
    assignee = doc.get("custom_assigned_to") or "accounting.team@example.com"
    doc.custom_assigned_to = assignee
    doc.set("_assign", '["' + assignee + '"]')

    if not doc.is_new():
        exists = frappe.db.exists("ToDo", {
            "reference_type": "Task",
            "reference_name": doc.name,
            "allocated_to": assignee,
            "status": "Open"
        })
        if not exists:
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = assignee
            todo.reference_type = "Task"
            todo.reference_name = doc.name
            todo.description = doc.subject or doc.name
            todo.assigned_by = frappe.session.user
            todo.flags.ignore_permissions = True
            todo.insert()