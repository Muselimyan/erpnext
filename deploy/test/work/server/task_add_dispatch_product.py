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
    discount_pct = float(frappe.form_dict.get("discount_pct") or 0)
    if not task_name:
        frappe.throw("Task is required.")
    if not item_code:
        frappe.throw("Choose Product first.")
    task = frappe.get_doc("Task", task_name)
    if (task.get("custom_accepted_by") or "") != frappe.session.user:
        frappe.throw("You must accept the task before making changes.")
    if (task.get("task_kind") or "") != "Order entry":
        frappe.throw("Products can only be added from an Order entry task.")
    if not task.get("dispatch_case"):
        frappe.throw("Create or link Dispatch Case / Packing Items first.")
    case = frappe.get_doc("Dispatch Case", task.dispatch_case)
    # Guard against adding products to a case that has already moved on.
    # Without this, an Order entry task left open alongside a packed or
    # delivered case could still mutate its contents.
    if (case.docstatus or 0) != 0:
        frappe.throw("This Dispatch Case is already submitted and its products cannot be changed.")
    if case.status not in ("Draft", "Awaiting Approval"):
        frappe.throw("Products can only be changed while the Dispatch Case is in Draft or Awaiting Approval. Current status: " + str(case.status))
    item_name = frappe.db.get_value("Item", item_code, "item_name") or item_code
    row = case.append("case_items", {})
    row.item_code = item_code
    row.item_name = item_name
    row.dispatched_qty = qty
    row.batch_no = batch_no or None
    row.unit_price = unit_price
    row.discount_pct = discount_pct
    case.flags.ignore_permissions = True
    case.save()
    frappe.response["message"] = {"ok": True, "dispatch_case": case.name, "item_code": item_code}
run_script()