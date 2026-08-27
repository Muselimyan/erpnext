# Name: Task-before-save-return-dropoff-photo
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 1
# ---

before = doc.get_doc_before_save()
before_status = before.status if before else None

is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

if is_becoming_completed and doc.task_kind == "Return drop-off at warehouse":
    has_dropoff = doc.warehouse_dropoff_photo or frappe.db.exists("File", {"attached_to_doctype": "Task", "attached_to_name": doc.name, "attached_to_field": "warehouse_dropoff_photo"})
    if not has_dropoff:
        frappe.throw("Warehouse Drop-off Photo is required to complete this task.")

    if not doc.completed_at:
        doc.completed_at = now_datetime()