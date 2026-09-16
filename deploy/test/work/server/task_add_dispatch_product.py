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
    # NOTE: any `unit_price` sent by the client is deliberately ignored. The
    # price is resolved server-side below. Deviations go through discount_pct.
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
    # ── Resolve the selling price on the SERVER ───────────────────────
    # The price used to be whatever the client sent, defaulting to 0, pre-filled
    # in the browser from Item.standard_rate. That field is populated on zero
    # items, which is why 94% of submitted case rows carried unit_price = 0 and
    # the auto-created invoices were near-worthless. It also ignored the
    # Price List / tender architecture entirely.
    #
    # Precedence (Doc 09 + Doc 16): active Tender Agreement -> customer-specific
    # Item Price -> Standard Selling -> refuse. A client-supplied price is NOT
    # trusted; deviations belong in discount_pct, which routes through Director
    # approval.
    #
    # Tender first is what makes C2 unreachable: the Sales Invoice tender
    # validator refuses any rate that differs from the tender price, and by the
    # time the invoice is built the price is already the tender price.
    resolved_price = 0
    price_source = ""
    tender_name = ""

    for t in (frappe.get_all("Tender Agreement",
                             filters={"hospital": case.customer, "status": "Active"},
                             fields=["name"], limit_page_length=0) or []):
        tender = frappe.get_doc("Tender Agreement", t.name)
        for ti in (tender.items or []):
            if ti.item_code == item_code and (ti.tender_price or 0) > 0:
                resolved_price = float(ti.tender_price)
                price_source = "Tender Agreement " + tender.name
                tender_name = tender.name

    if not resolved_price and case.customer:
        cust_price = frappe.db.get_value(
            "Item Price",
            {"item_code": item_code, "price_list": "Standard Selling", "customer": case.customer},
            "price_list_rate")
        if cust_price and float(cust_price) > 0:
            resolved_price = float(cust_price)
            price_source = "Customer price for " + str(case.customer)

    if not resolved_price:
        list_price = frappe.db.get_value(
            "Item Price",
            {"item_code": item_code, "price_list": "Standard Selling"},
            "price_list_rate")
        if list_price and float(list_price) > 0:
            resolved_price = float(list_price)
            price_source = "Standard Selling"

    if not resolved_price:
        frappe.throw("No selling price is set up for " + str(item_code) + ". Add an Item Price on the Standard Selling price list (or a Tender Agreement price for this hospital) before adding it to an order.")

    # A tender price is contractual, so it cannot be discounted.
    if tender_name and discount_pct > 0:
        frappe.throw("Item " + str(item_code) + " is covered by " + tender_name + " at " + str(resolved_price) + ". A tender price cannot be discounted.")

    print(f"[Price] {frappe.utils.now()} case={case.name} item={item_code} price={resolved_price} source={price_source}")

    item_name = frappe.db.get_value("Item", item_code, "item_name") or item_code
    row = case.append("case_items", {})
    row.item_code = item_code
    row.item_name = item_name
    row.dispatched_qty = qty
    row.batch_no = batch_no or None
    row.unit_price = resolved_price
    row.discount_pct = discount_pct
    case.flags.ignore_permissions = True
    case.save()
    frappe.response["message"] = {
        "ok": True, "dispatch_case": case.name, "item_code": item_code,
        "unit_price": resolved_price, "price_source": price_source,
    }
run_script()