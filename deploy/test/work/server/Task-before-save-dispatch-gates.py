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

# Debt Collection completion: require an outcome, and a date if one was promised.
#
# This gate lives in Section A deliberately. A collection episode spans every
# unpaid invoice for a customer and so has NO Dispatch Case -- had it been put
# inside the `if doc.dispatch_case` block below it would have been dead code,
# exactly as the old Debt Closure Approval role check was.
#
# Completing an episode means "this attempt at collecting is finished", not
# "the customer has paid". There was previously no gate at all, so an episode
# could be closed silently with no record of what happened -- and two on test
# were closed while still carrying real outstanding balances. Requiring an
# outcome is what makes the next episode's timing meaningful, since
# Scheduled-debt-collection-episodes reads the follow-up date to decide when to
# raise the next one.
# Write-off Approval completion: require an outcome.
#
# Completing this task moves real stock and, on one branch, raises a real
# invoice. Without an outcome the after-save handler has nothing to act on and
# the units would stay in Lost & Damaged with the task closed -- the same
# stranded state this whole path exists to remove.
#
# Placed in Section A alongside the other outcome gates. These tasks do carry a
# Dispatch Case, so it would also work below, but the rule is about the task's
# own field and does not need the case.
#
# Read via .get() rather than attribute access: a Frappe Document raises
# AttributeError for an unknown fieldname, so if this script were ever deployed
# ahead of the custom field, every Write-off Approval save would break.
if is_completing and doc.task_kind == "Write-off Approval":
    if not doc.get("writeoff_outcome"):
        frappe.throw("Choose a Write-off Outcome -- Bill Client or Write Off -- before completing. "
                     "Completing this task moves the stock out of Lost & Damaged.")

if is_completing and doc.task_kind == "Debt Collection":
    if not doc.collection_outcome:
        frappe.throw("Record what happened (Collection Outcome) before completing this collection attempt.")
    if doc.collection_outcome == "Promised" and not doc.collection_follow_up_date:
        frappe.throw("The client promised to pay, so set a Follow-up Date. The next collection attempt is raised on that date.")
    if doc.collection_follow_up_date and frappe.utils.date_diff(doc.collection_follow_up_date, frappe.utils.nowdate()) < 0:
        frappe.throw("The Follow-up Date is in the past. Set a future date, or clear it to fall back to the standard follow-up interval.")

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

            # Every row must carry a resolved selling price. Without this the
            # flow happily produced near-zero invoices: 94% of submitted case
            # rows on test had unit_price = 0, because the price was whatever
            # the browser sent, pre-filled from Item.standard_rate which is
            # populated on no items at all.
            unpriced = []
            for row in dc_doc.case_items:
                if float(row.unit_price or 0) <= 0:
                    unpriced.append(row.item_code or row.item_name or "Unknown")
            if unpriced:
                frappe.throw("These products have no selling price: " + ", ".join(unpriced)
                             + ". Set an Item Price on the Standard Selling price list (or a Tender Agreement price for this hospital), then re-add them.")

            # Tender remaining-quantity check, applied HERE rather than at
            # invoice submission. Sales-Invoice-before-submit-tender-validation
            # refuses an invoice whose quantity exceeds the tender remainder,
            # and by then the order is packed and delivered and the Invoice
            # Preparation task can never be completed. Catching it at order
            # entry leaves the user somewhere they can still change the order.
            for t in (frappe.get_all("Tender Agreement",
                                     filters={"hospital": dc_doc.customer, "status": "Active"},
                                     fields=["name"], limit_page_length=0) or []):
                tender = frappe.get_doc("Tender Agreement", t.name)
                for ti in (tender.items or []):
                    ordered = 0
                    for row in dc_doc.case_items:
                        if row.item_code == ti.item_code:
                            ordered += float(row.dispatched_qty or 0)
                    if ordered > 0:
                        remaining = float(ti.won_quantity or 0) - float(ti.supplied_quantity or 0)
                        if ordered > remaining:
                            frappe.throw("Tender " + tender.name + " has only " + str(remaining)
                                         + " remaining for " + str(ti.item_code) + ", but this order has "
                                         + str(ordered) + ". Reduce the quantity or review the tender before continuing.")

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

    # Returns Inspection completion: require returned_qty, and require the
    # lost/damaged presence wherever a lost/damaged quantity was recorded.
    #
    # Without the presence check the attribute is optional in practice and the
    # data is useless: the Director resolving the write-off cannot tell whether
    # the units physically exist, which is the only thing that distinguishes a
    # scrappable item from a missing one.
    if is_completing and doc.task_kind == "Returns processing / verification":
        case = frappe.get_doc("Dispatch Case", doc.dispatch_case)
        missing_presence = []
        for row in (case.case_items or []):
            if row.returned_qty is None:
                frappe.throw("Fill returned_qty for ALL items in Dispatch Case before completing.")
            if float(row.lost_damaged_qty or 0) > 0 and not row.get("lost_damaged_presence"):
                missing_presence.append(row.item_code or row.item_name or "Unknown")
        if missing_presence:
            frappe.throw("Say whether each lost/damaged item is damaged (in hand) or lost (not recoverable): "
                         + ", ".join(missing_presence))

    # Invoice Preparation completion: require a submitted invoice for the case.
    #
    # Resolved by querying Sales Invoice.dispatch_case rather than by following
    # Dispatch Case.sales_invoice. The old check read that link and refused
    # whenever it pointed at a cancelled document -- which is exactly what
    # Cancel + Amend produces, since the amendment gets a NEW name and the case
    # keeps pointing at the cancelled original. DC-2026-00015 on test is stuck
    # that way: ACC-SINV-2026-00001 cancelled, ACC-SINV-2026-00001-1 submitted
    # and orphaned. An amendment carries dispatch_case forward, so this finds it.
    #
    # task_close_case_nothing_to_invoice completes the task by its own route for
    # cases with nothing to bill, so this gate no longer traps them.
    if is_completing and doc.task_kind == "Invoice preparation / create invoice":
        submitted_invoices = frappe.get_all(
            "Sales Invoice",
            filters={"dispatch_case": doc.dispatch_case, "docstatus": 1},
            fields=["name"],
            limit_page_length=1,
        )
        if not submitted_invoices:
            any_invoice = frappe.get_all(
                "Sales Invoice",
                filters={"dispatch_case": doc.dispatch_case, "docstatus": ["!=", 2]},
                fields=["name", "docstatus"],
                limit_page_length=1,
            )
            if any_invoice:
                frappe.throw("Invoice " + any_invoice[0].name + " for this case is still a draft. Submit it before completing this task.")
            # An invoice is only REQUIRED when there is something to bill.
            # Demanding one unconditionally is what made a fully-returned case
            # unfinishable, and it would also have blocked
            # task_close_case_nothing_to_invoice, which completes this task
            # after closing the case.
            gate_case = frappe.get_doc("Dispatch Case", doc.dispatch_case)
            billable = False
            for gate_row in (gate_case.case_items or []):
                if float(gate_row.used_qty or 0) > 0:
                    billable = True
            if billable:
                frappe.throw("This case has items to bill but no submitted Sales Invoice yet. Use 'Create & Submit Invoice' on this task.")
            if gate_case.status != "Closed":
                frappe.throw("There is nothing to invoice on this case. Use 'Nothing to Invoice' so the case is closed with a recorded reason.")
