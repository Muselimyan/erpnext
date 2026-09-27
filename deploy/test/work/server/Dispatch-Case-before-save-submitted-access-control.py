# Name: Dispatch-Case-before-save-submitted-access-control
# Type: DocType Event
# DocType: Dispatch Case
# Event: Before Save (Submitted Document)
# Disabled: 0
# ---

# ═══════════════════════════════════════════════════════════════════════
# TWIN of Dispatch-Case-before-save-access-control, for SUBMITTED cases.
#
# KEEP THE TWO IN SYNC. Frappe Server Scripts run under RestrictedPython, which
# has no module system and forbids a function calling a sibling, so shared logic
# must be duplicated -- AGENTS.md records duplication as the required pattern.
# The only intended difference is the log tag.
#
# WHY A SECOND SCRIPT IS NEEDED AT ALL
# ------------------------------------
# Frappe runs `before_save` only when _action == "save". A submitted document
# saves with _action == "update_after_submit", which runs
# `before_update_after_submit` instead. Every "Before Save" Server Script is
# therefore INVISIBLE to submitted documents.
#
# That means neither the gate nor the lock-submitted script it replaced has ever
# guarded a submitted Dispatch Case -- and a case is submitted at order
# confirmation, then spends its entire working life submitted while packing,
# delivery and returns mutate it. The unguarded half was the larger half.
#
# Verified before this script existed (w9-probe-submitted-gate.py):
#   non-holder edits a DRAFT case      -> blocked
#   non-holder edits a SUBMITTED case  -> ALLOWED
#
# Ownership rule is D17, identical to the draft gate: a case may be modified by
# a user holding at least one open, accepted Task linked to it. Submission does
# not narrow that to Directors -- doing so would stop Ops working. What
# submission freezes is the commercial terms, which Frappe already enforces
# through allow_on_submit.
#
# Log tag: [DCACS]
# ═══════════════════════════════════════════════════════════════════════

# Must match Dispatch-Case-before-save-access-control.
SYSTEM_FIELDS = [
    "status",
    "discount_approval_status",
    "sales_invoice",
    "total_invoice_amount",
    "outstanding_amount",
    # "profit" removed along with the field -- see the draft twin for why.
    "dispatch_stock_entry",
    "delivery_stock_entry",
    "consumption_stock_entry",
    "return_pickup_stock_entry",
    "return_receive_stock_entry",
    "restock_stock_entry",
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

PRIVILEGED_ROLES = ["System Manager", "Ops - Directors"]

LAYOUT_FIELDTYPES = [
    "Section Break", "Column Break", "Tab Break", "HTML", "Heading",
    "Button", "Image", "Fold", "Barcode",
]
TABLE_FIELDTYPES = ["Table", "Table MultiSelect"]

before = doc.get_doc_before_save()

if not before:
    pass
else:
    dcuser = frappe.session.user
    dcroles = frappe.get_all("Has Role", filters={"parent": dcuser}, pluck="role") or []
    dcprivileged = (dcuser == "Administrator")
    for r in PRIVILEGED_ROLES:
        if r in dcroles:
            dcprivileged = True

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

    # Cancelled is final, and only the cancel API may set it. MUST run before
    # the system-field allowance below: `status` is on SYSTEM_FIELDS, so a
    # status-only save would otherwise be allowed unconditionally. The cancel
    # API writes with frappe.db.set_value and never reaches this script.
    # KEEP IN SYNC with Dispatch-Case-before-save-access-control.py -- the
    # reasoning is written out in full there.
    if doc.has_value_changed("status") and ((before.status or "") == "Cancelled" or (doc.status or "") == "Cancelled"):
        print(f"[DCACS] {frappe.utils.now()} dc={doc.name} gate=cancelled_final from={before.status} to={doc.status} user={dcuser} result=BLOCKED")
        if (before.status or "") == "Cancelled":
            frappe.throw("This case is cancelled, and a cancelled case cannot be reopened. Raise a new case instead.")
        frappe.throw("A case can only be cancelled with the Cancel button, which also closes its tasks, "
                     "releases any advance payment and brings back goods that have left the warehouse.")

    if not userchanged:
        print(f"[DCACS] {frappe.utils.now()} dc={doc.name} system_write fields={changed} result=ALLOWED")
    else:
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
            print(f"[DCACS] {frappe.utils.now()} dc={doc.name} gate=no_accepted_task user={dcuser} open_tasks={len(opentasks or [])} result=BLOCKED fields={userchanged}")
            frappe.throw("You must accept a task for this Dispatch Case before changing it.")

        print(f"[DCACS] {frappe.utils.now()} dc={doc.name} user={dcuser} holder={holder} privileged={dcprivileged} result=ALLOWED fields={userchanged}")
