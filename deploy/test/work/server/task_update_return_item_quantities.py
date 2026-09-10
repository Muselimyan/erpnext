# Name: task_update_return_item_quantities
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

case_name = frappe.form_dict.get("case_name")
item_idx = frappe.form_dict.get("item_idx")
returned_qty = frappe.form_dict.get("returned_qty")
lost_damaged_qty = frappe.form_dict.get("lost_damaged_qty")

if not case_name:
    frappe.throw("Dispatch Case is required.")
if item_idx is None:
    frappe.throw("Item index is required.")

tfe_tasks = frappe.get_all("Task", filters={"dispatch_case": case_name, "status": ["not in", ["Completed", "Cancelled"]]}, fields=["custom_accepted_by"], limit_page_length=1)
if not tfe_tasks or (tfe_tasks[0].custom_accepted_by or "") != frappe.session.user:
    frappe.throw("You must accept the task before making changes.")

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

used = dispatched_qty - returned - lost_damaged
row.returned_qty = returned
row.lost_damaged_qty = lost_damaged
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
    "used_qty": used
}