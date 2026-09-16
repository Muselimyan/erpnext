# Name: task_update_return_item_quantities
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

PRESENCE_OPTIONS = ["Damaged - in hand", "Lost - not recoverable"]

case_name = frappe.form_dict.get("case_name")
item_idx = frappe.form_dict.get("item_idx")
returned_qty = frappe.form_dict.get("returned_qty")
lost_damaged_qty = frappe.form_dict.get("lost_damaged_qty")
lost_damaged_presence = frappe.form_dict.get("lost_damaged_presence")

if not case_name:
    frappe.throw("Dispatch Case is required.")
if item_idx is None:
    frappe.throw("Item index is required.")

# Deterministic ownership check plus an explicit kind assertion: return and
# lost/damaged quantities may only be set from a Returns inspection task.
# Previously any open task on the case would do, chosen non-deterministically.
mytasks = frappe.get_all(
    "Task",
    filters={"dispatch_case": case_name, "custom_accepted_by": frappe.session.user,
             "status": ["not in", ["Completed", "Cancelled"]]},
    fields=["name", "task_kind"],
    limit_page_length=0,
)
acting_kind = ""
for t in mytasks:
    if t.task_kind == "Returns processing / verification":
        acting_kind = t.task_kind
if not acting_kind:
    frappe.throw("Return quantities can only be changed from an accepted Returns processing / verification task.")

case = frappe.get_doc("Dispatch Case", case_name)
idx = int(item_idx)

if idx < 0 or idx >= len(case.case_items):
    frappe.throw("Invalid item index.")

row = case.case_items[idx]
dispatched_qty = float(row.dispatched_qty or 0)
returned = float(returned_qty or 0)
lost_damaged = float(lost_damaged_qty or 0)

if returned < 0 or lost_damaged < 0:
    frappe.throw("Returned and lost/damaged quantities cannot be negative.")
if returned + lost_damaged > dispatched_qty:
    frappe.throw("Returned plus lost/damaged quantity cannot be greater than dispatched quantity.")

# Presence is meaningful only alongside a quantity, and a quantity without it is
# unresolvable later -- the Director cannot tell a scrappable unit from a missing
# one. Keep the pair consistent here rather than only at the completion gate, so
# a half-filled row cannot be saved and then puzzled over.
presence = (lost_damaged_presence or "").strip()
if presence and presence not in PRESENCE_OPTIONS:
    frappe.throw("Unknown lost/damaged presence '" + presence + "'. Expected one of: " + ", ".join(PRESENCE_OPTIONS))
if lost_damaged > 0 and not presence:
    presence = row.get("lost_damaged_presence") or ""
if lost_damaged <= 0:
    presence = ""

used = dispatched_qty - returned - lost_damaged
row.returned_qty = returned
row.lost_damaged_qty = lost_damaged
row.lost_damaged_presence = presence
row.used_qty = used

case.flags.ignore_permissions = True
case.flags.ignore_validate_update_after_submit = True
case.save()

frappe.response["message"] = {
    "ok": True,
    "item_code": row.item_code,
    "dispatched_qty": dispatched_qty,
    "returned_qty": returned,
    "lost_damaged_qty": lost_damaged,
    "lost_damaged_presence": presence,
    "used_qty": used
}