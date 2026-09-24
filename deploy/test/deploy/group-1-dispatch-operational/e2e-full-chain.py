# ==============================================================
# END-TO-END: one Dispatch Case driven through the ENTIRE chain, in one run,
# each step performed by the role that really performs it.
#
# WHY THIS EXISTS. Every workstream so far verified its own hop with a seeded
# fixture -- a case placed directly into the state that hop begins from. That
# proves each hop, and proves nothing about the joins between them. This drives
# the real sequence and asserts at every seam:
#
#   Order entry  -> accept, add product via the API, complete
#   Pack         -> accept, scan, photo, complete
#   Delivery     -> accept, Picked Up, Delivered
#   Return Call  -> accept, complete
#   Pickup       -> accept, Picked Up, Returned to Warehouse + photo
#   Inspection   -> accept, record used/returned/lost, complete
#   Restocking   -> accept, photo, complete
#   Invoice prep -> accept, commit invoice, complete
#
# Nothing is short-circuited: tasks are accepted through dispatch_task_accept,
# products added through task_add_dispatch_product, quantities set through
# task_update_return_item_quantities, the invoice raised through
# task_commit_invoice. If a seam is broken, this fails where it breaks.
#
# THE CLOSING ASSERTION IS STOCK CONSERVATION. dispatched must equal
# used + returned + lost across the whole journey, and the transit warehouses
# must all return to where they started. A chain that moves stock correctly at
# every hop but loses a unit between two of them passes every other test in this
# directory and fails this one.
#
# Everything is rolled back.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-1-dispatch-operational\e2e-full-chain.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
#
# NOTE: single function, no blank lines in the body, users as parameters.
# ==============================================================
import frappe
import json
def e2e(ORDER_USER, INV_USER, DELIV_USER, RETURNS_USER, ACCT_USER):
    R = []
    MAIN = "Main - Inmed"
    DTRANSIT = "Delivery In-Transit - Inmed"
    RTRANSIT = "Return Pickup In-Transit - Inmed"
    RETWH = "Returns - Inmed"
    LDWH = "Lost & Damaged - Inmed"
    def ok(label, cond, detail=""):
        R.append((label, "PASS" if cond else "FAIL", str(detail)[:96]))
        return cond
    def bal(wh, item):
        return float(frappe.db.get_value("Bin", {"item_code": item, "warehouse": wh}, "actual_qty") or 0)
    def api(script, args, user):
        frappe.set_user(user)
        frappe.form_dict.clear()
        for k in args:
            frappe.form_dict[k] = args[k]
        frappe.response.pop("message", None)
        frappe.get_doc("Server Script", script).execute_method()
        m = frappe.response.get("message") or {}
        frappe.set_user("Administrator")
        return m
    def accept(task, user):
        return api("dispatch_task_accept", {"task_name": task}, user)
    def photo(task):
        f = frappe.get_doc({"doctype": "File", "file_name": "e2e.png", "file_url": "/files/e2e.png", "attached_to_doctype": "Task", "attached_to_name": task, "is_private": 0})
        f.name = "e2e-" + frappe.generate_hash("", 8)
        f.db_insert()
    def save_as(task, user, fields):
        frappe.set_user(user)
        t = frappe.get_doc("Task", task)
        for k in fields:
            t.set(k, fields[k])
        t.save()
        frappe.set_user("Administrator")
        return t
    def open_task(dc, kind):
        n = frappe.db.get_value("Task", {"dispatch_case": dc, "task_kind": kind, "status": ["not in", ["Completed", "Cancelled"]]}, "name")
        return n
    def dcstatus(dc):
        return frappe.db.get_value("Dispatch Case", dc, "status")
    try:
        frappe.set_user("Administrator")
        # ── fixture: a customer, a priced item with real stock, a client warehouse
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        item = None
        for b in frappe.get_all("Bin", filters={"warehouse": MAIN, "actual_qty": [">", 20]}, fields=["item_code", "actual_qty", "valuation_rate"], order_by="actual_qty desc", limit_page_length=80):
            if not b.valuation_rate or float(b.valuation_rate) <= 0:
                continue
            if frappe.db.get_value("Item Price", {"item_code": b.item_code, "price_list": "Standard Selling", "price_list_rate": [">", 0]}, "price_list_rate"):
                item = b.item_code
                break
        if not item:
            ok("FIXTURE priced item with >20 in Main", False, "none found")
            raise Exception("no usable item")
        wh = frappe.db.get_value("Warehouse", {"is_group": 0, "company": "InMED", "name": ["not in", [MAIN, DTRANSIT, RTRANSIT, RETWH, LDWH]]}, "name")
        start_main = bal(MAIN, item)
        start_dt = bal(DTRANSIT, item)
        start_rt = bal(RTRANSIT, item)
        start_ret = bal(RETWH, item)
        start_ld = bal(LDWH, item)
        start_cli = bal(wh, item)
        ok("FIXTURE item / stock / client warehouse", True, "{0} main={1} -> {2}".format(item, start_main, wh))
        # ══ 1. ORDER ENTRY ══════════════════════════════════════════════
        oe = frappe.get_doc({"doctype": "Task", "subject": "E2E order entry", "task_kind": "Order entry", "task_access_policy": "Order entry", "status": "Open", "custom_assigned_to": ORDER_USER})
        oe.flags.ignore_permissions = True
        oe.insert()
        acc = accept(oe.name, ORDER_USER)
        dc = frappe.db.get_value("Task", oe.name, "dispatch_case")
        ok("1 accept auto-creates a Draft Dispatch Case", bool(dc), dc)
        ok("1 case starts in Draft", dcstatus(dc) == "Draft", dcstatus(dc))
        m = api("task_add_dispatch_product", {"task_name": oe.name, "item_code": item, "qty": 10}, ORDER_USER)
        rows = frappe.get_all("Dispatch Case Item", filters={"parent": dc}, fields=["name", "unit_price"])
        ok("1 product added, price resolved server-side", len(rows) == 1 and float(rows[0].unit_price) > 0, "price={0}".format(rows[0].unit_price if rows else "-"))
        row = rows[0].name
        save_as(oe.name, ORDER_USER, {"customer": cust, "order_return_expected": 1, "order_client_location_warehouse": wh})
        save_as(oe.name, ORDER_USER, {"status": "Completed"})
        ok("1 completing Order entry SUBMITS the case", frappe.db.get_value("Dispatch Case", dc, "docstatus") == 1, "docstatus={0}".format(frappe.db.get_value("Dispatch Case", dc, "docstatus")))
        ok("1 case status is Confirmed", dcstatus(dc) == "Confirmed", dcstatus(dc))
        pack = open_task(dc, "Pack / prepare items")
        ok("1 -> 2 SEAM: Pack task was created", bool(pack), pack)
        # ══ 2. PACK ═════════════════════════════════════════════════════
        accept(pack, INV_USER)
        api("task_mark_item_packed", {"case_name": dc, "row_name": row, "packed": 1}, INV_USER)
        photo(pack)
        save_as(pack, INV_USER, {"status": "Completed"})
        ok("2 case status is Packed", dcstatus(dc) == "Packed", dcstatus(dc))
        se1 = frappe.db.get_value("Dispatch Case", dc, "dispatch_stock_entry")
        ok("2 Main -> Delivery transit entry created", bool(se1), se1)
        ok("2 Main balance fell by 10", bal(MAIN, item) == start_main - 10, "{0} -> {1}".format(start_main, bal(MAIN, item)))
        ok("2 Delivery transit rose by 10", bal(DTRANSIT, item) == start_dt + 10, "{0} -> {1}".format(start_dt, bal(DTRANSIT, item)))
        sles = frappe.get_all("Stock Ledger Entry", filters={"voucher_no": se1, "is_cancelled": 0}, fields=["actual_qty", "valuation_rate"], limit_page_length=0)
        inn = [s for s in sles if float(s.actual_qty) > 0]
        outt = [s for s in sles if float(s.actual_qty) < 0]
        ok("2 transfer preserved valuation", inn and outt and abs(float(inn[0].valuation_rate) - float(outt[0].valuation_rate)) < 0.01, "out {0} -> in {1}".format(outt[0].valuation_rate if outt else "-", inn[0].valuation_rate if inn else "-"))
        deliv = open_task(dc, "Delivery")
        ok("2 -> 3 SEAM: Delivery task was created", bool(deliv), deliv)
        # ══ 3. DELIVERY ═════════════════════════════════════════════════
        accept(deliv, DELIV_USER)
        save_as(deliv, DELIV_USER, {"delivery_status": "Picked Up"})
        ok("3 case status is In Transit", dcstatus(dc) == "In Transit", dcstatus(dc))
        save_as(deliv, DELIV_USER, {"delivery_status": "Delivered"})
        ok("3 Delivery task auto-completed", frappe.db.get_value("Task", deliv, "status") == "Completed", frappe.db.get_value("Task", deliv, "status"))
        ok("3 stock reached the client warehouse", bal(wh, item) == start_cli + 10, "{0} -> {1}".format(start_cli, bal(wh, item)))
        ok("3 Delivery transit returned to start", bal(DTRANSIT, item) == start_dt, "{0}".format(bal(DTRANSIT, item)))
        ok("3 returns expected -> Awaiting Return Pickup", dcstatus(dc) == "Awaiting Return Pickup", dcstatus(dc))
        rc = open_task(dc, "Return Call")
        ok("3 -> 4 SEAM: Return Call task was created", bool(rc), rc)
        # ══ 4. RETURN CALL ══════════════════════════════════════════════
        accept(rc, RETURNS_USER)
        save_as(rc, RETURNS_USER, {"return_pickup_driver": DELIV_USER, "scheduled_return_date": frappe.utils.add_days(frappe.utils.nowdate(), 1)})
        save_as(rc, RETURNS_USER, {"status": "Completed"})
        ok("4 case status is Return Pickup Scheduled", dcstatus(dc) == "Return Pickup Scheduled", dcstatus(dc))
        pk = open_task(dc, "Pickup Returns")
        ok("4 -> 5 SEAM: Pickup Returns task was created", bool(pk), pk)
        # ══ 5. PICKUP RETURNS ═══════════════════════════════════════════
        accept(pk, DELIV_USER)
        save_as(pk, DELIV_USER, {"pickup_status": "Picked Up"})
        ok("5 case status is Return In Transit", dcstatus(dc) == "Return In Transit", dcstatus(dc))
        ok("5 stock left the client warehouse", bal(wh, item) == start_cli, "{0}".format(bal(wh, item)))
        ok("5 return transit holds the goods", bal(RTRANSIT, item) == start_rt + 10, "{0} -> {1}".format(start_rt, bal(RTRANSIT, item)))
        photo(pk)
        save_as(pk, DELIV_USER, {"pickup_status": "Returned to Warehouse"})
        ok("5 case status is Returns Received", dcstatus(dc) == "Returns Received", dcstatus(dc))
        ok("5 return transit emptied", bal(RTRANSIT, item) == start_rt, "{0}".format(bal(RTRANSIT, item)))
        ok("5 Returns warehouse holds the goods", bal(RETWH, item) == start_ret + 10, "{0} -> {1}".format(start_ret, bal(RETWH, item)))
        insp = open_task(dc, "Returns processing / verification")
        ok("5 -> 6 SEAM: Inspection task was created", bool(insp), insp)
        # ══ 6. INSPECTION: 6 used, 3 returned, 1 lost ═══════════════════
        accept(insp, RETURNS_USER)
        api("task_update_return_item_quantities", {"case_name": dc, "row_name": row, "returned_qty": 3, "lost_damaged_qty": 1, "lost_damaged_presence": "Damaged - in hand"}, RETURNS_USER)
        used = float(frappe.db.get_value("Dispatch Case Item", row, "used_qty") or 0)
        ok("6 used computed as dispatched - returned - lost", used == 6, "used={0}".format(used))
        save_as(insp, RETURNS_USER, {"status": "Completed"})
        ok("6 case status is Invoice Pending", dcstatus(dc) == "Invoice Pending", dcstatus(dc))
        ok("6 used quantity was consumed out of Returns", bal(RETWH, item) == start_ret + 3, "{0} (want {1})".format(bal(RETWH, item), start_ret + 3))
        ok("6 lost/damaged segregated to Lost & Damaged", bal(LDWH, item) == start_ld + 1, "{0} -> {1}".format(start_ld, bal(LDWH, item)))
        wo = open_task(dc, "Write-off Approval")
        ok("6 SEAM: Write-off Approval raised for the loss", bool(wo), wo)
        rs = open_task(dc, "Returns restocking")
        ok("6 -> 7 SEAM: Restocking task was created", bool(rs), rs)
        inv = open_task(dc, "Invoice preparation / create invoice")
        ok("6 -> 8 SEAM: Invoice task was created", bool(inv), inv)
        # ══ 7. RESTOCKING ═══════════════════════════════════════════════
        accept(rs, RETURNS_USER)
        photo(rs)
        save_as(rs, RETURNS_USER, {"status": "Completed"})
        ok("7 returned goods went back to Main", bal(MAIN, item) == start_main - 10 + 3, "{0} (want {1})".format(bal(MAIN, item), start_main - 7))
        ok("7 Returns warehouse emptied", bal(RETWH, item) == start_ret, "{0}".format(bal(RETWH, item)))
        # ══ 8. INVOICE ══════════════════════════════════════════════════
        accept(inv, ACCT_USER)
        ci = api("task_commit_invoice", {"task_name": inv}, ACCT_USER)
        si = ci.get("sales_invoice") or frappe.db.get_value("Sales Invoice", {"dispatch_case": dc, "docstatus": 1}, "name")
        ok("8 invoice created and submitted", bool(si), si)
        if si:
            sidoc = frappe.get_doc("Sales Invoice", si)
            qty = sum([float(r.qty) for r in sidoc.items])
            ok("8 invoice bills the USED quantity only", qty == 6, "invoiced qty={0}".format(qty))
        save_as(inv, ACCT_USER, {"status": "Completed"})
        fin = dcstatus(dc)
        ok("8 case reached a terminal state", fin in ("Closed", "Payment Pending"), fin)
        # ══ 9. CONSERVATION ═════════════════════════════════════════════
        ok("9 client warehouse back to start", bal(wh, item) == start_cli, "{0}".format(bal(wh, item)))
        ok("9 both transit warehouses back to start", bal(DTRANSIT, item) == start_dt and bal(RTRANSIT, item) == start_rt, "dt={0} rt={1}".format(bal(DTRANSIT, item), bal(RTRANSIT, item)))
        ok("9 Returns back to start", bal(RETWH, item) == start_ret, "{0}".format(bal(RETWH, item)))
        ok("9 Lost & Damaged still holds the 1 unit", bal(LDWH, item) == start_ld + 1, "{0}".format(bal(LDWH, item)))
        net_main = start_main - bal(MAIN, item)
        ok("9 CONSERVATION: Main fell by used + lost = 7", net_main == 7, "Main fell by {0}, expected 7 (6 used + 1 lost)".format(net_main))
    except Exception as e:
        R.append(("CHAIN ABORTED", "FAIL", str(e)[:150]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("E2E_RESULTS_START")
    for n, v, d in R:
        print("E2E | {0:<48} | {1:<4} | {2}".format(n, v, d))
    npass = len([1 for x in R if x[1] == "PASS"])
    print("E2E | {0} passed / {1} total".format(npass, len(R)))
    print("E2E_RESULTS_END")
e2e("e2e.order.creating@test.erpnext.am", "e2e.inventory@test.erpnext.am", "e2e.delivery@test.erpnext.am", "e2e.returns@test.erpnext.am", "e2e.accounting@test.erpnext.am")
