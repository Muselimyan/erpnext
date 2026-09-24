# Name: Dispatch-Case-before-save-access-control
# Type: DocType Event
# DocType: Dispatch Case
# Event: Before Save
# Disabled: 0
# ---

# ═══════════════════════════════════════════════════════════════════════
# SINGLE OWNER of Dispatch Case access control.
#
# Absorbs and replaces:
#   - Dispatch-Case-before-save-lock-submitted.py  (submitted-DC restriction)
#   - the copy-pasted acceptance check in six task_* API scripts
#
# Before this script, each of the six product/packing/scan APIs carried its own
# copy of the acceptance check, and all six used
#   frappe.get_all("Task", filters={...}, limit_page_length=1)
# with NO order_by — so when a case had more than one open task, WHICH task was
# checked depended on whatever row order MariaDB happened to return.
# Authorisation was non-deterministic. Centralising it here fixes that, and
# means any future route that touches a Dispatch Case is covered without
# remembering to copy the check.
#
# OWNERSHIP RULE (decision D17)
# -----------------------------
# A Dispatch Case may be modified by a user who has at least one open
# (not Completed, not Cancelled) Task linked to that case, accepted by them.
# The case carries ~9 separate task link fields (order_entry_task, pack_task,
# delivery_task, invoice_task, ...) so "the owning task" is not a single field;
# it is whichever task that user currently holds on this case.
#
# WHY THERE IS NO BYPASS FLAG — see Task-before-save-access-control.py.
# Same design: judge WHAT changed, not WHO is writing. Default-deny.
#
# Log tag: [DCAC]
# ═══════════════════════════════════════════════════════════════════════

# Fields the flow's own bookkeeping writes on an existing case, including on
# already-submitted cases, without any user holding a task at that moment
# (for example the ledger reconciliation that runs when a Payment Entry is
# submitted, or the profit write-back on debt closure).
# DEFAULT-DENY: anything not listed here requires ownership.
#
# Deliberately ABSENT, because a person edits them and they must stay gated:
#   case_items, customer, return_expected, client_location_warehouse,
#   surgery_date, notes, custom_select_surgical_kit_template
SYSTEM_FIELDS = [
    "status",
    "discount_approval_status",
    # Financial bookkeeping.
    #
    # W8 removed prepaid_amount, prepaid_payment_entry, advance_payments and
    # total_paid_amount from this list along with the fields themselves. They
    # duplicated facts the Payment Entry already states, and nothing writes
    # them any more -- an advance is a submitted unallocated Payment Entry
    # carrying its own dispatch_case and source_task. Leaving dead entries here
    # would quietly permit writes to fields with no legitimate system writer.
    "sales_invoice",
    "total_invoice_amount",
    "outstanding_amount",
    # "profit" removed along with the field itself. Nothing wrote it -- a grep
    # across every server script returned only these two allow-list entries.
    # Profit is computed into Task.custom_case_profit by
    # Payment Entry-after-submit-debt-closure-check instead. Per the rule stated
    # above, an allowance for a field with no legitimate system writer is a hole,
    # so it goes when the field does.
    # Stock movement audit links
    "dispatch_stock_entry",
    "delivery_stock_entry",
    "consumption_stock_entry",
    "return_pickup_stock_entry",
    "return_receive_stock_entry",
    "restock_stock_entry",
    # Task wiring
    "order_entry_task",
    "pack_task",
    "delivery_task",
    "return_waiting_task",
    "return_pickup_task",
    "returns_inspection_task",
    "restock_task",
    "invoice_task",
    "discount_approval_task",
    # Packing problem tracking, written by Dispatch Case-packing-problem-alerts.
    "custom_packing_problem_status",
    "custom_packing_problem_summary",
    "custom_problem_alert_sent",
]

# May edit a case they hold no task on.
PRIVILEGED_ROLES = ["System Manager", "Ops - Directors"]

LAYOUT_FIELDTYPES = [
    "Section Break", "Column Break", "Tab Break", "HTML", "Heading",
    "Button", "Image", "Fold", "Barcode",
]
TABLE_FIELDTYPES = ["Table", "Table MultiSelect"]

before = doc.get_doc_before_save()

if not before:
    # Creation is governed by Frappe DocPerm. There is no prior state to guard.
    pass
else:
    dcuser = frappe.session.user
    dcroles = frappe.get_all("Has Role", filters={"parent": dcuser}, pluck="role") or []
    dcprivileged = (dcuser == "Administrator")
    for r in PRIVILEGED_ROLES:
        if r in dcroles:
            dcprivileged = True

    # ── 1. What changed? ────────────────────────────────────────────────
    # Child tables need an explicit signature: has_value_changed compares
    # lists of row objects by identity and so reports every table as changed
    # on every save, which would defeat the system-field allowance.
    dcmeta = frappe.get_meta("Dispatch Case")
    changed = []
    for df in dcmeta.fields:
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

    # ── 2. System-only bookkeeping is always allowed ────────────────────
    # This must be checked BEFORE the submitted-case restriction, because the
    # flow legitimately updates status, financials and stock links on cases
    # that are already submitted.
    if not userchanged:
        print(f"[DCAC] {frappe.utils.now()} dc={doc.name} system_write fields={changed} result=ALLOWED")
    else:
        # ── 3. Ownership (D17) ──────────────────────────────────────────
        holder = False
        opentasks = frappe.get_all(
            "Task",
            filters={"dispatch_case": doc.name, "status": ["not in", ["Completed", "Cancelled"]]},
            fields=["name", "task_kind", "custom_accepted_by"],
            limit_page_length=0,
        )
        for t in (opentasks or []):
            if (t.custom_accepted_by or "") == dcuser:
                holder = True

        if not holder and not dcprivileged:
            print(f"[DCAC] {frappe.utils.now()} dc={doc.name} gate=no_accepted_task user={dcuser} open_tasks={len(opentasks or [])} result=BLOCKED fields={userchanged}")
            frappe.throw("You must accept a task for this Dispatch Case before changing it.")

        # NOTE: there is deliberately no "only Directors may edit a submitted
        # case" branch here.
        #
        # Two reasons. First, it could never fire: Frappe runs `before_save`
        # only when _action == "save", and a submitted document saves with
        # _action == "update_after_submit", which runs
        # `before_update_after_submit` instead. Every Before Save script --
        # including the lock-submitted script this one absorbed -- is therefore
        # invisible to submitted documents, so that rule has never once been
        # enforced. Verified with w9-probe-submitted-gate.py.
        #
        # Second, enforcing it literally would break the whole operational flow.
        # A case is submitted at order confirmation and then spends its working
        # life submitted -- packing, delivery, returns inspection all mutate it.
        # Restricting that to Directors would stop Ops working entirely.
        #
        # What submission is actually meant to freeze is the COMMERCIAL terms,
        # and Frappe already enforces that through allow_on_submit: a field
        # without it cannot change after submit, whoever is asking.
        #
        # Ownership for submitted cases is enforced by the twin script
        # Dispatch-Case-before-save-submitted-access-control, registered on
        # "Before Save (Submitted Document)".

        print(f"[DCAC] {frappe.utils.now()} dc={doc.name} user={dcuser} holder={holder} privileged={dcprivileged} result=ALLOWED fields={userchanged}")
