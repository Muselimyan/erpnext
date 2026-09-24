# Name: task_mark_item_packed
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

case_name = frappe.form_dict.get("case_name")
row_name = (frappe.form_dict.get("row_name") or "").strip()
packed = int(frappe.form_dict.get("packed") or 0)

if not case_name:
    frappe.throw("Dispatch Case is required.")

# Rows are addressed by NAME, not by position.
#
# item_idx was the array index of the row in the browser's rendering. It is only
# correct while nothing reorders case_items between render and submit -- another
# user adding or removing a product, or a template being reapplied, silently
# moved the write onto a different implant. The position is not an identity.
#
# A caller still sending item_idx is refused rather than quietly served, so the
# fragile path cannot survive unnoticed.
if not row_name:
    if frappe.form_dict.get("item_idx") is not None:
        frappe.throw("This endpoint now takes row_name, not item_idx. A row's position is not its identity: "
                     "if case_items is reordered between reading and writing, an index updates the wrong product.")
    frappe.throw("row_name is required.")

# Ownership AND kind. Filtering by the caller makes it deterministic; asserting
# the kind makes it correct. Without the kind check, holding ANY open task on
# the case was enough -- so the driver on the Delivery task, or the accountant on
# Invoice Preparation, could set packed quantities. Multiple open tasks per case
# is normal by design: returns inspection fans out to Write-off Approval,
# Invoice preparation and Returns restocking at once.
mytasks = frappe.get_all(
    "Task",
    filters={"dispatch_case": case_name, "custom_accepted_by": frappe.session.user,
             "status": ["not in", ["Completed", "Cancelled"]]},
    fields=["name", "task_kind"],
    limit_page_length=0,
)
acting_kind = ""
for t in mytasks:
    if t.task_kind == "Pack / prepare items":
        acting_kind = t.task_kind
if not acting_kind:
    frappe.throw("Packing can only be recorded from an accepted Pack / prepare items task.")

case = frappe.get_doc("Dispatch Case", case_name)

row = None
for r in (case.case_items or []):
    if r.name == row_name:
        row = r
if row is None:
    frappe.throw("Row " + row_name + " is not on Dispatch Case " + case_name + ".")
required_qty = float(row.dispatched_qty or 0)

row.custom_scanned_qty = required_qty if packed else 0

case.flags.ignore_permissions = True
case.flags.ignore_validate_update_after_submit = True
case.save()

frappe.response["message"] = {
    "ok": True,
    "item_code": row.item_code,
    "packed": packed,
    "scanned_qty": row.custom_scanned_qty,
    "remaining_qty": max(float(row.dispatched_qty or 0) - float(row.custom_scanned_qty or 0), 0)
}