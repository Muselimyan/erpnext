# Name: dispatch_case_cancel
# Type: API
# DocType: 
# Event: 
# Disabled: 0
# ---

# ═══════════════════════════════════════════════════════════════════════
# Cancel a Dispatch Case. Design: deploy/test/work/cancel-flow-design.md
#
# A case may be cancelled until its goods reach the client. Before that point
# the flow never creates an invoice, so cancellation never involves billing,
# credit notes or tender quantities. If the goods have left Main they come back
# through the existing returns chain, which this raises the first task of.
#
# ORDER MATTERS in the steps below:
#   - the case row is locked FIRST, so a Pack completing in a parallel request
#     cannot move stock after this has decided nothing needs bringing back
#   - open tasks are cancelled BEFORE the return task is raised, or the cancel
#     loop would cancel the return task too
#   - status is set LAST, so any failure leaves the case untouched (the whole
#     request rolls back)
#
# Writes use frappe.db.set_value deliberately. It is the only way to change
# `status` on a task the caller does not own -- `status` cannot be on an
# access-control script's system-field list, because it is the field users
# edit. It also skips the completion checks, which is correct: those enforce
# the rules for FINISHING work, and a cancelled task was not finished.
#
# No ToDos are created. The system is task-based: the Task list filters on
# _assign, which is set so the return task appears in the driver's queue.
# ═══════════════════════════════════════════════════════════════════════

def run_script():
    # Constants live INSIDE the function. RestrictedPython does not expose the
    # module namespace to a def body (AGENTS.md), so module-level constants
    # would compile, save cleanly, and then raise NameError on first execution.
    CANCELLABLE = ["Draft", "Awaiting Approval", "Confirmed", "Packed", "In Transit"]
    PRE_SUBMIT = ["Draft", "Awaiting Approval"]
    NEEDS_RETURN = ["Packed", "In Transit"]
    IN_RETURN_FLOW = ["Awaiting Return Pickup", "Return Pickup Scheduled", "Return In Transit", "Returns Received"]
    REASONS = ["Customer cancelled", "Surgery cancelled or postponed", "Items unavailable",
               "Duplicate order", "Entered in error", "Other"]
    DIRECTOR_ROLE = "Ops - Directors"
    RETURN_KIND = "Return to warehouse (aborted delivery / cancelled order)"

    case_name = (frappe.form_dict.get("dispatch_case") or "").strip()
    reason = (frappe.form_dict.get("reason") or "").strip()
    notes = (frappe.form_dict.get("notes") or "").strip()
    user = frappe.session.user
    now = frappe.utils.now()

    if not case_name:
        frappe.throw("Dispatch Case is required.")

    # ── 1. Lock the case row before reading anything ──────────────────
    # SELECT ... FOR UPDATE holds the row until this request commits. Every
    # other write to the case -- Pack completion included -- waits behind it,
    # so the status read here cannot go stale before the decision is made.
    # Frappe's own for_update rather than raw SQL: it is the native API, and it
    # does not depend on safe_exec's inspection of SQL strings.
    dc = frappe.db.get_value(
        "Dispatch Case", case_name,
        ["name", "status", "docstatus", "return_expected", "order_entry_task",
         "cancellation_reason", "cancelled_by", "cancelled_at"],
        as_dict=True, for_update=True)
    if not dc:
        frappe.throw("Dispatch Case " + case_name + " does not exist.")
    status = dc.status or ""

    # ── 2. Is it cancellable? Refusals say what to do instead ─────────
    if status == "Cancelled":
        frappe.throw("This case was already cancelled on " + str(dc.cancelled_at or "")
                     + " by " + str(dc.cancelled_by or "") + ": " + str(dc.cancellation_reason or "") + ".")
    if status == "Closed":
        frappe.throw("This case is closed. A correction after closure is a credit note.")
    if status not in CANCELLABLE:
        if status in IN_RETURN_FLOW or (status == "Delivered" and dc.return_expected):
            frappe.throw("These goods have reached the client and are being handled by the return flow "
                         "(Return Call, then Pickup Returns). A case cannot be cancelled once its goods "
                         "have been delivered.")
        frappe.throw("These goods have been delivered. A case cannot be cancelled after delivery; "
                     "a correction to what was billed is a credit note against the invoice.")

    # ── 3. Authority ──────────────────────────────────────────────────
    is_director = bool(frappe.get_all("Has Role", filters={"parent": user, "role": DIRECTOR_ROLE}, limit_page_length=1))
    if status in PRE_SUBMIT:
        # The order-taker is found through the case's Order entry task, NOT by
        # looking for an open task held by the caller. In Awaiting Approval that
        # task is already Completed, so the usual check would refuse the one
        # person entitled to withdraw their own order.
        oet = dc.order_entry_task or ""
        if not oet:
            found = frappe.get_all("Task", filters={"dispatch_case": case_name, "task_kind": "Order entry"},
                                   fields=["name"], order_by="creation desc", limit_page_length=1)
            oet = found[0].name if found else ""
        accepter = frappe.db.get_value("Task", oet, "custom_accepted_by") if oet else ""
        if not is_director and (accepter or "") != user:
            frappe.throw("Only the person who took this order, or " + DIRECTOR_ROLE + ", can cancel it before it is submitted.")
    else:
        if not is_director:
            frappe.throw("Only " + DIRECTOR_ROLE + " can cancel a case once it has been submitted to the warehouse.")

    # ── 4. A reason, and a note when the reason is Other ──────────────
    if reason not in REASONS:
        frappe.throw("Choose a cancellation reason: " + ", ".join(REASONS) + ".")
    if reason == "Other" and not notes:
        frappe.throw("Explain the reason. \"Other\" with no explanation records nothing.")

    # ── 5. No invoice may exist, in any state ─────────────────────────
    # The flow never creates one this early, which is exactly why it is worth
    # checking: if one exists, someone made it by hand. It is their work, so
    # this refuses rather than deleting it.
    inv = frappe.get_all("Sales Invoice", filters={"dispatch_case": case_name, "docstatus": ["!=", 2]},
                         fields=["name", "docstatus"], limit_page_length=1)
    if inv:
        kind = "a submitted" if int(inv[0].docstatus or 0) == 1 else "a draft"
        frappe.throw("This case has " + kind + " invoice (" + inv[0].name + "). A case with an invoice "
                     "cannot be cancelled. Deal with the invoice first.")

    # Captured BEFORE the tasks are cancelled: the driver holding the box is the
    # Delivery task's accepter, and that task is about to be cancelled.
    delivery_holder = ""
    if status == "In Transit":
        dt = frappe.get_all("Task", filters={"dispatch_case": case_name, "task_kind": "Delivery"},
                            fields=["custom_accepted_by"], order_by="creation desc", limit_page_length=1)
        delivery_holder = (dt[0].custom_accepted_by or "") if dt else ""

    reason_text = reason + ((" -- " + notes) if notes else "")
    stamp = "Cancelled because " + case_name + " was cancelled by " + user + " on " + now + ": " + reason_text + "."

    # ── 6. Cancel the open tasks ──────────────────────────────────────
    open_tasks = frappe.get_all("Task",
                                filters={"dispatch_case": case_name, "status": ["not in", ["Completed", "Cancelled"]]},
                                fields=["name", "task_kind", "description", "custom_accepted_by"],
                                limit_page_length=0)
    cancelled_names = []
    for t in (open_tasks or []):
        line = stamp
        # At Confirmed the books have not moved (stock moves only when Pack
        # completes), but a packer may already have taken items off the shelf.
        # No Stock Entry is needed for that -- only a person putting them back.
        if t.task_kind == "Pack / prepare items" and (t.custom_accepted_by or ""):
            line = line + " If you pulled items for this order, return them to the shelf."
        frappe.db.set_value("Task", t.name, {
            "status": "Cancelled",
            "description": (t.description or "") + "\n\n" + line,
        })
        cancelled_names.append(t.name)

    # ── 7. Release advance credit tagged to this case ─────────────────
    # Tagged credit is earmarked: task_commit_invoice will not spend it on
    # another case, and the debt calculation does not count it against the
    # client's other invoices. With this case cancelled, the invoice that would
    # have used it will never exist -- so left tagged, the client's money would
    # be stranded for good while the system showed them owing in full.
    #
    # Payment Entry.dispatch_case is not allow_on_submit, so this must be a
    # set_value, which writes no version record. The Comment is what keeps a
    # trail of who moved the money and why.
    released = []
    for pe in (frappe.get_all("Payment Entry",
                              filters={"dispatch_case": case_name, "docstatus": 1, "payment_type": "Receive",
                                       "party_type": "Customer", "unallocated_amount": [">", 0]},
                              fields=["name", "unallocated_amount"], limit_page_length=0) or []):
        frappe.db.set_value("Payment Entry", pe.name, "dispatch_case", "")
        frappe.get_doc({
            "doctype": "Comment",
            "comment_type": "Info",
            "reference_doctype": "Payment Entry",
            "reference_name": pe.name,
            "content": "Released from " + case_name + " to general credit: that case was cancelled by "
                       + user + " on " + now + " (" + reason_text + ").",
        }).insert(ignore_permissions=True)
        released.append(pe.name + " (" + str(pe.unallocated_amount) + ")")

    # ── 8. Start the physical return, if the goods left Main ──────────
    return_task = ""
    if status in NEEDS_RETURN:
        # In Transit: one particular driver has the box, so it goes to them. If
        # it went to the pool, whoever accepted it would be recording a
        # handover they did not make. Packed: the box is in the building and
        # anyone on the team can hand it over.
        assignee = delivery_holder or (frappe.db.get_value("Task Access Policy", RETURN_KIND, "default_team_user") or "")
        customer = frappe.db.get_value("Dispatch Case", case_name, "customer")
        rt = frappe.get_doc({
            "doctype": "Task",
            "subject": "Return to warehouse: " + case_name + " (cancelled)",
            "task_kind": RETURN_KIND,
            "task_access_policy": RETURN_KIND,
            "dispatch_case": case_name,
            "customer": customer,
            "status": "Open",
            "custom_assigned_to": assignee,
            "description": "This order was cancelled (" + reason_text + "). Bring the goods for " + case_name
                           + " back to the warehouse and hand them over. Attach a photo, then complete this task.",
        })
        rt.flags.ignore_permissions = True
        rt.insert()
        # _assign is what the Task list filters on, so without it the task would
        # not appear in the assignee's queue. No ToDo -- the system is task-based.
        if assignee:
            frappe.db.set_value("Task", rt.name, "_assign", json.dumps([assignee]), update_modified=False)
        return_task = rt.name

    # ── 9. Record why, then set the status LAST ───────────────────────
    record = []
    if cancelled_names:
        record.append("Tasks cancelled: " + ", ".join(cancelled_names))
    if released:
        record.append("Advance credit released to general credit: " + ", ".join(released))
    if return_task:
        record.append("Return raised: " + return_task)
    full_notes = notes
    if record:
        full_notes = (notes + "\n\n" if notes else "") + "\n".join(record)

    frappe.db.set_value("Dispatch Case", case_name, {
        "cancellation_reason": reason,
        "cancellation_notes": full_notes,
        "cancelled_by": user,
        "cancelled_at": now,
        "status": "Cancelled",
    })

    print(f"[Cancel] {now} dc={case_name} from={status} by={user} reason={reason} tasks={len(cancelled_names)} released={len(released)} return_task={return_task}")

    frappe.response["message"] = {
        "ok": True,
        "dispatch_case": case_name,
        "cancelled_from": status,
        "tasks_cancelled": cancelled_names,
        "credit_released": released,
        "return_task": return_task,
    }


run_script()
