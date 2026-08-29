# Name: Task-after-save-other-processing
# Type: DocType Event
# DocType: Task
# Event: After Save
# Disabled: 0
# ---

if doc.get("task_kind") == "Other: Entry" and doc.get("status") == "Completed":
    if not frappe.db.exists("Task", {"task_kind": "Other: Processing", "subject": "Other: Processing", "depends_on_tasks": ["like", "%" + doc.name + "%"]}):
        print(f"[OtherFlow] {frappe.utils.now()} task={doc.name} Other: Entry completed, creating Processing task")
        new_task = frappe.new_doc("Task")
        new_task.subject = "Other: Processing"
        new_task.task_kind = "Other: Processing"
        new_task.status = "Open"
        new_task.priority = doc.get("priority") or "Medium"
        if doc.get("project"):
            new_task.project = doc.project
        if doc.get("customer"):
            new_task.customer = doc.customer
        if doc.get("description"):
            new_task.description = doc.description
        if doc.get("custom_next_task_assign_to"):
            new_task.custom_assigned_to = doc.custom_next_task_assign_to
        new_task.append("depends_on", {"task": doc.name})
        new_task.flags.ignore_permissions = True
        new_task.insert()
        print(f"[OtherFlow] {frappe.utils.now()} task={doc.name} created Processing task={new_task.name} assigned_to={new_task.custom_assigned_to}")
        files = frappe.get_all("File", filters={"attached_to_doctype": "Task", "attached_to_name": doc.name}, fields=["file_url", "file_name", "is_private", "attached_to_field", "folder"])
        for f in files:
            if not f.file_url:
                continue
            if frappe.db.exists("File", {"attached_to_doctype": "Task", "attached_to_name": new_task.name, "file_url": f.file_url}):
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
