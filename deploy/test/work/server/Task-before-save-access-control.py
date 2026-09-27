# Name: Task-before-save-access-control
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

# ═══════════════════════════════════════════════════════════════════════
# SINGLE OWNER of Task access control.
#
# Absorbs and replaces:
#   - Task-before-save-lock-unaccepted.py   (acceptance lock + assignment reset)
#   - Task-before-save-lock-completed.py    (completed immutability)
#   - Task-before-save-dispatch-gates.py    lines 16-22 and 39-54
#   - Task-before-save-policy.py            lines 67-75 (role checks)
#
# No other script may enforce acceptance, ownership, task-kind role access, or
# completed-task immutability on Task. Domain rules (photos required, delivery
# status order, invoice submitted, etc.) stay in Task-before-save-dispatch-gates.
#
# DESIGN — why there is no bypass flag
# -----------------------------------
# Server-side housekeeping used to announce itself by setting
# `flags.ignore_permissions`, which only ONE of the previous five checks
# honoured. That flag is standard Frappe and means "skip Frappe's own
# permission check" — it does not mean "skip our business rules". Reading it as
# a business signal is retired.
#
# Instead this gate asks WHAT CHANGED rather than WHO is writing. A save that
# touches only system-managed fields is bookkeeping and is allowed; a save that
# touches anything a person can type into requires ownership. Polarity is
# default-deny: unlisted fields require ownership, so forgetting to register a
# new system field makes housekeeping fail loudly instead of silently opening a
# hole.
#
# Log tag: [AC]
# ═══════════════════════════════════════════════════════════════════════

# Fields the system may write on an existing Task without the saver owning it.
# DEFAULT-DENY: anything not listed here requires ownership.
SYSTEM_FIELDS = [
    # Acceptance bookkeeping. Note that `custom_assigned_to` is deliberately
    # NOT listed: reassignment is a supervisory act and must require ownership
    # or privilege. Accepting a task also sets it, but that save passes the
    # ownership check anyway because it sets custom_accepted_by to self.
    # `customer` and `dispatch_case` are also deliberately absent — `customer`
    # is user-editable on Order entry, and neither should ever change on an
    # existing task without an owner present.
    "custom_accepted_by",
    "custom_accepted_at",
    "completed_at",
    # Display mirror of the linked Dispatch Case, refreshed on every save by
    # Task-before-save-dispatch-gates. Must be listed or every system write
    # to a dispatch task is blocked.
    "dispatch_case_status",
    # Back-filled by Task-before-save-policy when empty, on any save.
    "task_access_policy",
    # Debt Alert snapshot, refreshed hourly by Scheduled-debt-collection.
    # These two are a deliberate exception to "no stored business facts": they
    # record what the debt WAS at the moment the alarm was raised, which is a
    # fact about the alert, not a live balance.
    "current_debt_amd",
    "debt_threshold_amd",
]

# NOTE (W2): the debt bookkeeping fields -- open_invoices, payment_history,
# total_outstanding, sales_invoice, available_advance_credit -- were listed here
# during W1 because create_or_update_debt_task() still appended invoice rows to
# an existing Debt Collection task. That cross-task write is what blocked
# Ops - Accounting users from completing Invoice Preparation.
#
# W2 deleted those fields. Debt is read live from the ledger, so there is
# nothing for the flow to append and the cross-task write no longer exists at
# all. The entries are therefore removed rather than kept as dead allowances --
# leaving them would have quietly permitted writes to fields that no longer
# have any legitimate system writer.

# Roles that may edit a task they do not own, and edit any task kind.
# NOTE: this does NOT extend to completing another user's task — see below.
PRIVILEGED_ROLES = ["System Manager", "Ops - Directors"]

# Fieldtypes that carry no data and can never constitute a change.
LAYOUT_FIELDTYPES = [
    "Section Break", "Column Break", "Tab Break", "HTML", "Heading",
    "Button", "Image", "Fold", "Barcode",
]
TABLE_FIELDTYPES = ["Table", "Table MultiSelect"]

before = doc.get_doc_before_save()

if not before:
    # Creation is governed by Frappe DocPerm plus Task-before-save-policy.
    # There is no prior owner to protect.
    pass
elif doc.status == "Template":
    # Task templates are configuration, not work.
    pass
else:
    acuser = frappe.session.user
    acroles = frappe.get_all("Has Role", filters={"parent": acuser}, pluck="role") or []
    acprivileged = (acuser == "Administrator")
    for r in PRIVILEGED_ROLES:
        if r in acroles:
            acprivileged = True

    accepted_by = doc.custom_accepted_by or ""
    before_status = before.status
    is_completing = (doc.status == "Completed" and before_status != "Completed")

    # ── 1. A completed OR CANCELLED task is immutable ───────────────────
    #
    # Cancelled is a final state, exactly like Completed. This used to protect
    # Completed only, and a cancelled task was locked solely by the client-side
    # editability script -- which is a convenience, not an enforcement. So a
    # privileged user could reopen a cancelled task, and its accepter could then
    # complete it. On a cancelled Dispatch Case that would run the completion
    # handler for real: a reopened Pack task would move stock into transit and
    # raise a Delivery task for an order that no longer exists.
    #
    # This applies to every task in the system, not only the cancel flow. The
    # same gap existed for Debt Alerts, approvals and everything else.
    #
    # Tasks that must run AFTER a case is cancelled -- the return-to-warehouse,
    # inspection and restocking steps -- are created as NEW open tasks, so this
    # does not touch them. The cancel API writes status with frappe.db.set_value,
    # which does not run this script at all.
    if before_status in ("Completed", "Cancelled"):
        print(f"[AC] {frappe.utils.now()} task={doc.name} gate={before_status.lower()}_immutable user={acuser} result=BLOCKED")
        frappe.throw("This task is already " + before_status.lower() + " and cannot be modified.")

    # ── 2. What changed? ────────────────────────────────────────────────
    # Scalars via has_value_changed. Child tables need an explicit signature:
    # has_value_changed compares lists of row objects by identity, so it
    # reports every table as changed on every save, which would make the
    # system-field allowance useless.
    acmeta = frappe.get_meta("Task")
    changed = []
    for df in acmeta.fields:
        fn = df.fieldname
        ft = df.fieldtype
        if not fn:
            continue
        if ft in LAYOUT_FIELDTYPES:
            continue
        if ft in TABLE_FIELDTYPES:
            if not df.options:
                continue
            childmeta = frappe.get_meta(df.options)
            beforerows = before.get(fn) or []
            currentrows = doc.get(fn) or []
            if len(beforerows) != len(currentrows):
                changed.append(fn)
            else:
                sigbefore = []
                sigafter = []
                for row in beforerows:
                    for cdf in childmeta.fields:
                        if cdf.fieldname and cdf.fieldtype not in LAYOUT_FIELDTYPES:
                            sigbefore.append(str(row.get(cdf.fieldname)))
                for row in currentrows:
                    for cdf in childmeta.fields:
                        if cdf.fieldname and cdf.fieldtype not in LAYOUT_FIELDTYPES:
                            sigafter.append(str(row.get(cdf.fieldname)))
                if sigbefore != sigafter:
                    changed.append(fn)
        else:
            if doc.has_value_changed(fn):
                changed.append(fn)

    userchanged = []
    for fn in changed:
        if fn not in SYSTEM_FIELDS:
            userchanged.append(fn)

    # ── 3. Assignment change resets acceptance ──────────────────────────
    # Accepting a task also reassigns it to the accepter, which must NOT count
    # as a reassignment. The old script distinguished these by reading
    # ignore_permissions; instead compare the new assignee against the
    # accepter — on accept they are the same person.
    old_assigned = before.custom_assigned_to or ""
    new_assigned = doc.custom_assigned_to or ""
    if old_assigned != new_assigned and new_assigned != accepted_by:
        print(f"[AC] {frappe.utils.now()} task={doc.name} assignment_changed {old_assigned} -> {new_assigned} resetting acceptance")
        doc.custom_accepted_by = ""
        doc.custom_accepted_at = None
        doc.status = "Open"
        accepted_by = ""
        is_completing = False

    # ── 4. Completion is reserved to the accepter. No exceptions. ───────
    # Decision (c): admins may edit and unstick, but may never mark another
    # person's work as done — the record of who did the work must stay true.
    # Cancellation remains available as the escape hatch for stuck tasks.
    if is_completing:
        if (doc.custom_assigned_to or "") != old_assigned:
            frappe.throw("You cannot reassign and complete a task at the same time. Save the reassignment first.")
        if not accepted_by:
            print(f"[AC] {frappe.utils.now()} task={doc.name} gate=complete_unaccepted user={acuser} result=BLOCKED")
            frappe.throw("You must accept this task before completing it. Click Accept / Start Task first.")
        if accepted_by != acuser:
            print(f"[AC] {frappe.utils.now()} task={doc.name} gate=complete_not_owner user={acuser} accepted_by={accepted_by} result=BLOCKED")
            frappe.throw("Only the user who accepted this task (" + accepted_by + ") can complete it.")

    # ── 5. Editing requires ownership, unless only system fields changed ─
    if not userchanged:
        print(f"[AC] {frappe.utils.now()} task={doc.name} system_write fields={changed} result=ALLOWED")
    else:
        if not accepted_by:
            if acprivileged:
                print(f"[AC] {frappe.utils.now()} task={doc.name} gate=edit_unaccepted user={acuser} result=ALLOWED_PRIVILEGED fields={userchanged}")
            else:
                print(f"[AC] {frappe.utils.now()} task={doc.name} gate=edit_unaccepted user={acuser} result=BLOCKED fields={userchanged}")
                frappe.throw("You must accept this task before making any changes. Click Accept / Start Task first.")
        elif accepted_by != acuser:
            if acprivileged:
                print(f"[AC] {frappe.utils.now()} task={doc.name} gate=edit_not_owner user={acuser} accepted_by={accepted_by} result=ALLOWED_PRIVILEGED fields={userchanged}")
            else:
                print(f"[AC] {frappe.utils.now()} task={doc.name} gate=edit_not_owner user={acuser} accepted_by={accepted_by} result=BLOCKED fields={userchanged}")
                frappe.throw("Only the user who accepted this task (" + accepted_by + ") can edit it.")

        # ── 6. Task-kind role access ────────────────────────────────────
        # Applies only to genuine user edits: a system-only write never
        # reaches here, which is what stops one team's housekeeping from
        # being judged against another team's role list.
        if doc.task_kind and not acprivileged:
            allowed = []
            try:
                acpolicy = frappe.get_doc("Task Access Policy", doc.task_kind)
                for rr in (acpolicy.allowed_roles or []):
                    if rr.role:
                        allowed.append(rr.role)
            except Exception:
                allowed = []
            if allowed:
                hasrole = False
                for r in allowed:
                    if r in acroles:
                        hasrole = True
                if not hasrole:
                    print(f"[AC] {frappe.utils.now()} task={doc.name} gate=kind_role kind={doc.task_kind} user={acuser} allowed={allowed} result=BLOCKED")
                    frappe.throw("You are not allowed to edit Task Kind '" + doc.task_kind + "'.")
