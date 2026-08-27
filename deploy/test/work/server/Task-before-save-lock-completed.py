# Name: Task-before-save-lock-completed
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

before = doc.get_doc_before_save()
if before and before.status == 'Completed':
    frappe.throw('This task is already completed and cannot be modified.')