# Name: Task-before-save-auto-subject
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

if not doc.subject:
    result = frappe.db.sql("SELECT MAX(CAST(subject AS UNSIGNED)) FROM `tabTask` WHERE subject REGEXP '^[0-9]+$' AND LENGTH(subject) = 5", as_list=True)
    max_num = (result[0][0] or 0) if result else 0
    doc.subject = str(int(max_num) + 1).zfill(5)