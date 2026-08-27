# Name: Task-after-insert-assign
# Type: DocType Event
# DocType: Task
# Event: After Insert
# Disabled: 1
# ---

# Assign task to user from custom_assign_to field
if doc.custom_assign_to:
    try:
        from frappe.desk.form.assign_to import add
        add({
            "doctype": doc.doctype,
            "name": doc.name,
            "assign_to": [doc.custom_assign_to]
        })
    except Exception as e:
        # Log error but don't block task creation
        frappe.log_error(f"Failed to auto-assign task {doc.name} to {doc.custom_assign_to}: {str(e)}")