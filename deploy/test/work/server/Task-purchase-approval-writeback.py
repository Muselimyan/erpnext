# Name: Task-purchase-approval-writeback
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

before = doc.get_doc_before_save()
before_status = before.status if before else None

is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")

if is_becoming_completed and doc.task_kind == "Purchase Approval":
    if not doc.purchase_order:
        frappe.throw("Purchase Approval task must be linked to a Purchase Order.")

    if doc.approval_outcome not in ("Approved", "Rejected"):
        frappe.throw("Approval Outcome must be set to Approved or Rejected before completing the task.")

    po = frappe.get_doc("Purchase Order", doc.purchase_order)

    po.director_approval_status = doc.approval_outcome
    po.director_approved_by = doc.modified_by or doc.owner
    po.director_approved_at = frappe.utils.now_datetime()
    po.director_approval_task = doc.name
    po.director_approval_note = doc.approval_note

    po.save(ignore_permissions=True)