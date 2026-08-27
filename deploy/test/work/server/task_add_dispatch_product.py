# Name: task_add_dispatch_product
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

def run_script():
    task_name = frappe.form_dict.get("task_name")
    item_code = frappe.form_dict.get("item_code")
    qty = float(frappe.form_dict.get("qty") or 1)
    batch_no = frappe.form_dict.get("batch_no")
    unit_price = float(frappe.form_dict.get("unit_price") or 0)
    if not task_name:
        frappe.throw("Task is required.")
    if not item_code:
        frappe.throw("Choose Product first.")
    task = frappe.get_doc("Task", task_name)
    if not task.get("dispatch_case"):
        frappe.throw("Create or link Dispatch Case / Packing Items first.")
    case = frappe.get_doc("Dispatch Case", task.dispatch_case)
    item_name = frappe.db.get_value("Item", item_code, "item_name") or item_code
    row = case.append("case_items", {})
    row.item_code = item_code
    row.item_name = item_name
    row.dispatched_qty = qty
    row.batch_no = batch_no or None
    row.unit_price = unit_price
    row.custom_scanned_qty = 0
    row.custom_remaining_qty = qty
    row.custom_packing_status = "Not Started"
    case.flags.ignore_permissions = True
    case.save()
    frappe.response["message"] = {"ok": True, "dispatch_case": case.name, "item_code": item_code}
run_script()