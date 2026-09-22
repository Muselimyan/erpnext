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
# Holding bucket for units whose disposition is undecided -- lost or damaged,
# awaiting a Director decision to bill the client or write them off. It is an
# accounting location, not a shelf: a lost unit does not physically exist, and
# `lost_damaged_presence` on the row records which it is. The warehouse is
# emptied by the resolution, so the fiction is bounded.
LOST_DAMAGED_WH = "Lost & Damaged - Inmed"
WRITEOFF_EXPENSE_ACCOUNT = "Stock Adjustment - Inmed"

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

    # expense_account defaults to COGS so every pre-existing call site behaves
    # exactly as before. A write-off overrides it with Stock Adjustment: a lost
    # or scrapped unit is not a cost of goods SOLD, and posting it to COGS would
    # distort the very margin figures the profit rework (A1) exists to correct.
    #
    # source_task stamps the Task that caused the movement. Two reasons: nothing
    # previously connected a Stock Entry back to the work that produced it, and
    # the lost/damaged resolution needs it as an idempotency key -- an already
    # resolved approval is recognised by the Stock Entry carrying its name.
    #
    # strict=1 runs the movement with ERPNext's own validation intact: no
    # ignore_validate, no ignore_stock_validation, no allow_zero_valuation_rate.
    #
    # It exists because the lost/damaged path cannot work without it. Verification
    # proved the point: ignore_validate skips set_basic_rate, so a transfer
    # arrives valued at ZERO regardless of what the source was worth. The units
    # therefore reached Lost & Damaged with no value and the write-off had nothing
    # to write off. Item A2 does not merely make these amounts untrustworthy --
    # on this path it makes a real write-off impossible.
    #
    # Used by the three lost/damaged movements only. Every other call site keeps
    # the old lenient behaviour until A2 is done properly, because those have
    # legacy data behind them and this does not.
    def create_se(src_wh, tgt_wh, items, purpose="Material Transfer", expense_account="Cost of Goods Sold - Inmed", source_task="", strict=0):
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
                "expense_account": expense_account,
                "cost_center": "Main - Inmed",
                "allow_zero_valuation_rate": 0 if strict else 1
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
        se_doc = {"doctype": "Stock Entry", "stock_entry_type": purpose, "purpose": purpose, "company": "InMED", "items": se_items}
        if source_task:
            se_doc["source_task"] = source_task
        se = frappe.get_doc(se_doc)
        se.flags.ignore_permissions = True
        if not strict:
            se.flags.ignore_validate = True
            frappe.flags.ignore_stock_validation = True
        se.insert()
        se.submit()
        if not strict:
            frappe.flags.ignore_stock_validation = False
        return se

    def all_items(c):
        return [(r.item_code, r.dispatched_qty, r.serial_no, r.batch_no) for r in (c.case_items or [])]

    def used_items(c):
        return [(r.item_code, r.used_qty, r.serial_no, r.batch_no) for r in (c.case_items or []) if (r.used_qty or 0) > 0]

    def returned_items(c):
        return [(r.item_code, r.returned_qty, r.serial_no, r.batch_no) for r in (c.case_items or []) if (r.returned_qty or 0) > 0]

    def lost_items(c):
        return [(r.item_code, r.lost_damaged_qty, r.serial_no, r.batch_no) for r in (c.case_items or []) if (r.lost_damaged_qty or 0) > 0]

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

    # NOTE: create_or_update_debt_task() has been removed entirely.
    #
    # It did two things, and both were wrong.
    #
    # It appended an invoice row to an EXISTING Debt Collection task and
    # recomputed that task's running total. That cross-task save was C1: an
    # Ops - Accounting user completing Invoice Preparation was judged against
    # Debt Collection's allowed roles (Ops - Finance / Ops - Directors) and
    # refused, so no repeat customer's invoice task could be completed by the
    # team that owns it. W2 removed the storage, leaving nothing to append.
    #
    # It also created a Debt Collection task the instant an invoice was raised.
    # That made sense only while invoices had no due date -- and they had none
    # because no payment terms were ever applied, so due_date always equalled
    # posting_date. Now that W6 applies Net 30, chasing a customer on day zero
    # is noise: they have thirty days to pay.
    #
    # Collection episodes are raised by Scheduled-debt-collection-episodes once
    # an invoice is actually overdue, or the customer's threshold is breached,
    # or a previous episode's follow-up date arrives. The case still moves to
    # Payment Pending here; chasing begins when there is something to chase.

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
        # Segregate lost and damaged units out of Returns.
        #
        # The return pickup moves the full DISPATCHED quantity back, so Returns
        # receives everything and only used and returned leave it. Without this
        # transfer the lost/damaged remainder is stranded there indefinitely,
        # mixed in with good sellable returns and indistinguishable from them.
        # With it, Returns balances exactly:
        #   dispatched = used (issued) + lost/damaged (moved) + returned (restocked)
        #
        # This is a Material TRANSFER, not an issue: value stays on the balance
        # sheet because the disposition is still undecided. The stock moves at
        # inspection rather than at approval deliberately -- physical truth must
        # not wait for a signature, which is the mistake prepaid_amount made.
        lost = lost_items(case)
        if lost:
            ld_se = create_se(RETURNS_WH, LOST_DAMAGED_WH, lost, "Material Transfer", "Cost of Goods Sold - Inmed", doc.name, 1)
            lost_lines = []
            for row in (case.case_items or []):
                if (row.lost_damaged_qty or 0) > 0:
                    presence = row.get("lost_damaged_presence") or "not recorded"
                    lost_lines.append(f"- {row.item_code} x{row.lost_damaged_qty} ({presence})")
            # make_task dedupes on an open task of the same kind for this case,
            # so re-completing the inspection cannot stack approvals.
            make_task(
                "Write-off Approval",
                f"Lost/damaged: {short_customer(case.customer)} ({case.name})",
                team_map.get("Write-off Approval", ""),
                "Decide what happens to these units. They are held in "
                + LOST_DAMAGED_WH + " pending your decision.\n\n"
                + "\n".join(lost_lines)
                + "\n\nSet Write-off Outcome to 'Bill Client' to invoice them, or "
                + "'Write Off' to absorb the loss. Either way the stock leaves "
                + LOST_DAMAGED_WH + " when you complete this task.",
                "", doc.dispatch_case, case.customer, source_task=doc.name, parent_task=doc.name,
            )
            print(f"[Dispatch] {frappe.utils.now()} case={case.name} lost/damaged segregated se={ld_se.name if ld_se else None} rows={len(lost)}")

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
            # Written through doc.save(), NOT frappe.db.set_value.
            #
            # set_value writes straight to the table: no validation, no hooks,
            # and no `tabVersion` row. Every financial field on this doctype was
            # maintained that way, so there was no record of who changed a money
            # figure, when, or from what -- on the one doctype where that
            # question matters most. A save produces version history naming the
            # user.
            #
            # The case is submitted by this point, so this runs
            # before_update_after_submit and is seen by
            # Dispatch-Case-before-save-submitted-access-control. All three
            # fields are in that gate's SYSTEM_FIELDS, so it is recognised as
            # bookkeeping and allowed without anyone holding a task.
            fin_case = frappe.get_doc("Dispatch Case", doc.dispatch_case)
            fin_case.total_invoice_amount = float(inv.grand_total or 0)
            fin_case.outstanding_amount = outstanding
            fin_case.sales_invoice = inv.name
            fin_case.flags.ignore_permissions = True
            fin_case.save()
            if outstanding <= 0:
                frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Closed")
                print(f"[Dispatch] {frappe.utils.now()} case={doc.dispatch_case} fully settled at invoice time, closed")
            else:
                frappe.db.set_value("Dispatch Case", doc.dispatch_case, "status", "Payment Pending")
                print(f"[Dispatch] {frappe.utils.now()} case={doc.dispatch_case} outstanding={outstanding}, awaiting payment (collection episodes are raised once overdue)")

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

    # Write-off Approval Completed -- resolve the held lost/damaged units.
    #
    # This handler lives here rather than in its own script because it needs
    # create_se, which is a nested function in this file. RestrictedPython has no
    # module system and forbids a function calling a sibling, so the alternative
    # would be duplicating the whole Stock Entry builder.
    #
    # Either outcome empties LOST_DAMAGED_WH of this case's units. The only
    # difference is where the value goes: to a client (revenue + COGS) or to the
    # company (write-off expense).
    if is_completing and doc.task_kind == "Write-off Approval":
        case.reload()
        lost = lost_items(case)
        # .get() rather than attribute access -- a Frappe Document raises
        # AttributeError for an unknown fieldname, so reading it directly would
        # break every Write-off Approval save if this script were ever deployed
        # ahead of the custom field.
        writeoff_outcome = doc.get("writeoff_outcome") or ""
        # Both branches move stock, so an already-resolved approval is recognised
        # by the Stock Entry stamped with this task. Previously only the billing
        # branch was guarded (by Sales Invoice.source_task) and the write-off
        # branch relied on nothing but the edge-triggered save -- one branch
        # defended by design, the other only by circumstance.
        prior_se = frappe.get_all(
            "Stock Entry",
            filters={"source_task": doc.name, "docstatus": ["!=", 2]},
            fields=["name"],
            limit_page_length=1,
        )
        if not lost:
            print(f"[Dispatch] {frappe.utils.now()} writeoff {doc.name} case={doc.dispatch_case} has no lost/damaged rows, nothing to resolve")
        elif prior_se:
            print(f"[Dispatch] {frappe.utils.now()} writeoff {doc.name} already resolved by se={prior_se[0].name}, skipping")
        elif writeoff_outcome == "Bill Client":
            # Idempotency is keyed on source_task, so completing this task twice
            # cannot raise a second invoice. The used-items invoice for the same
            # case is keyed on its own task and is unaffected.
            already = frappe.get_all(
                "Sales Invoice",
                filters={"source_task": doc.name, "docstatus": ["!=", 2]},
                fields=["name"],
                limit_page_length=1,
            )
            if already:
                print(f"[Dispatch] {frappe.utils.now()} writeoff {doc.name} already invoiced as {already[0].name}")
            else:
                ld_rows = []
                unpriced = []
                for row in (case.case_items or []):
                    qty = float(row.lost_damaged_qty or 0)
                    if qty <= 0:
                        continue
                    rate = float(row.unit_price or 0) * (1 - float(row.discount_pct or 0) / 100)
                    if rate <= 0:
                        unpriced.append(row.item_code or "Unknown")
                        continue
                    ld_rows.append({"item_code": row.item_code, "qty": qty, "rate": rate})
                if unpriced:
                    frappe.throw("These lost/damaged products have no price and cannot be billed: "
                                 + ", ".join(unpriced)
                                 + ". Set an Item Price, or choose Write Off instead.")
                cust = frappe.get_doc("Customer", case.customer)
                ld_hospital = cust.name if (cust.get("client_kind") or "") == "Hospital" else (cust.get("hospital") or "")
                si_doc = {
                    "doctype": "Sales Invoice",
                    "customer": case.customer,
                    "company": "InMED",
                    "currency": "AMD",
                    "update_stock": 0,
                    "dispatch_case": case.name,
                    "source_task": doc.name,
                    "items": ld_rows,
                }
                if ld_hospital:
                    si_doc["hospital"] = ld_hospital
                if cust.get("doctor_name"):
                    si_doc["doctor_name"] = cust.get("doctor_name")
                if frappe.db.exists("Sales Taxes and Charges Template", "Armenia Tax - Inmed"):
                    si_doc["taxes_and_charges"] = "Armenia Tax - Inmed"
                if frappe.db.exists("Payment Terms Template", "Net 30"):
                    si_doc["payment_terms_template"] = "Net 30"
                ld_si = frappe.get_doc(si_doc)
                ld_si.flags.ignore_permissions = True
                ld_si.insert()
                # Setting taxes_and_charges alone does not populate the tax rows;
                # the template has to be expanded. Same trap as W6.
                if si_doc.get("taxes_and_charges") and not ld_si.taxes:
                    for t in (frappe.get_all("Sales Taxes and Charges",
                                             filters={"parent": "Armenia Tax - Inmed", "parenttype": "Sales Taxes and Charges Template"},
                                             fields=["charge_type", "account_head", "rate", "description", "cost_center", "included_in_print_rate"],
                                             order_by="idx asc", limit_page_length=0) or []):
                        ld_si.append("taxes", {
                            "charge_type": t.charge_type, "account_head": t.account_head,
                            "rate": t.rate, "description": t.description,
                            "cost_center": t.cost_center,
                            "included_in_print_rate": t.included_in_print_rate,
                        })
                    ld_si.flags.ignore_permissions = True
                    ld_si.save()
                ld_si.flags.ignore_permissions = True
                ld_si.submit()
                # Billed, therefore sold: the stock leaves at COGS like any sale.
                out_se = create_se(LOST_DAMAGED_WH, "", lost, "Material Issue", "Cost of Goods Sold - Inmed", doc.name, 1)
                print(f"[Dispatch] {frappe.utils.now()} writeoff {doc.name} case={case.name} BILLED invoice={ld_si.name} total={ld_si.grand_total} se={out_se.name if out_se else None}")
        elif writeoff_outcome == "Write Off":
            # Absorbed by the company. Posted to Stock Adjustment rather than
            # COGS: these units were never sold, and routing them through cost of
            # goods sold would silently worsen gross margin on real sales.
            #
            # Refuse un-valued stock. This is the one operation whose entire
            # purpose IS the GL amount: everywhere else item A2's
            # allow_zero_valuation_rate makes a number wrong, but here it would
            # book a zero-value loss and report success, recognising nothing.
            # Checked explicitly against the bin as well as running strict, because
            # a zero here means the segregation transfer lost the valuation on the
            # way in and the loss would silently book nothing. Better to refuse and
            # say why than to record a loss of zero.
            unvalued = []
            for ic, q, sn, bn in lost:
                vrate = frappe.db.get_value("Bin", {"item_code": ic, "warehouse": LOST_DAMAGED_WH}, "valuation_rate")
                if not vrate or float(vrate) <= 0:
                    unvalued.append(ic)
            if unvalued:
                frappe.throw("These products have no stock valuation, so writing them off would "
                             "record a loss of zero: " + ", ".join(unvalued)
                             + ". Fix the item valuation first, or choose Bill Client instead.")
            out_se = create_se(LOST_DAMAGED_WH, "", lost, "Material Issue", WRITEOFF_EXPENSE_ACCOUNT, doc.name, 1)
            print(f"[Dispatch] {frappe.utils.now()} writeoff {doc.name} case={case.name} WRITTEN OFF se={out_se.name if out_se else None} expense={WRITEOFF_EXPENSE_ACCOUNT}")
        else:
            # No silent third path. Without this the task would complete, nothing
            # would move, and the units would sit in Lost & Damaged with no open
            # task pointing at them -- exactly the stranding A3 exists to remove,
            # reintroduced one layer further along. The before-save gate also
            # requires an outcome, but that is a different script, and the whole
            # reason W1 exists is that rules split across scripts drift apart.
            # Throwing here rolls the completion back, so the task stays open.
            frappe.throw("Cannot resolve these lost/damaged units: the Write-off Outcome is '"
                         + str(writeoff_outcome) + "', which is not Bill Client or Write Off. "
                         "Choose one before completing -- otherwise the stock stays in "
                         + LOST_DAMAGED_WH + " with nothing tracking it.")
