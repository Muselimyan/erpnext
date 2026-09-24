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

# PRICE EVERY LINE, OR APPLY NOTHING.
#
# This used to append rows with item_code, item_name and dispatched_qty and no
# unit_price at all, so every line of every applied template landed at zero and
# went on to be packed, delivered and consumed at a price of nothing. It was the
# largest single source of unpriced rows in the system, and it bypassed the
# server-side price resolution that the add-product endpoint exists to enforce.
#
# Resolution order is the same one task_add_dispatch_product uses -- active
# tender, then customer-specific Item Price, then Standard Selling. Duplicated
# rather than shared because RestrictedPython has no module system.
# KEEP IN SYNC WITH task_add_dispatch_product.py.
#
# All-or-nothing: a template is a kit, and applying half of one silently is
# worse than refusing the lot. The refusal names every unpriced item so the
# whole list can be fixed in one pass rather than one error at a time.
priced_rows = []
unpriced_items = []
for t_row in (template.template_items or []):
    t_item = t_row.item_code
    t_price = 0
    tender_hits = []
    for t in (frappe.get_all("Tender Agreement",
                             filters={"hospital": dc.customer, "status": "Active"},
                             fields=["name"], order_by="valid_to asc, valid_from asc, name asc",
                             limit_page_length=0) or []):
        tdoc = frappe.get_doc("Tender Agreement", t.name)
        for ti in (tdoc.items or []):
            if ti.item_code == t_item and (ti.tender_price or 0) > 0:
                tender_hits.append({"name": tdoc.name, "price": float(ti.tender_price)})
    if len(tender_hits) > 1:
        frappe.throw("Multiple active Tender Agreements cover " + str(t_item)
                     + " for " + str(dc.customer) + ": "
                     + ", ".join([h["name"] for h in tender_hits])
                     + ". Close or expire the duplicate before applying this template.")
    if len(tender_hits) == 1:
        t_price = tender_hits[0]["price"]
    if not t_price and dc.customer:
        cp = frappe.db.get_value("Item Price",
                                 {"item_code": t_item, "price_list": "Standard Selling", "customer": dc.customer},
                                 "price_list_rate")
        if cp and float(cp) > 0:
            t_price = float(cp)
    if not t_price:
        lp = frappe.db.get_value("Item Price",
                                 {"item_code": t_item, "price_list": "Standard Selling"},
                                 "price_list_rate")
        if lp and float(lp) > 0:
            t_price = float(lp)
    if not t_price:
        unpriced_items.append(str(t_item))
        continue
    priced_rows.append({
        "item_code": t_item,
        "item_name": t_row.item_name,
        "dispatched_qty": t_row.qty or 1,
        "unit_price": t_price,
    })

if unpriced_items:
    frappe.throw("Template " + str(template_name) + " cannot be applied: no selling price is set up for "
                 + ", ".join(unpriced_items)
                 + ". Add an Item Price on the Standard Selling price list (or a Tender Agreement price "
                 + "for this hospital) for each, then apply the template again. "
                 + "No products were changed.")

dc.set("case_items", [])
for prow in priced_rows:
    dc.append("case_items", prow)

dc.flags.ignore_permissions = True
dc.save()

print(f"[Template] Applied template {template_name} to DC {dc.name}: {len(dc.case_items)} items")
frappe.response["message"] = {"ok": True, "items_count": len(dc.case_items)}
