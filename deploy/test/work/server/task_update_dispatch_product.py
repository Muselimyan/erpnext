# Name: task_update_dispatch_product
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

def run_script():
    case_name = frappe.form_dict.get("case_name")
    row_name = frappe.form_dict.get("row_name")
    dispatched_qty = frappe.form_dict.get("dispatched_qty")
    unit_price = frappe.form_dict.get("unit_price")
    discount_pct = frappe.form_dict.get("discount_pct")
    batch_no = frappe.form_dict.get("batch_no")
    if not case_name or not row_name:
        frappe.throw("case_name and row_name are required.")
    # Deterministic ownership check plus an explicit kind assertion: products
    # may only be changed from an Order entry task. Previously any open task on
    # the case would do, chosen non-deterministically.
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
        frappe.throw("Products can only be changed from an accepted Order entry task.")
    case = frappe.get_doc("Dispatch Case", case_name)
    if (case.docstatus or 0) != 0:
        frappe.throw("This Dispatch Case is already submitted and its products cannot be changed.")
    if case.status not in ("Draft", "Awaiting Approval"):
        frappe.throw("Products can only be changed while the Dispatch Case is in Draft or Awaiting Approval. Current status: " + str(case.status))

    found = False
    target_item = ""
    for row in case.case_items:
        if row.name == row_name:
            target_item = row.item_code
            found = True
    if not found:
        frappe.throw("Row not found in Dispatch Case.")

    # ── Re-resolve the selling price on the SERVER ────────────────────
    # Duplicated from task_add_dispatch_product rather than shared: Frappe
    # Server Scripts run under RestrictedPython, where a module-level function
    # cannot call a sibling, and there is no module system. AGENTS.md records
    # duplication as the required pattern for shared logic here.
    #
    # A client-supplied `unit_price` is ignored. Precedence: active Tender
    # Agreement -> customer-specific Item Price -> Standard Selling -> refuse.
    resolved_price = 0
    price_source = ""
    tender_name = ""

    # Duplicate active tenders refused here too. KEEP IN SYNC WITH
    # task_add_dispatch_product.py -- the long explanation is there. Fixing only
    # the add path would move the hole rather than close it: this endpoint
    # re-resolves the price on every quantity or discount change, so it would
    # have gone on silently picking whichever tender came last.
    tender_matches = []
    for t in (frappe.get_all("Tender Agreement",
                             filters={"hospital": case.customer, "status": "Active"},
                             fields=["name"], order_by="valid_to asc, valid_from asc, name asc",
                             limit_page_length=0) or []):
        tender = frappe.get_doc("Tender Agreement", t.name)
        for ti in (tender.items or []):
            if ti.item_code == target_item and (ti.tender_price or 0) > 0:
                tender_matches.append({"name": tender.name, "price": float(ti.tender_price)})

    if len(tender_matches) > 1:
        frappe.throw("Multiple active Tender Agreements cover " + str(target_item)
                     + " for " + str(case.customer) + ": "
                     + ", ".join([m["name"] for m in tender_matches])
                     + ". Only one active tender per hospital and item is allowed. "
                     + "Close or expire the duplicate before changing this line.")

    if len(tender_matches) == 1:
        resolved_price = tender_matches[0]["price"]
        tender_name = tender_matches[0]["name"]
        price_source = "Tender Agreement " + tender_name

    if not resolved_price and case.customer:
        cust_price = frappe.db.get_value(
            "Item Price",
            {"item_code": target_item, "price_list": "Standard Selling", "customer": case.customer},
            "price_list_rate")
        if cust_price and float(cust_price) > 0:
            resolved_price = float(cust_price)
            price_source = "Customer price for " + str(case.customer)

    if not resolved_price:
        list_price = frappe.db.get_value(
            "Item Price",
            {"item_code": target_item, "price_list": "Standard Selling"},
            "price_list_rate")
        if list_price and float(list_price) > 0:
            resolved_price = float(list_price)
            price_source = "Standard Selling"

    if not resolved_price:
        frappe.throw("No selling price is set up for " + str(target_item) + ". Add an Item Price on the Standard Selling price list (or a Tender Agreement price for this hospital) before ordering it.")

    new_discount = None
    if discount_pct is not None:
        new_discount = float(discount_pct)
    if tender_name and new_discount and new_discount > 0:
        frappe.throw("Item " + str(target_item) + " is covered by " + tender_name + " at " + str(resolved_price) + ". A tender price cannot be discounted.")

    for row in case.case_items:
        if row.name == row_name:
            if dispatched_qty is not None:
                row.dispatched_qty = float(dispatched_qty)
            if new_discount is not None:
                row.discount_pct = new_discount
            if batch_no is not None:
                row.batch_no = batch_no or None
            row.unit_price = resolved_price

    print(f"[Price] {frappe.utils.now()} case={case.name} item={target_item} price={resolved_price} source={price_source}")

    case.flags.ignore_permissions = True
    case.save()
    frappe.response["message"] = {"ok": True, "unit_price": resolved_price, "price_source": price_source}
run_script()
