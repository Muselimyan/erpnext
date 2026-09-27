# ==============================================================
# D11 VERIFY: the Dispatch Case cancellation flow, end to end.
# Design: deploy/test/work/cancel-flow-design.md (section 9 lists these).
#
# Every case is built through the REAL flow -- Order entry accepted through
# dispatch_task_accept, products added through the pricing endpoint, Pack
# completed with a photo so stock genuinely moves -- because a cancellation
# from Packed is only meaningful if the goods are actually in transit.
#
# The two full return chains are the heart of it: all returned, and one unit
# short. Stock is asserted in every warehouse at every step, and the case must
# stay Cancelled with no invoice task throughout.
#
# Refusals run inside savepoints: an API that throws mid-request would
# otherwise leave the console transaction in an unknown state.
#
# NOTE: single function, no blank lines in the body (IPython truncates a
# piped function at the first blank line), users as parameters.
#
# Everything rolls back.
# ==============================================================
import frappe
def d11(ORDER_USER, INV_USER, DELIV_USER, RETURNS_USER):
    R = []
    MAIN = "Main - Inmed"
    DT = "Delivery In-Transit - Inmed"
    RET = "Returns - Inmed"
    LD = "Lost & Damaged - Inmed"
    RW_KIND = "Return to warehouse (aborted delivery / cancelled order)"
    QTY = 3
    def ok(label, cond, detail=""):
        R.append((label, "PASS" if cond else "FAIL", str(detail)[:92]))
        return cond
    def bal(wh, item):
        return float(frappe.db.get_value("Bin", {"item_code": item, "warehouse": wh}, "actual_qty") or 0)
    def api(script, args, user):
        frappe.set_user(user)
        frappe.form_dict.clear()
        for k in args:
            frappe.form_dict[k] = args[k]
        frappe.response.pop("message", None)
        err = ""
        frappe.db.savepoint("d11call")
        try:
            frappe.get_doc("Server Script", script).execute_method()
        except Exception as e:
            err = str(e)[:300]
            frappe.db.rollback(save_point="d11call")
        m = frappe.response.get("message") or {}
        frappe.set_user("Administrator")
        return m, err
    def save_as(task, user, fields):
        frappe.set_user(user)
        err = ""
        frappe.db.savepoint("d11save")
        try:
            t = frappe.get_doc("Task", task)
            for k in fields:
                t.set(k, fields[k])
            t.save()
        except Exception as e:
            err = str(e)[:300]
            frappe.db.rollback(save_point="d11save")
        frappe.set_user("Administrator")
        return err
    def photo(task):
        f = frappe.get_doc({"doctype": "File", "file_name": "d11.png", "file_url": "/files/d11.png", "attached_to_doctype": "Task", "attached_to_name": task, "is_private": 0})
        f.name = "d11-" + frappe.generate_hash("", 8)
        f.db_insert()
    def open_task(dc, kind):
        return frappe.db.get_value("Task", {"dispatch_case": dc, "task_kind": kind, "status": ["not in", ["Completed", "Cancelled"]]}, "name")
    def st(dc):
        return frappe.db.get_value("Dispatch Case", dc, "status")
    def build(stage, cust, item, wh, discount=0):
        # Drive a real case to `stage`. Returns (case, order_entry_task, row).
        oe = frappe.get_doc({"doctype": "Task", "subject": "D11 order", "task_kind": "Order entry", "task_access_policy": "Order entry", "status": "Open", "custom_assigned_to": ORDER_USER})
        oe.flags.ignore_permissions = True
        oe.insert()
        api("dispatch_task_accept", {"task_name": oe.name}, ORDER_USER)
        dc = frappe.db.get_value("Task", oe.name, "dispatch_case")
        api("task_add_dispatch_product", {"task_name": oe.name, "item_code": item, "qty": QTY}, ORDER_USER)
        row = frappe.get_all("Dispatch Case Item", filters={"parent": dc}, fields=["name"])[0].name
        if discount:
            api("task_update_dispatch_product", {"case_name": dc, "row_name": row, "discount_pct": discount}, ORDER_USER)
        save_as(oe.name, ORDER_USER, {"customer": cust, "order_return_expected": 1, "order_client_location_warehouse": wh})
        if stage == "Draft":
            return dc, oe.name, row
        save_as(oe.name, ORDER_USER, {"status": "Completed"})
        if stage in ("Awaiting Approval", "Confirmed"):
            return dc, oe.name, row
        pack = open_task(dc, "Pack / prepare items")
        api("dispatch_task_accept", {"task_name": pack}, INV_USER)
        api("task_mark_item_packed", {"case_name": dc, "row_name": row, "packed": 1}, INV_USER)
        photo(pack)
        save_as(pack, INV_USER, {"status": "Completed"})
        if stage == "Packed":
            return dc, oe.name, row
        deliv = open_task(dc, "Delivery")
        api("dispatch_task_accept", {"task_name": deliv}, DELIV_USER)
        save_as(deliv, DELIV_USER, {"delivery_status": "Picked Up"})
        return dc, oe.name, row
    try:
        frappe.set_user("Administrator")
        # ── fixtures ─────────────────────────────────────────────────
        DIRECTOR = ""
        for hr in frappe.get_all("Has Role", filters={"role": "Ops - Directors", "parenttype": "User"}, fields=["parent"], limit_page_length=0):
            if (hr.parent or "").startswith("e2e.") and frappe.db.get_value("User", hr.parent, "enabled"):
                DIRECTOR = hr.parent
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        item = None
        for b in frappe.get_all("Bin", filters={"warehouse": MAIN, "actual_qty": [">", 40]}, fields=["item_code", "valuation_rate"], order_by="actual_qty desc", limit_page_length=80):
            if b.valuation_rate and float(b.valuation_rate) > 0 and frappe.db.get_value("Item Price", {"item_code": b.item_code, "price_list": "Standard Selling", "price_list_rate": [">", 0]}, "price_list_rate"):
                item = b.item_code
                break
        wh = frappe.db.get_value("Warehouse", {"is_group": 0, "company": "InMED", "name": ["not in", [MAIN, DT, RET, LD, "Return Pickup In-Transit - Inmed"]]}, "name")
        ok("FIXTURE director / customer / item / client wh", bool(DIRECTOR and cust and item and wh), "dir={0} item={1}".format(DIRECTOR, item))
        if not (DIRECTOR and cust and item and wh):
            raise Exception("fixture incomplete")
        # ══ S7 + S1: order-taker cancels their own Draft ═════════════════
        a, a_oe, a_row = build("Draft", cust, item, wh)
        ok("S1 Draft case built", st(a) == "Draft", st(a))
        m, e = api("dispatch_case_cancel", {"dispatch_case": a, "reason": "Entered in error"}, ORDER_USER)
        ok("S7 order-taker cancels own Draft", not e and st(a) == "Cancelled", e or st(a))
        ok("S4 Draft cancel closed the Order entry task", frappe.db.get_value("Task", a_oe, "status") == "Cancelled", frappe.db.get_value("Task", a_oe, "status"))
        desc = frappe.db.get_value("Task", a_oe, "description") or ""
        ok("S4 cancelled task carries the reason", "was cancelled by" in desc and "Entered in error" in desc, desc[-70:])
        ok("S4 case records reason / who / when", frappe.db.get_value("Dispatch Case", a, "cancellation_reason") == "Entered in error" and frappe.db.get_value("Dispatch Case", a, "cancelled_by") == ORDER_USER and bool(frappe.db.get_value("Dispatch Case", a, "cancelled_at")), frappe.db.get_value("Dispatch Case", a, "cancelled_by"))
        # ══ S7 + S1: order-taker cancels Awaiting Approval ═══════════════
        b, b_oe, b_row = build("Awaiting Approval", cust, item, wh, discount=5)
        ok("S1 Awaiting Approval case built", st(b) == "Awaiting Approval", st(b))
        da = open_task(b, "Discount Approval")
        m, e = api("dispatch_case_cancel", {"dispatch_case": b, "reason": "Customer cancelled"}, ORDER_USER)
        ok("S7 order-taker cancels in Awaiting Approval (their OE task is Completed)", not e and st(b) == "Cancelled", e or st(b))
        ok("S4 open Discount Approval was cancelled", (not da) or frappe.db.get_value("Task", da, "status") == "Cancelled", "da={0}".format(da))
        # ══ S7: a non-Director cannot cancel a submitted case ════════════
        c, c_oe, c_row = build("Confirmed", cust, item, wh)
        ok("S1 Confirmed case built", st(c) == "Confirmed", st(c))
        m, e = api("dispatch_case_cancel", {"dispatch_case": c, "reason": "Customer cancelled"}, ORDER_USER)
        ok("S7 order-taker refused once submitted", "Ops - Directors" in e and st(c) == "Confirmed", e[:70] or "ALLOWED")
        # an accepted Pack task gets the reshelving note
        c_pack = open_task(c, "Pack / prepare items")
        api("dispatch_task_accept", {"task_name": c_pack}, INV_USER)
        m, e = api("dispatch_case_cancel", {"dispatch_case": c, "reason": "Other"}, DIRECTOR)
        ok("S2 Other without a note refused", "Other" in e, e[:60] or "ALLOWED")
        main_before = bal(MAIN, item)
        m, e = api("dispatch_case_cancel", {"dispatch_case": c, "reason": "Other", "notes": "hospital merged two orders"}, DIRECTOR)
        ok("S1 Director cancels Confirmed", not e and st(c) == "Cancelled", e or st(c))
        ok("S4 accepted Pack task told to reshelve", "return them to the shelf" in (frappe.db.get_value("Task", c_pack, "description") or ""), "")
        ok("S9 Confirmed cancel: no Stock Entry", bal(MAIN, item) == main_before and not frappe.db.get_value("Dispatch Case", c, "dispatch_stock_entry"), "main {0}->{1}".format(main_before, bal(MAIN, item)))
        ok("S9 Confirmed cancel: no return task", not frappe.db.exists("Task", {"dispatch_case": c, "task_kind": RW_KIND}), "")
        # ══ S2: second cancellation refused ══════════════════════════════
        m, e = api("dispatch_case_cancel", {"dispatch_case": c, "reason": "Customer cancelled"}, DIRECTOR)
        ok("S2 second cancellation refused", "already cancelled" in e, e[:60] or "ALLOWED")
        # ══ S5: a cancelled task is final, even for Directors ════════════
        e = save_as(c_pack, DIRECTOR, {"status": "Open"})
        ok("S5 Director cannot reopen a cancelled task", "cancelled and cannot be modified" in e and frappe.db.get_value("Task", c_pack, "status") == "Cancelled", e[:60] or "REOPENED")
        # ══ S6: a document save cannot move a case into / out of Cancelled
        frappe.set_user(DIRECTOR)
        e6 = ""
        frappe.db.savepoint("d11s6")
        try:
            cd = frappe.get_doc("Dispatch Case", c)
            cd.status = "Confirmed"
            cd.save()
        except Exception as ex:
            e6 = str(ex)[:200]
            frappe.db.rollback(save_point="d11s6")
        frappe.set_user("Administrator")
        ok("S6 save cannot un-cancel a case", "cannot be reopened" in e6 and st(c) == "Cancelled", e6[:60] or "UNCANCELLED")
        g, g_oe, g_row = build("Confirmed", cust, item, wh)
        frappe.set_user(DIRECTOR)
        e6b = ""
        frappe.db.savepoint("d11s6b")
        try:
            gd = frappe.get_doc("Dispatch Case", g)
            gd.status = "Cancelled"
            gd.save()
        except Exception as ex:
            e6b = str(ex)[:200]
            frappe.db.rollback(save_point="d11s6b")
        frappe.set_user("Administrator")
        ok("S6 save cannot cancel a case around the API", "Cancel button" in e6b and st(g) == "Confirmed", e6b[:60] or "CANCELLED")
        # ══ S3: an invoice blocks cancellation, and is left alone ════════
        si = frappe.get_doc({"doctype": "Sales Invoice", "customer": cust, "company": "InMED", "dispatch_case": g, "posting_date": frappe.utils.nowdate(), "due_date": frappe.utils.nowdate(), "items": [{"item_code": item, "qty": 1, "rate": 100}]})
        si.flags.ignore_permissions = True
        si.insert()
        m, e = api("dispatch_case_cancel", {"dispatch_case": g, "reason": "Customer cancelled"}, DIRECTOR)
        ok("S3 hand-made draft invoice blocks cancel", "invoice" in e and st(g) == "Confirmed", e[:60] or "ALLOWED")
        ok("S3 that invoice was left untouched", frappe.db.exists("Sales Invoice", si.name) and frappe.db.get_value("Sales Invoice", si.name, "docstatus") == 0, si.name)
        # ══ S2: refusals after delivery say what to do instead ═══════════
        for fake, needle in (("Awaiting Return Pickup", "return flow"), ("Invoice Pending", "credit note"), ("Payment Pending", "credit note"), ("Closed", "closed")):
            frappe.db.set_value("Dispatch Case", g, "status", fake)
            m, e = api("dispatch_case_cancel", {"dispatch_case": g, "reason": "Customer cancelled"}, DIRECTOR)
            ok("S2 refused from {0}".format(fake), needle in e, e[:56] or "ALLOWED")
        frappe.db.set_value("Dispatch Case", g, "status", "Confirmed")
        # ══ S10 + S8 + S11 + S15: Packed -> full return, everything back ═
        start_main = bal(MAIN, item)
        start_dt = bal(DT, item)
        start_ret = bal(RET, item)
        e_, e_oe, e_row = build("Packed", cust, item, wh)
        ok("S1 Packed case built, stock in transit", st(e_) == "Packed" and bal(DT, item) == start_dt + QTY, "dt {0}->{1}".format(start_dt, bal(DT, item)))
        pe = frappe.get_doc({"doctype": "Payment Entry", "payment_type": "Receive", "party_type": "Customer", "party": cust, "paid_amount": 500, "received_amount": 500, "company": "InMED", "paid_to": "Cash - Inmed", "mode_of_payment": "Cash", "posting_date": frappe.utils.nowdate(), "reference_date": frappe.utils.nowdate(), "dispatch_case": e_})
        pe.flags.ignore_permissions = True
        pe.insert()
        pe.submit()
        m, e = api("dispatch_case_cancel", {"dispatch_case": e_, "reason": "Surgery cancelled or postponed"}, DIRECTOR)
        ok("S1 Director cancels Packed", not e and st(e_) == "Cancelled", e or st(e_))
        ok("S8 tagged advance released to general credit", not frappe.db.get_value("Payment Entry", pe.name, "dispatch_case"), frappe.db.get_value("Payment Entry", pe.name, "dispatch_case"))
        ok("S8 release recorded as a Comment on the payment", frappe.db.exists("Comment", {"reference_doctype": "Payment Entry", "reference_name": pe.name, "content": ["like", "%Released from " + e_ + "%"]}), "")
        rw = open_task(e_, RW_KIND)
        team = frappe.db.get_value("Task Access Policy", RW_KIND, "default_team_user")
        ok("S10 Packed: return task goes to the team pool", bool(rw) and frappe.db.get_value("Task", rw, "custom_assigned_to") == team, "{0} -> {1}".format(rw, frappe.db.get_value("Task", rw, "custom_assigned_to") if rw else "-"))
        ok("S10 return task has no ToDo", not frappe.db.exists("ToDo", {"reference_type": "Task", "reference_name": rw}), "")
        ok("S10 return task visible in the queue (_assign set)", team in (frappe.db.get_value("Task", rw, "_assign") or ""), frappe.db.get_value("Task", rw, "_assign"))
        api("dispatch_task_accept", {"task_name": rw}, DELIV_USER)
        e = save_as(rw, DELIV_USER, {"status": "Completed"})
        ok("S6b return task refuses completion without a photo", "photo" in e.lower() and frappe.db.get_value("Task", rw, "status") != "Completed", e[:60] or "COMPLETED")
        photo(rw)
        e = save_as(rw, DELIV_USER, {"status": "Completed"})
        ok("S6b return task CAN be completed on a cancelled case", not e and frappe.db.get_value("Task", rw, "status") == "Completed", e[:80] or "completed")
        ok("S11 goods left Delivery In-Transit", bal(DT, item) == start_dt, "dt={0} start={1}".format(bal(DT, item), start_dt))
        ok("S11 goods arrived in Returns", bal(RET, item) == start_ret + QTY, "ret {0}->{1}".format(start_ret, bal(RET, item)))
        insp = open_task(e_, "Returns processing / verification")
        ok("S11 inspection raised", bool(insp), insp)
        api("dispatch_task_accept", {"task_name": insp}, RETURNS_USER)
        api("task_update_return_item_quantities", {"case_name": e_, "row_name": e_row, "returned_qty": QTY, "lost_damaged_qty": 0}, RETURNS_USER)
        e = save_as(insp, RETURNS_USER, {"status": "Completed"})
        ok("S11 inspection completes", not e, e[:80] or "completed")
        ok("S11 case STAYS Cancelled after inspection", st(e_) == "Cancelled", st(e_))
        ok("S11 NO invoice task raised", not frappe.db.exists("Task", {"dispatch_case": e_, "task_kind": "Invoice preparation / create invoice"}), "")
        rs = open_task(e_, "Returns restocking")
        ok("S11 restocking raised", bool(rs), rs)
        api("dispatch_task_accept", {"task_name": rs}, RETURNS_USER)
        photo(rs)
        e = save_as(rs, RETURNS_USER, {"status": "Completed"})
        ok("S11 restocking completes on a cancelled case", not e, e[:80] or "completed")
        ok("S15 Main fully restored", bal(MAIN, item) == start_main, "main {0} -> {1}".format(start_main, bal(MAIN, item)))
        ok("S15 Returns back to start", bal(RET, item) == start_ret, "ret {0}".format(bal(RET, item)))
        ok("S11 case still Cancelled at the end", st(e_) == "Cancelled", st(e_))
        # ══ S10 + S12 + S13 + S15: In Transit -> one unit short ══════════
        start_main = bal(MAIN, item)
        start_dt = bal(DT, item)
        start_ld = bal(LD, item)
        f_, f_oe, f_row = build("In Transit", cust, item, wh)
        ok("S1 In Transit case built", st(f_) == "In Transit", st(f_))
        m, e = api("dispatch_case_cancel", {"dispatch_case": f_, "reason": "Surgery cancelled or postponed"}, DIRECTOR)
        ok("S1 Director cancels In Transit", not e and st(f_) == "Cancelled", e or st(f_))
        rw2 = open_task(f_, RW_KIND)
        ok("S10 In Transit: return task goes to the driver holding the box", bool(rw2) and frappe.db.get_value("Task", rw2, "custom_assigned_to") == DELIV_USER, frappe.db.get_value("Task", rw2, "custom_assigned_to") if rw2 else "-")
        api("dispatch_task_accept", {"task_name": rw2}, DELIV_USER)
        photo(rw2)
        save_as(rw2, DELIV_USER, {"status": "Completed"})
        insp2 = open_task(f_, "Returns processing / verification")
        api("dispatch_task_accept", {"task_name": insp2}, RETURNS_USER)
        api("task_update_return_item_quantities", {"case_name": f_, "row_name": f_row, "returned_qty": QTY - 2, "lost_damaged_qty": 1, "lost_damaged_presence": "Lost - not recoverable"}, RETURNS_USER)
        e = save_as(insp2, RETURNS_USER, {"status": "Completed"})
        ok("S13 inspection refuses returned+lost != dispatched", "nothing can have been used" in e, e[:60] or "COMPLETED")
        api("task_update_return_item_quantities", {"case_name": f_, "row_name": f_row, "returned_qty": QTY - 1, "lost_damaged_qty": 1, "lost_damaged_presence": "Lost - not recoverable"}, RETURNS_USER)
        e = save_as(insp2, RETURNS_USER, {"status": "Completed"})
        ok("S12 balanced inspection completes", not e, e[:80] or "completed")
        ok("S12 no consumption entry on a cancelled case", not frappe.db.get_value("Dispatch Case", f_, "consumption_stock_entry"), frappe.db.get_value("Dispatch Case", f_, "consumption_stock_entry"))
        ok("S12 lost unit moved to Lost & Damaged", bal(LD, item) == start_ld + 1, "ld {0}->{1}".format(start_ld, bal(LD, item)))
        wo = open_task(f_, "Write-off Approval")
        ok("S12 Write-off Approval raised", bool(wo), wo)
        api("dispatch_task_accept", {"task_name": wo}, DIRECTOR)
        e = save_as(wo, DIRECTOR, {"writeoff_outcome": "Bill Client", "status": "Completed"})
        ok("S12 Bill Client refused on a cancelled case", "cannot be billed" in e, e[:60] or "BILLED")
        e = save_as(wo, DIRECTOR, {"writeoff_outcome": "Write Off", "status": "Completed"})
        ok("S12 Write Off succeeds", not e and bal(LD, item) == start_ld, e[:60] or "ld={0}".format(bal(LD, item)))
        ok("S12 no invoice anywhere on the cancelled case", not frappe.db.exists("Sales Invoice", {"dispatch_case": f_, "docstatus": ["!=", 2]}), "")
        rs2 = open_task(f_, "Returns restocking")
        api("dispatch_task_accept", {"task_name": rs2}, RETURNS_USER)
        photo(rs2)
        save_as(rs2, RETURNS_USER, {"status": "Completed"})
        ok("S15 Main fell by exactly the written-off unit", bal(MAIN, item) == start_main - 1, "main {0} -> {1}".format(start_main, bal(MAIN, item)))
        ok("S15 Delivery In-Transit back to start", bal(DT, item) == start_dt, "dt={0}".format(bal(DT, item)))
        ok("S12 case still Cancelled at the end", st(f_) == "Cancelled", st(f_))
        # ══ S14: the aging report runs, and does not count cancelled cases
        # Through Frappe's REAL report runner, not raw SQL -- that is what a
        # user hits, and running it this way is what exposed that the report
        # had never worked (a PowerShell `t had corrupted its FROM clause).
        rep_err = ""
        rows = []
        try:
            out = frappe.get_attr("frappe.desk.query_report.run")("RPT - Dispatch Case Aging", filters={})
            rows = out.get("result") or []
        except Exception as rex:
            rep_err = str(rex)[:120]
        ok("S14 aging report actually runs", not rep_err, rep_err or "{0} rows".format(len(rows)))
        joined = " ".join([str(r) for r in rows])
        ok("S14 aging report excludes cancelled cases", not rep_err and (c not in joined) and (e_ not in joined) and (f_ not in joined), "{0} rows".format(len(rows)))
    except Exception as ex:
        R.append(("HARNESS ABORTED", "FAIL", str(ex)[:150]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("D11VERIFY_START")
    for n, v, d in R:
        print("D11VERIFY | {0:<66} | {1:<4} | {2}".format(n, v, d))
    print("D11VERIFY | {0} passed / {1} total".format(len([1 for x in R if x[1] == "PASS"]), len(R)))
    print("D11VERIFY_END")
d11("e2e.order.creating@test.erpnext.am", "e2e.inventory@test.erpnext.am", "e2e.delivery@test.erpnext.am", "e2e.returns@test.erpnext.am")
