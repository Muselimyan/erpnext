# Name: Task-after-save-account-details-processing
# Type: DocType Event
# DocType: Task
# Event: After Save
# Disabled: 0
# ---

if doc.get("task_kind") == "Account Details: Entry":
    before = doc.get_doc_before_save()
    before_status = None
    if before:
        before_status = before.status

    if doc.status == "Completed" and before_status != "Completed":
        existing = frappe.db.exists("Task", {"custom_account_details_entry_task": doc.name})
        if not existing:
            assignee = doc.get("custom_next_task_assign_to")
            if assignee and (not doc.get("custom_assigned_to") or assignee == doc.get("custom_assigned_to")):
                assignee = None
            if not assignee:
                assignee = "accounting.team@example.com"

            new_task = frappe.new_doc("Task")
            entry_subject = doc.get("custom_account_details_subject")
            if entry_subject:
                new_task.subject = entry_subject
                new_task.custom_account_details_subject = entry_subject
            else:
                new_task.subject = "Account Details: Processing"
            new_task.task_kind = "Account Details: Processing"
            new_task.task_access_policy = "Account Details: Processing"
            new_task.status = "Open"
            new_task.description = doc.description
            new_task.priority = doc.priority
            new_task.customer = doc.customer
            new_task.exp_start_date = doc.exp_start_date
            new_task.exp_end_date = doc.exp_end_date
            new_task.expected_time = doc.expected_time
            new_task.custom_assigned_to = assignee
            new_task.custom_account_details_entry_task = doc.name

            if doc.get("custom_account_photos"):
                for row in doc.get("custom_account_photos"):
                    new_task.append("custom_account_photos", row.as_dict())

            new_task.flags.ignore_permissions = True
            new_task.insert()

            frappe.db.set_value("Task", new_task.name, "_assign", json.dumps([assignee]))
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = assignee
            todo.reference_type = "Task"
            todo.reference_name = new_task.name
            todo.description = new_task.subject or new_task.name
            todo.assigned_by = frappe.session.user
            todo.flags.ignore_permissions = True
            todo.insert()

            files = frappe.get_all("File", filters={"attached_to_doctype": "Task", "attached_to_name": doc.name}, fields=["file_url", "file_name", "is_private", "attached_to_field", "folder"])
            for f in files:
                if not f.file_url:
                    continue
                duplicate = frappe.db.exists("File", {
                    "attached_to_doctype": "Task",
                    "attached_to_name": new_task.name,
                    "file_url": f.file_url
                })
                if duplicate:
                    continue
                nf = frappe.new_doc("File")
                nf.file_url = f.file_url
                nf.file_name = f.file_name
                nf.is_private = f.is_private
                nf.folder = f.folder or "Home/Attachments"
                nf.attached_to_doctype = "Task"
                nf.attached_to_name = new_task.name
                nf.attached_to_field = f.attached_to_field
                nf.flags.ignore_permissions = True
                nf.insert()
