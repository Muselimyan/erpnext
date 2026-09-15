# Name: task_apply_template
# Type: API
# DocType: 
# Event: 
# Disabled: 0
# ---

task_name = frappe.form_dict.get("task_name")
template_name = frappe.form_dict.get("template_name")
if not task_name or not template_name:
    frappe.throw("Task and template are required.")

task = frappe.get_doc("Task", task_name)
if (task.get("custom_accepted_by") or "") != frappe.session.user:
    frappe.throw("You must accept the task before making changes.")
if (task.get("task_kind") or "") != "Order entry":
    frappe.throw("A template can only be applied from an Order entry task.")
if not task.dispatch_case:
    frappe.throw("No Dispatch Case linked to this task.")

dc = frappe.get_doc("Dispatch Case", task.dispatch_case)
# Applying a template REPLACES all case items, so it must never run against a
# case that has already been submitted, packed or delivered.
if (dc.docstatus or 0) != 0:
    frappe.throw("This Dispatch Case is already submitted; a template cannot replace its products.")
if dc.status not in ("Draft", "Awaiting Approval"):
    frappe.throw("A template can only be applied while the Dispatch Case is in Draft or Awaiting Approval. Current status: " + str(dc.status))
template = frappe.get_doc("Surgical Kit Template", template_name)

dc.set("case_items", [])
for t_row in (template.template_items or []):
    dc.append("case_items", {
        "item_code": t_row.item_code,
        "item_name": t_row.item_name,
        "dispatched_qty": t_row.qty or 1,
    })

dc.flags.ignore_permissions = True
dc.save()

print(f"[Template] Applied template {template_name} to DC {dc.name}: {len(dc.case_items)} items")
frappe.response["message"] = {"ok": True, "items_count": len(dc.case_items)}
