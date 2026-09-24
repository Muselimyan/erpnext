# ==============================================================
# A9 VERIFY - the five smaller defects.
#
# C.1 duplicate active tenders refused at ORDER ENTRY, not at invoicing
# C.2 a stranded draft invoice no longer deadlocks the case
# C.3 tender data cannot make an invoice uncancellable
# C.4 a settlement always raises Director review, even closing no case
# C.5 the debt panel returns the same data without the per-row query
#
# C.2 uses a savepoint for the failure path. bench console has no request
# boundary, so a submit() that fails part-way leaves rows visible that a real
# request would roll back -- see AGENTS.md.
#
# Everything rolls back.
# ==============================================================
import frappe
def a9_verify(ACCT_USER, ORDER_USER):
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
        frappe.db.savepoint("a9call")
        try:
            frappe.get_doc("Server Script", script).execute_method()
        except Exception as e:
            err = str(e)[:220]
            frappe.db.rollback(save_point="a9call")
        frappe.set_user("Administrator")
        return (frappe.response.get("message") or {}), err
    def mkcust(tag):
        c = frappe.get_doc({"doctype": "Customer", "customer_name": "A9 " + tag + " " + frappe.generate_hash("", 5), "customer_type": "Company", "client_code": "A9" + frappe.generate_hash("", 6), "client_kind": "Hospital", "debt_threshold_amd": 999999999})
        c.flags.ignore_permissions = True
        c.insert()
        return c.name
    def mktender(cust, item, price, won):
        t = frappe.get_doc({"doctype": "Tender Agreement", "tender_name": "A9T " + frappe.generate_hash("", 5), "hospital": cust, "valid_from": frappe.utils.add_days(frappe.utils.nowdate(), -5), "valid_to": frappe.utils.add_days(frappe.utils.nowdate(), 90), "status": "Active", "items": [{"item_code": item, "tender_price": price, "won_quantity": won, "supplied_quantity": 0}]})
        t.flags.ignore_permissions = True
        t.insert()
        frappe.db.set_value("Tender Agreement", t.name, "status", "Active")
        return t.name
    def mkoe(cust, user):
        t = frappe.get_doc({"doctype": "Task", "subject": "A9 order entry", "task_kind": "Order entry", "task_access_policy": "Order entry", "status": "Working", "customer": cust, "custom_assigned_to": user, "custom_accepted_by": user, "custom_accepted_at": frappe.utils.now()})
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
        ok("FIXTURE priced item", bool(item), item)
        # ══ C.1 duplicate tenders refused at order entry ═══════════════
        cDup = mkcust("dup")
        t1 = mktender(cDup, item, 500, 100)
        t2 = mktender(cDup, item, 900, 100)
        oe, dc = mkoe(cDup, ORDER_USER)
        m, err = api("task_add_dispatch_product", {"task_name": oe, "item_code": item, "qty": 2}, ORDER_USER)
        ok("C.1 two active tenders refused at order entry", "Multiple active Tender Agreements" in err, err[:80] or "NOT REFUSED")
        ok("C.1 refusal names both tenders", (t1 in err) and (t2 in err), "t1={0} t2={1}".format(t1 in err, t2 in err))
        ok("C.1 no row was added", len(frappe.get_all("Dispatch Case Item", filters={"parent": dc})) == 0, "rows={0}".format(len(frappe.get_all("Dispatch Case Item", filters={"parent": dc}))))
        # single tender still works, and is used
        frappe.db.set_value("Tender Agreement", t2, "status", "Closed")
        m, err = api("task_add_dispatch_product", {"task_name": oe, "item_code": item, "qty": 2}, ORDER_USER)
        rows = frappe.get_all("Dispatch Case Item", filters={"parent": dc}, fields=["name", "unit_price"])
        ok("C.1 one active tender still prices the row", len(rows) == 1 and float(rows[0].unit_price) == 500.0, "err={0} price={1}".format(err[:40], rows[0].unit_price if rows else "-"))
        # ══ C.2 stranded draft no longer deadlocks ═════════════════════
        cDraft = mkcust("draft")
        dc2 = frappe.get_doc({"doctype": "Dispatch Case", "customer": cDraft, "status": "Confirmed", "client_location_warehouse": "Main - Inmed", "case_items": [{"item_code": item, "dispatched_qty": 4, "used_qty": 4, "unit_price": 700}]})
        dc2.flags.ignore_permissions = True
        dc2.insert()
        dc2.submit()
        frappe.db.set_value("Dispatch Case", dc2.name, "status", "Invoice Pending")
        inv = frappe.get_doc({"doctype": "Task", "subject": "A9 invoice", "task_kind": "Invoice preparation / create invoice", "task_access_policy": "Invoice preparation / create invoice", "status": "Working", "dispatch_case": dc2.name, "customer": cDraft, "custom_assigned_to": ACCT_USER, "custom_accepted_by": ACCT_USER, "custom_accepted_at": frappe.utils.now()})
        inv.flags.ignore_permissions = True
        inv.insert()
        # plant a stranded draft exactly as a failed submit would leave it
        stranded = frappe.get_doc({"doctype": "Sales Invoice", "customer": cDraft, "company": "InMED", "currency": "AMD", "update_stock": 0, "dispatch_case": dc2.name, "items": [{"item_code": item, "qty": 4, "rate": 700}]})
        stranded.flags.ignore_permissions = True
        stranded.insert()
        ok("C.2 stranded draft planted", frappe.db.get_value("Sales Invoice", stranded.name, "docstatus") == 0, stranded.name)
        m2, err2 = api("task_commit_invoice", {"task_name": inv.name}, ACCT_USER)
        ok("C.2 commit SUCCEEDS despite the draft", bool(m2.get("sales_invoice")) and not err2, err2[:80] or m2.get("sales_invoice"))
        # Assert on DOCSTATUS, not on the name. Deleting the draft frees its
        # number, so the replacement invoice is often issued the SAME name --
        # exists(stranded.name) is then true for a different document and the
        # test fails while the code is correct. What matters is that no
        # unsubmitted invoice is left on the case.
        left_drafts = frappe.get_all("Sales Invoice", filters={"dispatch_case": dc2.name, "docstatus": 0}, fields=["name"], limit_page_length=0)
        ok("C.2 no draft invoice left on the case", len(left_drafts) == 0, "{0}".format([d.name for d in left_drafts]))
        subs = frappe.get_all("Sales Invoice", filters={"dispatch_case": dc2.name, "docstatus": 1}, fields=["name"])
        ok("C.2 exactly one submitted invoice results", len(subs) == 1, "{0}".format([s.name for s in subs]))
        # a SUBMITTED invoice must still block, with the right wording
        m3, err3 = api("task_commit_invoice", {"task_name": inv.name}, ACCT_USER)
        ok("C.2 submitted invoice still blocks", "already has submitted invoice" in err3, err3[:70])
        # ══ C.3 tender data cannot block a cancel ══════════════════════
        cCan = mkcust("cancel")
        tC = mktender(cCan, item, 300, 50)
        siC = frappe.get_doc({"doctype": "Sales Invoice", "customer": cCan, "company": "InMED", "currency": "AMD", "update_stock": 0, "items": [{"item_code": item, "qty": 3, "rate": 300}]})
        siC.flags.ignore_permissions = True
        siC.insert()
        siC.submit()
        supplied = float(frappe.db.get_value("Tender Agreement Item", {"parent": tC, "item_code": item}, "supplied_quantity") or 0)
        ok("C.3 submit consumed tender quantity", supplied == 3.0, "supplied={0}".format(supplied))
        # delete the tender item row out from under the reversal
        trow = frappe.db.get_value("Tender Agreement Item", {"parent": tC, "item_code": item}, "name")
        frappe.db.delete("Tender Agreement Item", {"name": trow})
        cancel_err = ""
        try:
            siC.reload()
            siC.cancel()
        except Exception as e:
            cancel_err = str(e)[:150]
        ok("C.3 invoice STILL cancels with tender row gone", frappe.db.get_value("Sales Invoice", siC.name, "docstatus") == 2, cancel_err or "cancelled")
        # ══ C.4 settlement with no closed case raises approval ═════════
        cSet = mkcust("settle")
        si4 = frappe.get_doc({"doctype": "Sales Invoice", "customer": cSet, "company": "InMED", "currency": "AMD", "update_stock": 0, "items": [{"item_code": item, "qty": 1, "rate": 1200}]})
        si4.flags.ignore_permissions = True
        si4.insert()
        si4.submit()
        # no Dispatch Case at all for this customer, so nothing can close
        pe = frappe.get_doc({"doctype": "Payment Entry", "payment_type": "Receive", "party_type": "Customer", "party": cSet, "paid_amount": si4.grand_total, "received_amount": si4.grand_total, "company": "InMED", "paid_to": "Cash - Inmed", "mode_of_payment": "Cash", "posting_date": frappe.utils.nowdate(), "reference_date": frappe.utils.nowdate(), "references": [{"reference_doctype": "Sales Invoice", "reference_name": si4.name, "allocated_amount": si4.grand_total}]})
        pe.flags.ignore_permissions = True
        pe.insert()
        pe.submit()
        appr = frappe.get_all("Task", filters={"task_kind": "Debt Closure Approval", "customer": cSet}, fields=["name", "description", "custom_case_profit", "dispatch_case"], limit_page_length=0)
        ok("C.4 approval raised though no case closed", len(appr) == 1, "{0} approval(s)".format(len(appr)))
        if appr:
            ok("C.4 description says no case was closed", "closed NO Dispatch Case" in (appr[0].description or ""), (appr[0].description or "")[:60])
            # NOT asserting custom_case_profit is blank: it is a Currency field,
            # so it reads back as 0 whether or not it was set, and a test for
            # `not profit` passes vacuously. The description is the only place
            # that can distinguish "profit is zero" from "profit not computed",
            # so that is what is asserted -- including that it does NOT print a
            # profit line that a reader would take as a real figure.
            ok("C.4 no profit figure presented as real", "Profit on the covered cases" not in (appr[0].description or ""), "profit line absent")
            ok("C.4 description explains why there is none", "No profit figure is computed" in (appr[0].description or ""), "explanation present")
            ok("C.4 dispatch_case left blank, no IndexError", not (appr[0].dispatch_case or ""), "dc='{0}'".format(appr[0].dispatch_case))
        # ══ C.5 panel returns the same shape ══════════════════════════
        frappe.form_dict.clear()
        frappe.form_dict["customer"] = cSet
        frappe.response.pop("message", None)
        frappe.get_doc("Server Script", "task_debt_panel").execute_method()
        panel = frappe.response.get("message") or {}
        pays = panel.get("payments") or []
        ok("C.5 panel still returns payment history", len(pays) >= 1, "{0} payment(s)".format(len(pays)))
        withagainst = [p for p in pays if p.get("against")]
        ok("C.5 allocations still attached to the right payment", len(withagainst) >= 1 and withagainst[0]["against"][0]["sales_invoice"] == si4.name, "{0}".format(withagainst[0]["against"] if withagainst else "none"))
    except Exception as e:
        R.append(("HARNESS ABORTED", "FAIL", str(e)[:140]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("A9VERIFY_START")
    for n, v, d in R:
        print("A9VERIFY | {0:<48} | {1:<4} | {2}".format(n, v, d))
    print("A9VERIFY | {0} passed / {1} total".format(len([1 for x in R if x[1] == "PASS"]), len(R)))
    print("A9VERIFY_END")
a9_verify("e2e.accounting@test.erpnext.am", "e2e.order.creating@test.erpnext.am")
