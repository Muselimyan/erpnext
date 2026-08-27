# Name: Task-before-save-dispatch-gates
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

# Mandatory: task must be accepted before any save/change/complete
if doc.task_kind and doc.status != "Template" and doc.status != "Cancelled":
    accept_gate_before = doc.get_doc_before_save()
    accept_gate_is_new = not accept_gate_before
    if not accept_gate_is_new and not doc.custom_accepted_by:
        frappe.throw("You must Accept this task before making any changes or completing it.")

# Sync customer from Task to Dispatch Case
if doc.dispatch_case and doc.customer:
    dc_customer = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "customer")
    if not dc_customer:
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, "customer", doc.customer)
# Global: cannot complete a task unless you are assigned to it
before = doc.get_doc_before_save()
before_status = before.status if before else None
is_completing_global = (doc.status == "Completed" and before_status != "Completed")
if is_completing_global:
    # Block completion if assignment is being changed in the same save
    old_assigned_user = before.custom_assigned_to if before else None
    old_assigned_team = before.custom_team_queue_role if before else None
    if (doc.custom_assigned_to or "") != (old_assigned_user or "") or (doc.custom_team_queue_role or "") != (old_assigned_team or ""):
        frappe.throw("You cannot reassign and complete a task at the same time. Save the reassignment first.")
    accepted_by = doc.custom_accepted_by or frappe.db.get_value("Task", doc.name, "custom_accepted_by")
    if not accepted_by and frappe.session.user != "Administrator":
        frappe.throw("You must accept this task before completing it. Click Accept / Start Task first.")
    if accepted_by and accepted_by != frappe.session.user and frappe.session.user != "Administrator":
        frappe.throw("Only the user who accepted this task (" + accepted_by + ") can complete it.")

# Order entry completion: require submitted Dispatch Case
before = doc.get_doc_before_save()
before_status = before.status if before else None
is_completing_early = (doc.status == "Completed" and before_status != "Completed")
if is_completing_early and doc.task_kind == "Order entry":
    if not doc.dispatch_case:
        frappe.throw("Link a Dispatch Case before completing the Order entry task.")
    dc_docstatus = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "docstatus")
    if dc_docstatus != 1:
        dc_doc = frappe.get_doc("Dispatch Case", doc.dispatch_case)
        if not dc_doc.items or len(dc_doc.items) == 0:
            frappe.throw("Add at least one product to the Dispatch Case before completing.")
        dc_doc.submit()

if not doc.dispatch_case:
    pass
else:
    # Update dispatch_case_status field for display
    if doc.dispatch_case:
        dc_status = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "status")
        if dc_status:
            doc.dispatch_case_status = dc_status
    before = doc.get_doc_before_save()
    before_status = before.status if before else None
    before_ds = (before.delivery_status if before else None) or "Todo"
    before_ps = (before.pickup_status if before else None) or "Todo"
    is_completing = (doc.status == "Completed" and before_status != "Completed")
    ds_changing = (doc.task_kind == "Delivery" and doc.delivery_status != before_ds)
    ps_changing = (doc.task_kind == "Pickup Returns" and doc.pickup_status != before_ps)

    # Pack task: require pickup photo before completing
    if is_completing and doc.task_kind == "Pack / prepare items":
        has_photo = doc.warehouse_pickup_photo or frappe.db.exists("File", {"attached_to_doctype": "Task", "attached_to_name": doc.name, "attached_to_field": "warehouse_pickup_photo"})
        if not has_photo:
            frappe.throw("Warehouse Pickup Photo is required before completing the Pack / prepare items task.")

    # Delivery: must go through Picked Up before Delivered
    if ds_changing and doc.delivery_status == "Delivered" and before_ds != "Picked Up":
        frappe.throw("Delivery status must be changed to 'Picked Up' and saved before it can be marked as 'Delivered'.")

    # Delivery: can't complete unless delivery_status is Delivered
    if is_completing and doc.task_kind == "Delivery" and doc.delivery_status != "Delivered":
        frappe.throw("Delivery task cannot be completed until delivery status is 'Delivered'.")

    # Auto-complete Delivery task when marked Delivered
    if ds_changing and doc.delivery_status == "Delivered":
        doc.status = "Completed"

    # Pickup Returns: must go through Picked Up before Returned to Warehouse
    if ps_changing and doc.pickup_status == "Returned to Warehouse" and before_ps != "Picked Up":
        frappe.throw("Pickup status must be changed to 'Picked Up' and saved before it can be marked as 'Returned to Warehouse'.")

    # Pickup Returns: can't complete unless pickup_status is Returned to Warehouse
    if is_completing and doc.task_kind == "Pickup Returns" and doc.pickup_status != "Returned to Warehouse":
        frappe.throw("Pickup Returns task cannot be completed until pickup status is 'Returned to Warehouse'.")

    # Auto-complete Return Pickup task when Returned to Warehouse
    if ps_changing and doc.pickup_status == "Returned to Warehouse":
        has_dropoff = doc.warehouse_dropoff_photo or frappe.db.exists("File", {"attached_to_doctype": "Task", "attached_to_name": doc.name, "attached_to_field": "warehouse_dropoff_photo"})
        if not has_dropoff:
            frappe.throw("Drop-off Photo (Warehouse Drop-off Photo) is required before marking Returned to Warehouse.")
        doc.status = "Completed"

    # Pack completion: all items must be checked as packed
    if doc.status == "Completed" and doc.task_kind == "Pack / prepare items":
        case = frappe.get_doc("Dispatch Case", doc.dispatch_case)
        not_packed = []
        for row in (case.case_items or []):
            status = row.custom_packing_status or 'Pending'
            if status not in ('Complete', 'Over Scanned'):
                not_packed.append(row.item_code or row.item_name or 'Unknown')
        if not_packed:
            frappe.throw('All items must be packed before completing this task. Not packed: ' + ', '.join(not_packed))

    # Returns Inspection completion: require returned_qty
    if is_completing and doc.task_kind == "Returns processing / verification":
        case = frappe.get_doc("Dispatch Case", doc.dispatch_case)
        for row in (case.case_items or []):
            if row.returned_qty is None:
                frappe.throw("Fill returned_qty for ALL items in Dispatch Case before completing.")

    # Invoice Preparation completion: require submitted invoice
    if is_completing and doc.task_kind == "Invoice preparation / create invoice":
        inv = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "sales_invoice")
        if not inv:
            frappe.throw("No Sales Invoice linked to this Dispatch Case yet.")
        if frappe.db.get_value("Sales Invoice", inv, "docstatus") != 1:
            frappe.throw("Submit the Sales Invoice before completing this task.")

    # Discount Approval completion: require approval_outcome
    if is_completing and doc.task_kind == "Discount Approval":
        if not doc.approval_outcome:
            frappe.throw("Set Approval Outcome (Approved or Rejected) before completing.")

    # Debt Closure Approval: only Norayr, Sevak, or Levon can complete
    if is_completing and doc.task_kind == "Debt Closure Approval":
        APPROVED_USERS = ["ghahramanyann@gmail.com", "karapetyansev@gmail.com", "vahe.muselimyan@gmail.com", "levonaghinyan77@gmail.com"]
        if frappe.session.user not in APPROVED_USERS and frappe.session.user != "Administrator":
            frappe.throw("Only Norayr, Sevak, or Levon can approve and complete this task.")