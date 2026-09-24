# Name: task_remove_dispatch_product
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

def run_script():
    case_name = frappe.form_dict.get("case_name")
    row_name = frappe.form_dict.get("row_name")
    if not case_name or not row_name:
        frappe.throw("case_name and row_name are required.")
    # Deterministic ownership check plus an explicit kind assertion: products
    # may only be removed from an Order entry task.
    mytasks = frappe.get_all(
        "Task",
        filters={"dispatch_case": case_name, "custom_accepted_by": frappe.session.user,
                 "status": ["not in", ["Completed", "Cancelled"]]},
        fields=["name", "task_kind"],
        limit_page_length=0,
    )
    acting_kind = ""
    for t in mytasks:
        if t.task_kind == "Order entry":
            acting_kind = t.task_kind
    if not acting_kind:
        frappe.throw("Products can only be removed from an accepted Order entry task.")
    case = frappe.get_doc("Dispatch Case", case_name)
    # Same lifecycle guard task_add_dispatch_product and
    # task_update_dispatch_product already carry. Its absence here was an
    # asymmetry, not a decision: three sibling endpoints mutate the same child
    # table and only two of them refused to do it after the goods had moved.
    if (case.docstatus or 0) != 0:
        frappe.throw("This Dispatch Case is already submitted and its products cannot be changed.")
    if case.status not in ("Draft", "Awaiting Approval"):
        frappe.throw("Products can only be changed while the Dispatch Case is in Draft or Awaiting Approval. Current status: " + str(case.status))
    original_count = len(case.case_items)
    case.case_items = [r for r in case.case_items if r.name != row_name]
    if len(case.case_items) == original_count:
        frappe.throw("Row not found in Dispatch Case.")
    case.flags.ignore_permissions = True
    case.save()
    frappe.response["message"] = {"ok": True, "remaining": len(case.case_items)}
run_script()
