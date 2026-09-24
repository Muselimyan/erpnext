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
    # A DISCOUNT MAY NOT REACH 100. Nothing bounded this before, so 100 (and 150,
    # and negatives) were all accepted -- and 100 produces an effective rate of
    # zero, which is not a discounted sale but a giveaway wearing one's clothes.
    # It then flowed through billing as though it were a priced line: the invoice
    # refused it, the nothing-to-invoice path counted it as billable, and the
    # task could be finished by neither route.
    #
    # Free-of-charge supply, if it is ever wanted, needs its own mechanism and
    # its own approval -- not a price of zero moving through the sales ledger.
    # A negative discount is a price increase by the back door; prices come from
    # the price list or a tender, so that is refused too.
    # KEEP IN SYNC WITH task_update_dispatch_product.py.
    if discount_pct < 0:
        frappe.throw("Discount cannot be negative. To charge more than the list price, change the price list or the tender, not the discount.")
    if discount_pct >= 100:
        frappe.throw("A discount of " + str(discount_pct) + "% is not allowed: it prices the item at zero. "
                     + "The maximum discount is just under 100%. If these goods are genuinely free of charge, "
                     + "they must not be added to a priced order.")
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

    # TWO ACTIVE TENDERS ON ONE ITEM IS REFUSED HERE, NOT AT INVOICING.
    #
    # This loop used to have no break and no order_by, so when two active
    # tenders covered the same item the LAST one scanned won -- from an
    # unordered query, so which price a client got was not deterministic. The
    # collision was caught much later, by the Sales Invoice validator, which
    # throws on submit. By then the order had been picked, delivered and
    # returned, and the throw left a stranded draft invoice that blocked every
    # retry (A9-2). The failure surfaced at the far end of the flow from the
    # thing that caused it.
    #
    # Refusing at order entry means the person who can actually fix it -- close
    # or expire the duplicate tender -- is told at the moment they are choosing
    # the item, and the message matches the validator's wording so the two read
    # as one rule.
    #
    # order_by makes the surviving single-match case deterministic too.
    tender_matches = []
    for t in (frappe.get_all("Tender Agreement",
                             filters={"hospital": case.customer, "status": "Active"},
                             fields=["name"], order_by="valid_to asc, valid_from asc, name asc",
                             limit_page_length=0) or []):
        tender = frappe.get_doc("Tender Agreement", t.name)
        for ti in (tender.items or []):
            if ti.item_code == item_code and (ti.tender_price or 0) > 0:
                tender_matches.append({"name": tender.name, "price": float(ti.tender_price)})

    if len(tender_matches) > 1:
        frappe.throw("Multiple active Tender Agreements cover " + str(item_code)
                     + " for " + str(case.customer) + ": "
                     + ", ".join([m["name"] for m in tender_matches])
                     + ". Only one active tender per hospital and item is allowed. "
                     + "Close or expire the duplicate before adding this item to an order.")

    if len(tender_matches) == 1:
        resolved_price = tender_matches[0]["price"]
        tender_name = tender_matches[0]["name"]
        price_source = "Tender Agreement " + tender_name

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