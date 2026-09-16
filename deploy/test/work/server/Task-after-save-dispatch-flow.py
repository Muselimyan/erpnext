# Name: Task-after-save-dispatch-flow
# Type: DocType Event
# DocType: Task
# Event: After Save
# Disabled: 0
# ---

COMPANY = "InMED"
MAIN_WH = "Main - Inmed"
DELIVERY_TRANSIT_WH = "Delivery In-Transit - Inmed"
RETURN_PICKUP_TRANSIT_WH = "Return Pickup In-Transit - Inmed"
RETURNS_WH = "Returns - Inmed"

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

    # Read team user mappings from Task Access Policy (single source of truth)
    team_map = {}
    for p in frappe.get_all("Task Access Policy", fields=["name", "default_team_user"], limit_page_length=0):
        if p.default_team_user:
            team_map[p.name] = p.default_team_user

    print(f"[Dispatch] {frappe.utils.now()} task={doc.name} kind={doc.task_kind} dc={doc.dispatch_case} completing={is_completing} ds_changed={ds_changed} ps_changed={ps_changed} team_map_entries={len(team_map)}")

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

    # parent_task passed explicitly — doc is NOT available inside def bodies after
    # nested insert() calls corrupt the RestrictedPython scope.
    def make_task(kind, subject, assignee, desc="", link_field=None, dispatch_case_name=None, customer=None, source_task=None, parent_task=""):
        dc_name = dispatch_case_name or ""
        cust = customer or frappe.db.get_value("Dispatch Case", dc_name, "customer")
        existing = frappe.db.exists("Task", {"dispatch_case": dc_name, "task_kind": kind, "status": ["not in", ["Completed", "Cancelled"]]})
        if existing:
            print(f"[Dispatch] {frappe.utils.now()} task={parent_task} skipped: kind={kind} dc={dc_name} existing={existing}")
            return existing
        t = frappe.get_doc({
            "doctype": "Task", "subject": subject, "task_kind": kind, "task_access_policy": kind,
            "dispatch_case": dc_name, "customer": cust, "description": desc,
        })
            # Check if source task specified next-task assignment
        if source_task:
            next_user = frappe.db.get_value("Task", source_task, "custom_next_task_assign_to")
            if next_user:
                assignee = next_user
        t.custom_assigned_to = assignee
    
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
        print(f"[Dispatch] {frappe.utils.now()} task={parent_task} created: kind={kind} new_task={t.name} assignee={assignee} dc={dc_name}")
        return t.name

    # NOTE: create_invoice() has been removed.
    #
    # A draft Sales Invoice used to be created here, automatically, the moment
    # goods were delivered or returns were inspected. Two problems followed:
    #
    #   - When no line qualified -- the client returned everything unused, a
    #     routine outcome -- it returned without creating anything, yet the
    #     caller created the Invoice Preparation task regardless. That task's
    #     gate demands a submitted invoice, so it could never be completed by
    #     anyone, including an Administrator. (Group 11 G1.)
    #   - It priced lines from whatever was on the case with no tender
    #     awareness, so a tender-covered invoice was refused at submission and
    #     the task deadlocked after the goods had already shipped. (C2.)
    #
    # The invoice is now built and submitted in one deliberate action by
    # task_commit_invoice, called from the Invoice Preparation task, with
    # task_close_case_nothing_to_invoice as the explicit alternative when there
    # is nothing to bill.

    def create_or_update_debt_task(c, outstanding, inv_name, team_user):
        # Ensures ONE open Debt Collection task exists for the customer, and
        # stores no balances on it.
        #
        # This function used to append an invoice row to an EXISTING debt task
        # and recompute its running total. That save was the cross-task write
        # behind C1: an Ops - Accounting user completing Invoice Preparation was
        # judged against Debt Collection's allowed roles (Ops - Finance /
        # Ops - Directors) and refused, so no repeat customer's invoice task
        # could be completed by the team that owns it.
        #
        # There is nothing to append any more. What the customer owes is read
        # live from the ledger by the task_debt_panel API, so an existing task
        # already covers every invoice for that customer, including this one.
        # The cross-task write is therefore not permitted-around, it is gone.
        existing = frappe.db.get_value("Task", {"customer": c.customer, "task_kind": "Debt Collection", "status": ["not in", ["Completed", "Cancelled"]]}, "name")
        if existing:
            print(f"[Dispatch] {frappe.utils.now()} debt task {existing} already open for {c.customer}, nothing to store")
            return existing
        t = frappe.get_doc({
            "doctype": "Task", "subject": f"Debt Collection: {c.customer}",
            "task_kind": "Debt Collection", "task_access_policy": "Debt Collection",
            "customer": c.customer,
        })
        t.flags.ignore_permissions = True
        t.insert()
        # FIXED: Update _assign via db (assign_to module not available in RestrictedPython)
        frappe.db.set_value("Task", t.name, "_assign", json.dumps([team_user]))
        todo = frappe.new_doc("ToDo")
        todo.status = "Open"
        todo.allocated_to = team_user
        todo.reference_type = "Task"
        todo.reference_name = t.name
        todo.description = t.subject
        todo.assigned_by = frappe.session.user
        todo.flags.ignore_permissions = True
        todo.insert()
        print(f"[Dispatch] {frappe.utils.now()} created debt task {t.name} for {c.customer}")
        return t.name

    case = frappe.get_doc("Dispatch Case", doc.dispatch_case)

    # Delivery: Picked Up
    if ds_changed and doc.delivery_status == "Picked Up":
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "In Transit")

    # Delivery: Delivered
    if ds_changed and doc.delivery_status == "Delivered":
        se = create_se(DELIVERY_TRANSIT_WH, case.client_location_warehouse, all_items(case))
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Delivered", "delivery_stock_entry": se.name if se else ""})
        case.reload()
        if not case.return_expected:
            c_se = create_se(case.client_location_warehouse, "", all_items(case), "Material Issue")
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"consumption_stock_entry": c_se.name if c_se else "", "status": "Invoice Pending"})
            make_task("Invoice preparation / create invoice", f"Invoice: {short_customer(case.customer)} ({case.name})", team_map.get("Invoice preparation / create invoice", ""), f"Review the products, then use Create & Submit Invoice on this task for {case.name}.", "invoice_task", doc.dispatch_case, case.customer, source_task=doc.name, parent_task=doc.name)
        else:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Awaiting Return Pickup")
            make_task("Return Call", f"Return call: {short_customer(case.customer)} ({case.name})", team_map.get("Return Call", ""), f"Waiting for {case.customer} to call regarding return pickup. Fill in details and assign to driver.", "return_waiting_task", doc.dispatch_case, case.customer, source_task=doc.name, parent_task=doc.name)

    # Return Pickup: Picked Up
    if ps_changed and doc.pickup_status == "Picked Up":
        case.reload()
        se = create_se(case.client_location_warehouse, RETURN_PICKUP_TRANSIT_WH, all_items(case))
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Return In Transit", "return_pickup_stock_entry": se.name if se else ""})

    # Return Pickup: Returned to Warehouse
    if ps_changed and doc.pickup_status == "Returned to Warehouse":
        se = create_se(RETURN_PICKUP_TRANSIT_WH, RETURNS_WH, all_items(case))
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Returns Received", "return_receive_stock_entry": se.name if se else ""})
        ret_tid = make_task("Returns processing / verification", f"Inspect returns: {short_customer(case.customer)} ({case.name})", team_map.get("Returns processing / verification", ""), "Open Dispatch Case and fill returned_qty for each item.", "returns_inspection_task", doc.dispatch_case, case.customer, source_task=doc.name, parent_task=doc.name)

    # Order Entry task Completed - create Pack task only if DC is submitted (no discount)
    if is_completing and doc.task_kind == "Order entry":
        case.reload()
        if case.docstatus == 1:
            items_txt = "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in case.case_items)
            make_task("Pack / prepare items", f"Pack: {short_customer(case.customer)} ({case.name})", team_map.get("Pack / prepare items", ""), f"Pack for {case.customer}\n\n{items_txt}", "pack_task", doc.dispatch_case, case.customer, source_task=doc.name, parent_task=doc.name)
        else:
            print(f"[Dispatch] DC {case.name} docstatus={case.docstatus}, Pack deferred (Awaiting Approval)")

    # Pack task Completed
    if is_completing and doc.task_kind == "Pack / prepare items":
        case.reload()
        se = create_se(MAIN_WH, DELIVERY_TRANSIT_WH, all_items(case))
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Packed", "dispatch_stock_entry": se.name if se else ""})
        items_txt = "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in case.case_items)
        make_task("Delivery", f"Deliver: {short_customer(case.customer)} ({case.name})", team_map.get("Delivery", ""), f"Deliver to {case.customer}\nDest: {case.client_location_warehouse}\n\n{items_txt}", "delivery_task", doc.dispatch_case, case.customer, source_task=doc.name, parent_task=doc.name)

    # Return Call Completed
    if is_completing and doc.task_kind == "Return Call":
        case.reload()
        if case.status == "Awaiting Return Pickup":
            driver = doc.return_pickup_driver or team_map.get("Pickup Returns", "")
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Return Pickup Scheduled")
            items_txt = "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in case.case_items)
            tid = make_task("Pickup Returns", f"Pickup Returns: {short_customer(case.customer)} ({case.name})", driver, f"Collect from {case.customer}\nAt: {case.client_location_warehouse}\n\n{items_txt}", "return_pickup_task", doc.dispatch_case, case.customer, source_task=doc.name, parent_task=doc.name)
            if doc.scheduled_return_date and tid:
                frappe.db.set_value("Task", tid, "exp_end_date", doc.scheduled_return_date)

    # Returns Inspection Completed
    if is_completing and doc.task_kind == "Returns processing / verification":
        case.reload()
        u = used_items(case)
        if u:
            c_se = create_se(RETURNS_WH, "", u, "Material Issue")
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "consumption_stock_entry", c_se.name if c_se else "")
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Invoice Pending")
        make_task("Invoice preparation / create invoice", f"Invoice: {short_customer(case.customer)} ({case.name})", team_map.get("Invoice preparation / create invoice", ""), f"Review the used quantities, then use Create & Submit Invoice on this task for {case.name}. If nothing was used, use Nothing to Invoice.", "invoice_task", doc.dispatch_case, case.customer, source_task=doc.name, parent_task=doc.name)
        u = used_items(case)
        r = returned_items(case)
        if r:
            used_txt = "\n".join(f"- {ic} x{q}" for ic, q, sn, bn in u) if u else "None"
            ret_txt = "\n".join(f"- {ic} x{q}" for ic, q, sn, bn in r)
            make_task("Returns restocking", f"Restock returns: {short_customer(case.customer)} ({case.name})", team_map.get("Returns restocking", ""), f"Used items:\n{used_txt}\n\nReturned items to restock:\n{ret_txt}", "restock_task", doc.dispatch_case, case.customer, source_task=doc.name, parent_task=doc.name)
    # Restock task Completed
    if is_completing and doc.task_kind == "Returns restocking":
        case.reload()
        r = returned_items(case)
        if r:
            se = create_se(RETURNS_WH, MAIN_WH, r)
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, "restock_stock_entry", se.name if se else "")

    # Invoice Preparation Completed
    if is_completing and doc.task_kind == "Invoice preparation / create invoice":
        # The invoice is found by querying Sales Invoice.dispatch_case, not by
        # reading Dispatch Case.sales_invoice. That link is only a convenience
        # pointer now: it went stale whenever an invoice was cancelled and
        # amended, because the amendment is a NEW document with a new name,
        # leaving the case pointing at the cancelled one and its gate refusing
        # to let the task finish. An amendment carries dispatch_case forward, so
        # querying that way survives Cancel + Amend.
        submitted = frappe.get_all(
            "Sales Invoice",
            filters={"dispatch_case": doc.dispatch_case, "docstatus": 1},
            fields=["name", "grand_total", "outstanding_amount"],
            order_by="creation desc",
            limit_page_length=0,
        )
        if submitted:
            inv = submitted[0]
            # Outstanding comes from the invoice, which already nets off any
            # advance applied at commit time. It is no longer computed as
            # grand_total minus a separately stored prepaid figure -- that
            # subtraction happened once, at a fixed moment, so an advance
            # recorded afterwards was never reflected and the case showed a
            # balance the ledger disagreed with.
            outstanding = float(inv.outstanding_amount or 0)
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, {
                "total_invoice_amount": float(inv.grand_total or 0),
                "outstanding_amount": outstanding,
                "sales_invoice": inv.name,
            })
            if outstanding <= 0:
                frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Closed")
                print(f"[Dispatch] {frappe.utils.now()} case={doc.dispatch_case} fully settled at invoice time, closed")
            else:
                frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Payment Pending")
                create_or_update_debt_task(case, outstanding, inv.name, team_map.get("Debt Collection", ""))

    # Discount Approval Completed
    if is_completing and doc.task_kind == "Discount Approval":
        if doc.approval_outcome == "Approved":
            dc_doc = frappe.get_doc("Dispatch Case", doc.dispatch_case)
            dc_doc.status = "Confirmed"
            dc_doc.discount_approval_status = "Approved"
            dc_doc.flags.ignore_permissions = True
            dc_doc.submit()
            dc_doc.reload()
            items_txt = "\n".join(f"- {r.item_code} x{r.dispatched_qty}" for r in dc_doc.case_items)
            make_task("Pack / prepare items", f"Pack: {short_customer(dc_doc.customer)} ({dc_doc.name})", team_map.get("Pack / prepare items", ""), f"Pack for {dc_doc.customer}\n\n{items_txt}", "pack_task", doc.dispatch_case, dc_doc.customer, source_task=doc.name, parent_task=doc.name)
            print(f"[Dispatch] Discount approved for DC {doc.dispatch_case}, submitted and Pack created")
        else:
            frappe.db.set_value("Dispatch Case", doc.dispatch_case, {"status": "Draft", "discount_approval_status": "Rejected"})
            make_task("Order entry", f"Discount rejected - {short_customer(case.customer)}", team_map.get("Order entry", ""), "Discount rejected by Directors. Open Dispatch Case, fix prices, save again.", None, doc.dispatch_case, case.customer, source_task=doc.name, parent_task=doc.name)
            print(f"[Dispatch] Discount rejected for DC {doc.dispatch_case}, new Order Entry created")
