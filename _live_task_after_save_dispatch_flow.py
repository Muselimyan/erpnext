COMPANY = "InMED"
MAIN_WH = "Main - Inmed"
DELIVERY_TRANSIT_WH = "Delivery In-Transit - Inmed"
RETURN_PICKUP_TRANSIT_WH = "Return Pickup In-Transit - Inmed"
RETURNS_WH = "Returns - Inmed"
INVENTORY_TEAM = "inventory.team@example.com"
DELIVERY_TEAM = "delivery.team@example.com"
RETURNS_TEAM = "returns.team@example.com"
ACCOUNTING_TEAM = "accounting.team@example.com"
FINANCE_TEAM = "finance.team@example.com"
OFFICE_TEAM = "office.team@example.com"
ORDER_CREATION_TEAM = "order.creation.team@example.com"

if not doc.dispatch_case:
    pass
else:
    before = doc.get_doc_before_save()
    before_status = before.status if before else None
    before_ds = (before.delivery_status if before else None) or "Todo"
    before_ps = (before.pickup_status if before else None) or "Todo"
    is_completing = (doc.status == "Completed" and before_status != "Completed")
    ds_changed = (doc.task_kind == "Delivery" and doc.delivery_status != before_ds)
    ps_changed = (doc.task_kind == "Pickup Returns" and doc.pickup_status != before_ps)

    def create_se(src_wh, tgt_wh, items, purpose="Material Transfer"):
        se_items = []
        for ic, q, sn, bn in items:
            if (q or 0) <= 0:
                continue
            item_doc = frappe.get_doc("Item", ic)
            stock_uom = item_doc.stock_uom or "Nos"
            row = {
                "item_code": ic, 
                "qty": q,
                "transfer_qty": q,
                "uom": stock_uom,
                "stock_uom": stock_uom,
                "conversion_factor": 1,
                "s_warehouse": src_wh,
                "expense_account": "Cost of Goods Sold - Inmed",
                "cost_center": "Main - Inmed",
                "allow_zero_valuation_rate": 1
            }
            if sn:
                row["serial_no"] = sn
            if bn:
                row["batch_no"] = bn
            if purpose != "Material Issue":
                row["t_warehouse"] = tgt_wh
            se_items.append(row)
        if not se_items:
            return None
        se = frappe.get_doc({"doctype": "Stock Entry", "stock_entry_type": purpose, "purpose": purpose, "company": "InMED", "items": se_items})
        se.flags.ignore_permissions = True
        se.flags.ignore_validate = True
        frappe.flags.ignore_stock_validation = True
        se.insert()
        se.submit()
        frappe.flags.ignore_stock_validation = False
        return se

    def all_items(c):
        return [(r.item_code, r.dispatched_qty, r.serial_no, r.batch_no) for r in (c.case_items or [])]

    def used_items(c):
        return [(r.item_code, r.used_qty, r.serial_no, r.batch_no) for r in (c.case_items or []) if (r.used_qty or 0) > 0]

    def returned_items(c):
        return [(r.item_code, r.returned_qty, r.serial_no, r.batch_no) for r in (c.case_items or []) if (r.returned_qty or 0) > 0]

    def short_customer(cname):
        if not cname:
            return cname or ""
        for sep in [" \u2014 ", " - "]:
            if sep in cname:
                parts = cname.split(sep, 1)
                if len(parts[0].strip()) <= 6:
                    return parts[1]
        return cname

    def make_task(kind, subject, assignee, desc="", link_field=None, dispatch_case_name=None, customer=None):
        dc_name = dispatch_case_name or doc.dispatch_case
        cust = customer or frappe.db.get_value("Dispatch Case", dc_name, "customer")
        existing = frappe.db.exists("Task", {"dispatch_case": dc_name, "task_kind": kind, "status": ["not in", ["Completed", "Cancelled"]]})
        if existing:
            return existing
        t = frappe.get_doc({
            "doctype": "Task", "subject": subject, "task_kind": kind, "task_access_policy": kind,
            "dispatch_case": dc_name, "customer": cust, "description": desc,
        })
        t.flags.ignore_permissions = True
        t.insert()
        if link_field:
            frappe.db.set_value("Dispatch Case", dc_name, link_field, t.name)
        # FIXED: Update _assign via db (assign_to module not available in RestrictedPython)
        frappe.db.set_value("Task", t.name, "_assign", json.dumps([assignee]))
        todo = frappe.new_doc("ToDo")
        todo.status = "Open"
        todo.allocated_to = assignee
        todo.reference_type = "Task"
        todo.reference_name = t.name
        todo.description = subject
        todo.assigned_by = frappe.session.user
        todo.flags.ignore_permissions = True
        todo.insert()
        return t.name

    def create_invoice(c):
        items_rows = []
        for r in (c.case_items or []):
            if r.used_qty is not None and str(r.used_qty) != "":
                qty = float(r.used_qty)
            else:
                qty = float(r.dispatched_qty or 0)
            if qty <= 0:
                continue
            rate = (r.unit_price or 0) * (1 - (r.discount_pct or 0) / 100)
            items_rows.append({"item_code": r.item_code, "qty": qty, "rate": rate})
        if not items_rows:
            return
        currency = "AMD"
        if c.get("currency"):
            currency = c.currency
        si = frappe.get_doc({"doctype": "Sales Invoice", "customer": c.customer, "company": "InMED", "currency": currency, "update_stock": 0, "items": items_rows})
        si.flags.ignore_permissions = True
        si.insert()
        frappe.db.set_value("Dispatch Case", c.name, "sales_invoice", si.name)

    def create_or_update_debt_task(c, outstanding, inv_name):
        FINANCE_TEAM = "finance.team@example.com"
        existing = frappe.db.get_value("Task", {"customer": c.customer, "task_kind": "Debt Collection", "status": ["not in", ["Completed", "Cancelled"]]}, "name")
        inv_row = {"dispatch_case": c.name, "sales_invoice": inv_name, "invoice_amount": outstanding, "paid_amount": 0, "outstanding_amount": outstanding}
        if existing:
            t = frappe.get_doc("Task", existing)
            t.append("open_invoices", inv_row)
            t.total_outstanding = sum((r.outstanding_amount or 0) for r in t.open_invoices)
            t.sales_invoice = inv_name
            t.flags.ignore_permissions = True
            t.save()
        else:
            t = frappe.get_doc({
                "doctype": "Task", "subject": f"Debt Collection: {c.customer}",
                "task_kind": "Debt Collection", "task_access_policy": "Debt Collection",
                "customer": c.customer, "total_outstanding": outstanding, "sales_invoice": inv_name,
                "open_invoices": [inv_row],
            })
            t.flags.ignore_permissions = True
            t.insert()
            # FIXED: Update _assign via db (assign_to module not available in RestrictedPython)
            frappe.db.set_value("Task", t.name, "_assign", json.dumps([FINANCE_TEAM]))
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = FINANCE_TEAM
            todo.reference_type = "Task"
            todo.reference_name = t.name
            todo.description = t.subject
            todo.assigned_by = frappe.session.user
            todo.flags.ignore_permissions = True
            todo.insert()

    case = frappe.get_doc("Dispatch Case", doc.dispatch_case)

    # Delivery: Picked Up
    if ds_changed and doc.delivery_status == "Picked Up":
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "In Transit")

    # Delivery: Delivered
    if ds_changed and doc.delivery_status == "Delivered":
        if doc.warehouse_pickup_photo:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "delivery_photo", doc.warehouse_pickup_photo)
        se = create_se(DELIVERY_TRANSIT_WH, case.client_location_warehouse, all_items(case))
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Delivered", "delivery_stock_entry": se.name if se else ""})
        case.reload()
        if not case.return_expected:
            c_se = create_se(case.client_location_warehouse, "", all_items(case), "Material Issue")
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"consumption_stock_entry": c_se.name if c_se else "", "status": "Invoice Pending"})
            create_invoice(case)
            make_task("Invoice preparation / create invoice", f"Invoice: {short_customer(case.customer)} ({case.name})", ACCOUNTING_TEAM, f"Review and submit draft Sales Invoice for {case.name}.", "invoice_task", doc.dispatch_case, case.customer)
        else:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Awaiting Return Pickup")
            make_task("Return Call", f"Return call: {short_customer(case.customer)} ({case.name})", OFFICE_TEAM, f"Waiting for {case.customer} to call regarding return pickup. Fill in details and assign to driver.", "return_waiting_task", doc.dispatch_case, case.customer)

    # Return Pickup: Picked Up
    if ps_changed and doc.pickup_status == "Picked Up":
        case.reload()
        se = create_se(case.client_location_warehouse, RETURN_PICKUP_TRANSIT_WH, all_items(case))
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Return In Transit", "return_pickup_stock_entry": se.name if se else ""})

    # Return Pickup: Returned to Warehouse
    if ps_changed and doc.pickup_status == "Returned to Warehouse":
        if doc.warehouse_dropoff_photo:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "return_dropoff_photo", doc.warehouse_dropoff_photo)
        se = create_se(RETURN_PICKUP_TRANSIT_WH, RETURNS_WH, all_items(case))
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Returns Received", "return_receive_stock_entry": se.name if se else ""})
        ret_tid = make_task("Returns processing / verification", f"Inspect returns: {short_customer(case.customer)} ({case.name})", RETURNS_TEAM, "Open Dispatch Case and fill returned_qty for each item.", "returns_inspection_task", doc.dispatch_case, case.customer)
        # Copy pickup photo from Pack task to Returns task
        pack_task_name = case.pack_task
        if pack_task_name and ret_tid:
            pack_photo = frappe.db.get_value("Task", pack_task_name, "warehouse_pickup_photo")
            if pack_photo:
                frappe.db.set_value("Task", ret_tid, "custom_delivery_photo", pack_photo, update_modified=False)

    # Order Entry task Completed - create Pack task
    if is_completing and doc.task_kind == "Order entry":
        case.reload()
        items_txt = "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in case.case_items)
        make_task("Pack / prepare items", f"Pack: {short_customer(case.customer)} ({case.name})", INVENTORY_TEAM, f"Pack for {case.customer}\n\n{items_txt}", "pack_task", doc.dispatch_case, case.customer)

    # Pack task Completed
    if is_completing and doc.task_kind == "Pack / prepare items":
        case.reload()
        se = create_se(MAIN_WH, DELIVERY_TRANSIT_WH, all_items(case))
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Packed", "dispatch_stock_entry": se.name if se else ""})
        items_txt = "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in case.case_items)
        make_task("Delivery", f"Deliver: {short_customer(case.customer)} ({case.name})", DELIVERY_TEAM, f"Deliver to {case.customer}\nDest: {case.client_location_warehouse}\n\n{items_txt}", "delivery_task", doc.dispatch_case, case.customer)

    # Return Call Completed
    if is_completing and doc.task_kind == "Return Call":
        case.reload()
        if case.status == "Awaiting Return Pickup":
            driver = doc.return_pickup_driver or DELIVERY_TEAM
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Return Pickup Scheduled")
            items_txt = "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in case.case_items)
            tid = make_task("Pickup Returns", f"Pickup Returns: {short_customer(case.customer)} ({case.name})", driver, f"Collect from {case.customer}\nAt: {case.client_location_warehouse}\n\n{items_txt}", "return_pickup_task", doc.dispatch_case, case.customer)
            if doc.scheduled_return_date and tid:
                frappe.db.set_value("Task", tid, "exp_end_date", doc.scheduled_return_date)

    # Returns Inspection Completed
    if is_completing and doc.task_kind == "Returns processing / verification":
        case.reload()
        u = used_items(case)
        if u:
            c_se = create_se(case.client_location_warehouse, "", u, "Material Issue")
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "consumption_stock_entry", c_se.name if c_se else "")
        create_invoice(case)
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Invoice Pending")
        make_task("Invoice preparation / create invoice", f"Invoice: {short_customer(case.customer)} ({case.name})", ACCOUNTING_TEAM, f"Review draft invoice for {case.name}.", "invoice_task", doc.dispatch_case, case.customer)
        u = used_items(case)
        r = returned_items(case)
        if r:
            used_txt = "\n".join(f"- {ic} x{q}" for ic, q, sn, bn in u) if u else "None"
            ret_txt = "\n".join(f"- {ic} x{q}" for ic, q, sn, bn in r)
            make_task("Returns restocking", f"Restock returns: {short_customer(case.customer)} ({case.name})", RETURNS_TEAM, f"Used items:\n{used_txt}\n\nReturned items to restock:\n{ret_txt}", "restock_task", doc.dispatch_case, case.customer)
    # Restock task Completed
    if is_completing and doc.task_kind == "Returns restocking":
        case.reload()
        r = returned_items(case)
        if r:
            se = create_se(RETURNS_WH, MAIN_WH, r)
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "restock_stock_entry", se.name if se else "")

    # Invoice Preparation Completed
    if is_completing and doc.task_kind == "Invoice preparation / create invoice":
        case.reload()
        inv_name = case.sales_invoice
        if inv_name:
            inv_total = frappe.db.get_value("Sales Invoice", inv_name, "grand_total") or 0
            outstanding = inv_total - (case.prepaid_amount or 0)
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"total_invoice_amount": inv_total, "outstanding_amount": outstanding})
            if outstanding <= 0:
                frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Closed")
            else:
                frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Payment Pending")
                create_or_update_debt_task(case, outstanding, inv_name)

    # Discount Approval Completed
    if is_completing and doc.task_kind == "Discount Approval":
        if doc.approval_outcome == "Approved":
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Confirmed", "discount_approval_status": "Approved"})
            case.reload()
            items_txt = "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in case.case_items)
            make_task("Pack / prepare items", f"Pack: {short_customer(case.customer)} ({case.name})", INVENTORY_TEAM, f"Pack for {case.customer}\n\n{items_txt}", "pack_task", doc.dispatch_case, case.customer)
        else:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Draft", "discount_approval_status": "Rejected"})
            make_task("Order entry", f"Discount rejected - {short_customer(case.customer)}", ORDER_CREATION_TEAM, "Discount rejected by Directors. Open Dispatch Case, fix prices, save again.", None, doc.dispatch_case, case.customer)
