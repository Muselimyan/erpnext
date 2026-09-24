# ==============================================================
# A3 VERIFY: no item priced at zero can participate in the flow.
#
# Nine holes were closed. This tests each, plus the two consequences that
# matter most -- that the deadlock is gone, and that packing/returns still work
# now that the validation bypass has been removed from them.
#
# The riskiest assertion here is 8: removing ignore_validate_update_after_submit
# means those four endpoints now run Frappe's real update-after-submit check. If
# any field they write were not allow_on_submit, packing would break. That is
# why lost_damaged_presence was corrected first, and why this asserts the whole
# scan/return path end to end rather than just the absence of the flag.
#
# Everything rolls back.
# ==============================================================
import frappe
def a3_verify(ORDER_USER, INV_USER, RETURNS_USER, ACCT_USER):
    R = []
    def ok(label, cond, detail=""):
        R.append((label, "PASS" if cond else "FAIL", str(detail)[:88]))
        return cond
    def api(script, args, user):
        frappe.set_user(user)
        frappe.form_dict.clear()
        for k in args:
            frappe.form_dict[k] = args[k]
        frappe.response.pop("message", None)
        err = ""
        frappe.db.savepoint("a3call")
        try:
            frappe.get_doc("Server Script", script).execute_method()
        except Exception as e:
            err = str(e)[:240]
            frappe.db.rollback(save_point="a3call")
        frappe.set_user("Administrator")
        return (frappe.response.get("message") or {}), err
    def mkcust(tag):
        c = frappe.get_doc({"doctype": "Customer", "customer_name": "A3 " + tag + " " + frappe.generate_hash("", 5), "customer_type": "Company", "client_code": "A3" + frappe.generate_hash("", 6), "client_kind": "Hospital", "debt_threshold_amd": 999999999})
        c.flags.ignore_permissions = True
        c.insert()
        return c.name
    def mkoe(cust, user):
        t = frappe.get_doc({"doctype": "Task", "subject": "A3 OE", "task_kind": "Order entry", "task_access_policy": "Order entry", "status": "Working", "customer": cust, "custom_assigned_to": user, "custom_accepted_by": user, "custom_accepted_at": frappe.utils.now()})
        t.flags.ignore_permissions = True
        t.insert()
        dc = frappe.get_doc({"doctype": "Dispatch Case", "customer": cust, "status": "Draft", "client_location_warehouse": "Main - Inmed"})
        dc.flags.ignore_permissions = True
        dc.insert()
        frappe.db.set_value("Task", t.name, "dispatch_case", dc.name)
        return t.name, dc.name
    try:
        frappe.set_user("Administrator")
        item = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, "item_code")
        # an item with NO Standard Selling price, for the template test
        noprice = None
        for it in frappe.get_all("Item", filters={"disabled": 0}, fields=["name"], limit_page_length=400):
            if not frappe.db.exists("Item Price", {"item_code": it.name, "price_list": "Standard Selling"}):
                noprice = it.name
                break
        ok("FIXTURE priced + unpriced items", bool(item and noprice), "priced={0} unpriced={1}".format(item, noprice))
        # ══ A.2 discount bounds ════════════════════════════════════════
        cA = mkcust("disc")
        oeA, dcA = mkoe(cA, ORDER_USER)
        m, e100 = api("task_add_dispatch_product", {"task_name": oeA, "item_code": item, "qty": 1, "discount_pct": 100}, ORDER_USER)
        ok("A.2 100% discount refused on add", "not allowed" in e100 and "zero" in e100, e100[:70] or "ACCEPTED")
        m, e150 = api("task_add_dispatch_product", {"task_name": oeA, "item_code": item, "qty": 1, "discount_pct": 150}, ORDER_USER)
        ok("A.2 150% discount refused", bool(e150), e150[:60] or "ACCEPTED")
        m, eneg = api("task_add_dispatch_product", {"task_name": oeA, "item_code": item, "qty": 1, "discount_pct": -10}, ORDER_USER)
        ok("A.2 negative discount refused", "negative" in eneg, eneg[:60] or "ACCEPTED")
        m, eok = api("task_add_dispatch_product", {"task_name": oeA, "item_code": item, "qty": 2, "discount_pct": 99}, ORDER_USER)
        ok("A.2 99% discount still allowed", not eok, eok[:60] or "accepted")
        rows = frappe.get_all("Dispatch Case Item", filters={"parent": dcA}, fields=["name", "unit_price", "discount_pct"])
        ok("A.2 only the valid row exists", len(rows) == 1, "{0} row(s)".format(len(rows)))
        # update path bound too
        if rows:
            # This endpoint takes case_name, not task_name -- it resolves the
            # acting task from the case and the session user.
            m, eupd = api("task_update_dispatch_product", {"case_name": dcA, "row_name": rows[0].name, "discount_pct": 100}, ORDER_USER)
            ok("A.2 100% discount refused on update", "not allowed" in eupd, eupd[:60] or "ACCEPTED")
        # ══ A.1 template refuses unpriced lines ════════════════════════
        tmpl = frappe.get_doc({"doctype": "Surgical Kit Template", "template_name": "A3T " + frappe.generate_hash("", 5), "template_items": [{"item_code": item, "item_name": item, "qty": 1}, {"item_code": noprice, "item_name": noprice, "qty": 1}]})
        tmpl.flags.ignore_permissions = True
        tmpl.flags.ignore_mandatory = True
        tmpl.insert()
        cB = mkcust("tmpl")
        oeB, dcB = mkoe(cB, ORDER_USER)
        m, etm = api("task_apply_template", {"task_name": oeB, "template_name": tmpl.name}, ORDER_USER)
        ok("A.1 template with an unpriced item refused", "no selling price" in etm and noprice in etm, etm[:70] or "ACCEPTED")
        ok("A.1 refusal changed nothing (all or nothing)", len(frappe.get_all("Dispatch Case Item", filters={"parent": dcB})) == 0, "{0} row(s)".format(len(frappe.get_all("Dispatch Case Item", filters={"parent": dcB}))))
        # a fully priced template applies AND carries prices
        tmpl2 = frappe.get_doc({"doctype": "Surgical Kit Template", "template_name": "A3T2 " + frappe.generate_hash("", 5), "template_items": [{"item_code": item, "item_name": item, "qty": 3}]})
        tmpl2.flags.ignore_permissions = True
        tmpl2.flags.ignore_mandatory = True
        tmpl2.insert()
        m, etm2 = api("task_apply_template", {"task_name": oeB, "template_name": tmpl2.name}, ORDER_USER)
        trows = frappe.get_all("Dispatch Case Item", filters={"parent": dcB}, fields=["unit_price"])
        ok("A.1 priced template applies WITH prices", len(trows) == 1 and float(trows[0].unit_price) > 0, "err={0} price={1}".format(etm2[:30], trows[0].unit_price if trows else "-"))
        # ══ A.3 submit backstop ════════════════════════════════════════
        cC = mkcust("submit")
        dcC = frappe.get_doc({"doctype": "Dispatch Case", "customer": cC, "status": "Draft", "client_location_warehouse": "Main - Inmed", "case_items": [{"item_code": item, "dispatched_qty": 2, "unit_price": 0}]})
        dcC.flags.ignore_permissions = True
        dcC.insert()
        serr = ""
        try:
            dcC.submit()
        except Exception as ex:
            serr = str(ex)[:160]
        ok("A.3 submit refuses a zero-price row", "price of zero" in serr, serr[:70] or "SUBMITTED")
        # and refuses the 100%-discount shape, which unit_price alone would miss
        dcD = frappe.get_doc({"doctype": "Dispatch Case", "customer": cC, "status": "Draft", "client_location_warehouse": "Main - Inmed", "case_items": [{"item_code": item, "dispatched_qty": 2, "unit_price": 900, "discount_pct": 100}]})
        dcD.flags.ignore_permissions = True
        dcD.insert()
        derr = ""
        try:
            dcD.submit()
        except Exception as ex:
            derr = str(ex)[:160]
        ok("A.3 submit refuses 100%-discount row", "price of zero" in derr, derr[:70] or "SUBMITTED")
        # a properly priced case still submits
        dcE = frappe.get_doc({"doctype": "Dispatch Case", "customer": cC, "status": "Draft", "client_location_warehouse": "Main - Inmed", "case_items": [{"item_code": item, "dispatched_qty": 2, "unit_price": 900, "discount_pct": 10}]})
        dcE.flags.ignore_permissions = True
        dcE.insert()
        eerr = ""
        try:
            dcE.submit()
        except Exception as ex:
            eerr = str(ex)[:120]
        ok("A.3 a properly priced case still submits", frappe.db.get_value("Dispatch Case", dcE.name, "docstatus") == 1, eerr or "submitted")
        # ══ A.4 price locked after submit ══════════════════════════════
        perr = ""
        try:
            locked = frappe.get_doc("Dispatch Case", dcE.name)
            locked.case_items[0].unit_price = 1
            locked.flags.ignore_permissions = True
            locked.save()
        except Exception as ex:
            perr = str(ex)[:160]
        after_price = float(frappe.db.get_value("Dispatch Case Item", {"parent": dcE.name}, "unit_price") or 0)
        ok("A.4 price cannot be changed after submit", bool(perr) and after_price == 900.0, "err={0} price={1}".format(perr[:44], after_price))
        # ══ A.5 nothing-to-invoice uses the effective rate ═════════════
        frappe.db.set_value("Dispatch Case", dcE.name, "status", "Invoice Pending")
        frappe.db.set_value("Dispatch Case Item", {"parent": dcE.name}, "used_qty", 2)
        invt = frappe.get_doc({"doctype": "Task", "subject": "A3 inv", "task_kind": "Invoice preparation / create invoice", "task_access_policy": "Invoice preparation / create invoice", "status": "Working", "dispatch_case": dcE.name, "customer": cC, "custom_assigned_to": ACCT_USER, "custom_accepted_by": ACCT_USER, "custom_accepted_at": frappe.utils.now()})
        invt.flags.ignore_permissions = True
        invt.insert()
        m, cerr = api("task_close_case_nothing_to_invoice", {"task_name": invt.name, "reason": "test"}, ACCT_USER)
        ok("A.5 priced consumed row cannot be closed as nothing-to-invoice", "billable items" in cerr, cerr[:60] or "CLOSED")
        # ══ A.6 packing + returns still work without the bypass ════════
        cF = mkcust("pack")
        dcF = frappe.get_doc({"doctype": "Dispatch Case", "customer": cF, "status": "Draft", "client_location_warehouse": "Main - Inmed", "case_items": [{"item_code": item, "dispatched_qty": 5, "unit_price": 400}]})
        dcF.flags.ignore_permissions = True
        dcF.insert()
        dcF.submit()
        rowF = frappe.get_all("Dispatch Case Item", filters={"parent": dcF.name}, fields=["name"])[0].name
        packt = frappe.get_doc({"doctype": "Task", "subject": "A3 pack", "task_kind": "Pack / prepare items", "task_access_policy": "Pack / prepare items", "status": "Working", "dispatch_case": dcF.name, "customer": cF, "custom_assigned_to": INV_USER, "custom_accepted_by": INV_USER, "custom_accepted_at": frappe.utils.now()})
        packt.flags.ignore_permissions = True
        packt.insert()
        m, perr2 = api("task_mark_item_packed", {"case_name": dcF.name, "row_name": rowF, "packed": 1}, INV_USER)
        ok("A.6 marking packed still works on a SUBMITTED case", not perr2 and float(frappe.db.get_value("Dispatch Case Item", rowF, "custom_scanned_qty") or 0) == 5.0, perr2[:60] or "scanned=5")
        frappe.db.set_value("Dispatch Case", dcF.name, "status", "Returns Received")
        rett = frappe.get_doc({"doctype": "Task", "subject": "A3 ret", "task_kind": "Returns processing / verification", "task_access_policy": "Returns processing / verification", "status": "Working", "dispatch_case": dcF.name, "customer": cF, "custom_assigned_to": RETURNS_USER, "custom_accepted_by": RETURNS_USER, "custom_accepted_at": frappe.utils.now()})
        rett.flags.ignore_permissions = True
        rett.insert()
        m, rerr = api("task_update_return_item_quantities", {"case_name": dcF.name, "row_name": rowF, "returned_qty": 2, "lost_damaged_qty": 1, "lost_damaged_presence": "Damaged - in hand"}, RETURNS_USER)
        pres = frappe.db.get_value("Dispatch Case Item", rowF, "lost_damaged_presence")
        ok("A.6 returns incl. lost_damaged_presence still writes", not rerr and pres == "Damaged - in hand", rerr[:60] or "presence={0}".format(pres))
        ok("A.6 used_qty recomputed", float(frappe.db.get_value("Dispatch Case Item", rowF, "used_qty") or 0) == 2.0, "used={0}".format(frappe.db.get_value("Dispatch Case Item", rowF, "used_qty")))
        # ══ A.7 override endpoints disabled ════════════════════════════
        for ep in ("disable_all_item_batch_serial_for_now", "perm_disable_batch_expiry_dbset"):
            ok("A.7 {0} disabled".format(ep[:34]), int(frappe.db.get_value("Server Script", ep, "disabled") or 0) == 1, "disabled={0}".format(frappe.db.get_value("Server Script", ep, "disabled")))
    except Exception as e:
        R.append(("HARNESS ABORTED", "FAIL", str(e)[:150]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("A3VERIFY_START")
    for n, v, d in R:
        print("A3VERIFY | {0:<58} | {1:<4} | {2}".format(n, v, d))
    print("A3VERIFY | {0} passed / {1} total".format(len([1 for x in R if x[1] == "PASS"]), len(R)))
    print("A3VERIFY_END")
a3_verify("e2e.order.creating@test.erpnext.am", "e2e.inventory@test.erpnext.am", "e2e.returns@test.erpnext.am", "e2e.accounting@test.erpnext.am")
