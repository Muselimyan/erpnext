# Name: Task-before-save-dispatch-gates
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

# ═══════════════════════════════════════════════════════════════════════
# DOMAIN gates for dispatch tasks: what must be true about the WORK before a
# task may progress (photo taken, items scanned, status stepped in order,
# invoice submitted, approval outcome chosen).
#
# This script does NOT enforce access control. Acceptance, ownership,
# task-kind role access and completed-task immutability are owned solely by
# Task-before-save-access-control.py. Previously this file also carried an
# acceptance gate (old lines 16-22) and a completion-ownership gate
# (old lines 39-54), which conflicted with the two other scripts implementing
# the same rules under different bypass semantics.
#
# STRUCTURE — why the split matters
# ---------------------------------
# This file used to wrap every kind gate in a single `if not doc.dispatch_case`
# guard. Any gate for a task kind WITHOUT a Dispatch Case was therefore dead
# code: the Debt Closure Approval role check never ran for approval tasks with
# no case, which on test is most of them. Gates are now separated by whether
# they actually need a case, so DC-less kinds can be gated too.
#
# Log tags: [Gates], [Photo]
# ═══════════════════════════════════════════════════════════════════════


def task_has_image(task_name):
    """Check if a Task has at least one attached image File record."""
    exts = (".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif")
    files = frappe.get_all("File", filters={"attached_to_doctype": "Task", "attached_to_name": task_name}, fields=["file_url"])
    images = [f.file_url for f in files if (f.file_url or "").lower().split("?")[0].endswith(exts)]
    print(f"[Photo] task_has_image({task_name}): total_files={len(files)}, images={len(images)}, urls={images[:5]}")
    return len(images) > 0


before = doc.get_doc_before_save()
before_status = before.status if before else None
before_ds = (before.delivery_status if before else None) or "Todo"
before_ps = (before.pickup_status if before else None) or "Todo"
is_completing = (doc.status == "Completed" and before_status != "Completed")

# ═══════════════════════════════════════════════════════════════════════
# SECTION A — gates that do NOT require a Dispatch Case
# ═══════════════════════════════════════════════════════════════════════

# Discount Approval completion: require approval_outcome
if is_completing and doc.task_kind == "Discount Approval":
    if not doc.approval_outcome:
        frappe.throw("Set Approval Outcome (Approved or Rejected) before completing.")

# NOTE: the former Debt Closure Approval role check lived here and was
# unreachable for tasks without a Dispatch Case. It is now redundant and has
# been removed: dispatch_task_accept validates the accepter against the Task
# Access Policy, and Task-before-save-access-control reserves completion to the
# accepter, so only a policy-allowed user can ever complete the task.
# Task-after-save-debt-closure.py retains its own equivalent check.

# ═══════════════════════════════════════════════════════════════════════
# SECTION B — gates that require a Dispatch Case
# ═══════════════════════════════════════════════════════════════════════

if not doc.dispatch_case:
    pass
else:
    # Order Entry: full field sync (all fields, even when cleared)
    if doc.task_kind == "Order entry":
        sync_fields = {
            "return_expected": doc.order_return_expected or 0,
            "client_location_warehouse": doc.order_client_location_warehouse or "",
            "surgery_date": doc.order_surgery_date or None,
        }
        if doc.customer:
            sync_fields["customer"] = doc.customer
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, sync_fields)
    # Other dispatch tasks: safety-net customer sync (only if DC customer is blank)
    elif doc.customer:
        dc_customer = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "customer")
        if not dc_customer:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "customer", doc.customer)

    # Update dispatch_case_status field for display
    dc_status = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "status")
    if dc_status:
        doc.dispatch_case_status = dc_status

    ds_changing = (doc.task_kind == "Delivery" and doc.delivery_status != before_ds)
    ps_changing = (doc.task_kind == "Pickup Returns" and doc.pickup_status != before_ps)

    # Order entry completion: validate items, sync fields, handle discounts, submit DC
    if is_completing and doc.task_kind == "Order entry":
        # Guard: if DC is already submitted (manual submit or retry), skip
        dc_docstatus = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "docstatus")
        if dc_docstatus == 1:
            print(f"[Gates] DC {doc.dispatch_case} already submitted, skipping completion gate")
        else:
            dc_doc = frappe.get_doc("Dispatch Case", doc.dispatch_case)
            if not dc_doc.case_items or len(dc_doc.case_items) == 0:
                frappe.throw("Add at least one product before completing.")
            if not doc.customer:
                frappe.throw("Select a Customer before completing the order.")
            if doc.order_return_expected and not doc.order_client_location_warehouse:
                frappe.throw("Client Location Warehouse is required when Return Expected is checked.")

            dc_doc.customer = doc.customer
            dc_doc.return_expected = doc.order_return_expected or 0
            dc_doc.client_location_warehouse = doc.order_client_location_warehouse or ""
            dc_doc.surgery_date = doc.order_surgery_date or None

            has_discount = any(float(row.discount_pct or 0) > 0 for row in dc_doc.case_items)

            if has_discount:
                dc_doc.status = "Awaiting Approval"
                dc_doc.discount_approval_status = "Pending"
                dc_doc.flags.ignore_permissions = True
                dc_doc.save()
                print(f"[Gates] DC {doc.dispatch_case} has discounts, set to Awaiting Approval")
            else:
                dc_doc.flags.ignore_permissions = True
                dc_doc.submit()
                print(f"[Gates] DC {doc.dispatch_case} submitted (no discounts)")

    # Pack task: require at least one image before completing
    if is_completing and doc.task_kind == "Pack / prepare items":
        has_photo = task_has_image(doc.name)
        print(f"[Photo] {frappe.utils.now()} task={doc.name} Pack completion gate: has_image={has_photo}, result={'PASS' if has_photo else 'BLOCKED'}")
        if not has_photo:
            frappe.throw("At least one photo is required before completing the Pack / prepare items task.")

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
        has_dropoff = task_has_image(doc.name)
        print(f"[Photo] {frappe.utils.now()} task={doc.name} Pickup Returns dropoff gate: has_image={has_dropoff}, result={'PASS' if has_dropoff else 'BLOCKED'}")
        if not has_dropoff:
            frappe.throw("At least one photo is required before marking Returned to Warehouse.")
        doc.status = "Completed"

    # Pack completion: all items must be fully scanned
    if doc.status == "Completed" and doc.task_kind == "Pack / prepare items":
        case = frappe.get_doc("Dispatch Case", doc.dispatch_case)
        not_packed = []
        for row in (case.case_items or []):
            if float(row.custom_scanned_qty or 0) < float(row.dispatched_qty or 0):
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
