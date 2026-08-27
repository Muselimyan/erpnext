# Name: task_mark_item_packed
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

case_name = frappe.form_dict.get("case_name")
item_idx = frappe.form_dict.get("item_idx")
packed = frappe.form_dict.get("packed")

if not case_name:
    frappe.throw("Dispatch Case is required.")
if item_idx is None:
    frappe.throw("Item index is required.")

case = frappe.get_doc("Dispatch Case", case_name)
idx = int(item_idx)

if idx < 0 or idx >= len(case.case_items):
    frappe.throw("Invalid item index.")

row = case.case_items[idx]
required_qty = float(row.dispatched_qty or 0)

if packed:
    row.custom_scanned_qty = required_qty
    row.custom_remaining_qty = 0
    row.custom_packing_status = "Complete"
else:
    row.custom_scanned_qty = 0
    row.custom_remaining_qty = required_qty
    row.custom_packing_status = "Pending"

case.flags.ignore_permissions = True
case.save()

frappe.response["message"] = {
    "ok": True,
    "item_code": row.item_code,
    "packed": packed,
    "scanned_qty": row.custom_scanned_qty,
    "remaining_qty": row.custom_remaining_qty
}