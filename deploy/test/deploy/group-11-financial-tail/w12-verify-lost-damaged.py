# ==============================================================
# W12 verification - run against TEST via bench console.
#
# Covers the lost & damaged resolution path: the presence attribute is required,
# the units are segregated out of Returns at inspection, Returns then balances,
# a Director decision either bills the client or writes the units off, and
# neither branch can act twice.
#
# Run as e2e.returns and e2e.directors, NEVER as Administrator -- privileged
# users are exempt from the access-control gates, and three defects in this area
# were invisible to privileged testing.
#
# Everything is rolled back; no records survive the run.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-11-financial-tail\w12-verify-lost-damaged.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
#
# NOTE: single function, no blank lines in the body, users passed as parameters.
# IPython treats a blank line as end-of-block when code is piped in, and does not
# expose module globals to the function body.
# ==============================================================
import frappe
def w12_verify(RETURNS_USER, DIRECTOR_USER, ACCOUNTING_USER):
    results = []
    LD_WH = "Lost & Damaged - Inmed"
    RET_WH = "Returns - Inmed"
    try:
        frappe.set_user("Administrator")
        company = frappe.db.get_single_value("Global Defaults", "default_company") or "InMED"
        cust = frappe.db.get_value("Customer", {"disabled": 0, "doctor_name": ["!=", ""]}, "name") or frappe.db.get_value("Customer", {"disabled": 0}, "name")
        priced = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, ["item_code", "price_list_rate"], as_dict=True)
        rate = float(priced.price_list_rate)
        item = priced.item_code
        # uom / transfer_qty / conversion_factor are normally filled in by
        # Stock Entry.validate(), which ignore_validate skips -- so the seeds have
        # to supply them or insert() fails on mandatory fields. Same trap as A2.
        uom = frappe.db.get_value("Item", item, "stock_uom") or "Nos"
        # ---- 0. schema present -------------------------------------------
        if frappe.db.exists("Warehouse", LD_WH):
            results.append(("SCHEMA Lost & Damaged warehouse", "PASS", LD_WH))
        else:
            results.append(("SCHEMA Lost & Damaged warehouse", "FAIL", "missing -- deploy w12 first"))
        meta_ok = frappe.get_meta("Dispatch Case Item").get_field("lost_damaged_presence") is not None
        results.append(("SCHEMA lost_damaged_presence field", "PASS" if meta_ok else "FAIL", "present" if meta_ok else "missing"))
        # ---- fixture: a submitted return-expected case, 10 dispatched -----
        # 6 used, 3 returned, 1 lost/damaged -- so Returns must end at zero.
        # Submitted as Confirmed, then moved to Returns Received by a direct write.
        # Dispatch-Case-before-submit refuses to submit anything outside
        # Draft/Confirmed, so the end state cannot be set before submitting.
        case = frappe.new_doc("Dispatch Case")
        case.status = "Confirmed"
        case.customer = cust
        case.return_expected = 1
        case.flags.ignore_permissions = True
        case.flags.ignore_mandatory = True
        r = case.append("case_items", {})
        r.item_code = item
        r.item_name = item
        r.dispatched_qty = 10
        r.unit_price = rate
        case.insert()
        case.flags.ignore_permissions = True
        case.submit()
        frappe.db.set_value("Dispatch Case", case.name, "status", "Returns Received")
        case.reload()
        # Group 1 D2 changed task_update_return_item_quantities to address rows by
        # NAME rather than array position, and it now REFUSES item_idx outright
        # rather than quietly serving it. This script was a caller nobody found
        # when that inventory was taken -- the grep covered work/client and
        # work/server but not deploy/. Resolve the row name once and use it below.
        ld_row = frappe.get_all("Dispatch Case Item", filters={"parent": case.name}, fields=["name"], limit_page_length=1)[0].name
        # Put the dispatched stock into Returns, as the pickup flow would.
        # basic_rate is explicit and allow_zero_valuation_rate is NOT set: the
        # write-off branch now refuses un-valued stock, so a zero-valued fixture
        # would fail for the wrong reason. The refusal gets its own check below.
        seed = frappe.get_doc({"doctype": "Stock Entry", "stock_entry_type": "Material Receipt", "purpose": "Material Receipt", "company": company, "items": [{"item_code": item, "qty": 10, "transfer_qty": 10, "uom": uom, "stock_uom": uom, "conversion_factor": 1, "t_warehouse": RET_WH, "basic_rate": 1000, "cost_center": "Main - Inmed", "expense_account": "Stock Adjustment - Inmed"}]})
        seed.flags.ignore_permissions = True
        seed.insert()
        seed.submit()
        ret_before = float(frappe.db.get_value("Bin", {"item_code": item, "warehouse": RET_WH}, "actual_qty") or 0)
        insp = frappe.get_doc({"doctype": "Task", "subject": "W12VERIFY inspect", "task_kind": "Returns processing / verification", "task_access_policy": "Returns processing / verification", "customer": cust, "dispatch_case": case.name, "status": "Working", "custom_assigned_to": RETURNS_USER, "custom_accepted_by": RETURNS_USER})
        insp.flags.ignore_permissions = True
        insp.insert()
        upd = frappe.get_doc("Server Script", "task_update_return_item_quantities")
        # ---- 1. presence rejected when nothing is lost --------------------
        frappe.set_user(RETURNS_USER)
        frappe.form_dict.clear()
        frappe.form_dict["case_name"] = case.name
        frappe.form_dict["row_name"] = ld_row
        frappe.form_dict["returned_qty"] = 10
        frappe.form_dict["lost_damaged_qty"] = 0
        frappe.form_dict["lost_damaged_presence"] = "Damaged - in hand"
        try:
            frappe.response.pop("message", None)
            upd.execute_method()
            frappe.set_user("Administrator")
            stored = frappe.db.get_value("Dispatch Case Item", {"parent": case.name}, "lost_damaged_presence")
            if not stored:
                results.append(("API presence cleared when qty is zero", "PASS", "not stored"))
            else:
                results.append(("API presence cleared when qty is zero", "FAIL", "stored '" + str(stored) + "'"))
        except Exception as e:
            results.append(("API presence cleared when qty is zero", "FAIL", str(e)[:120]))
        # ---- 2. record 6 used / 3 returned / 1 lost, no presence ----------
        frappe.set_user(RETURNS_USER)
        frappe.form_dict.clear()
        frappe.form_dict["case_name"] = case.name
        frappe.form_dict["row_name"] = ld_row
        frappe.form_dict["returned_qty"] = 3
        frappe.form_dict["lost_damaged_qty"] = 1
        try:
            frappe.response.pop("message", None)
            upd.execute_method()
            msg = frappe.response.get("message") or {}
            if float(msg.get("used_qty") or 0) == 6:
                results.append(("API used_qty = dispatched - returned - lost", "PASS", "6"))
            else:
                results.append(("API used_qty = dispatched - returned - lost", "FAIL", str(msg.get("used_qty"))))
        except Exception as e:
            results.append(("API used_qty = dispatched - returned - lost", "FAIL", str(e)[:120]))
        # ---- 3. inspection blocked without a presence ---------------------
        frappe.set_user(RETURNS_USER)
        try:
            t = frappe.get_doc("Task", insp.name)
            t.status = "Completed"
            t.flags.ignore_permissions = True
            t.save()
            results.append(("GATE inspection needs a presence", "FAIL", "completed without one"))
        except Exception as e:
            results.append(("GATE inspection needs a presence", "PASS", "blocked: " + str(e)[:90]))
        # ---- 4. bad presence value refused --------------------------------
        frappe.set_user(RETURNS_USER)
        frappe.form_dict.clear()
        frappe.form_dict["case_name"] = case.name
        frappe.form_dict["row_name"] = ld_row
        frappe.form_dict["returned_qty"] = 3
        frappe.form_dict["lost_damaged_qty"] = 1
        frappe.form_dict["lost_damaged_presence"] = "Eaten by the dog"
        try:
            frappe.response.pop("message", None)
            upd.execute_method()
            results.append(("API unknown presence refused", "FAIL", "accepted"))
        except Exception as e:
            results.append(("API unknown presence refused", "PASS", "blocked: " + str(e)[:80]))
        # ---- 5. set a valid presence, complete inspection ------------------
        frappe.set_user(RETURNS_USER)
        frappe.form_dict.clear()
        frappe.form_dict["case_name"] = case.name
        frappe.form_dict["row_name"] = ld_row
        frappe.form_dict["returned_qty"] = 3
        frappe.form_dict["lost_damaged_qty"] = 1
        frappe.form_dict["lost_damaged_presence"] = "Damaged - in hand"
        frappe.response.pop("message", None)
        upd.execute_method()
        try:
            t = frappe.get_doc("Task", insp.name)
            t.status = "Completed"
            t.flags.ignore_permissions = True
            t.save()
            results.append(("GATE inspection completes with a presence", "PASS", "allowed"))
        except Exception as e:
            results.append(("GATE inspection completes with a presence", "FAIL", str(e)[:130]))
        # ---- 6. the unit is segregated into Lost & Damaged ----------------
        frappe.set_user("Administrator")
        ld_qty = float(frappe.db.get_value("Bin", {"item_code": item, "warehouse": LD_WH}, "actual_qty") or 0)
        if ld_qty >= 1:
            results.append(("STOCK segregated into Lost & Damaged", "PASS", str(ld_qty) + " in " + LD_WH))
        else:
            results.append(("STOCK segregated into Lost & Damaged", "FAIL", "bin qty " + str(ld_qty)))
        # ---- 7. one Write-off Approval, assigned to Directors -------------
        appr = frappe.get_all("Task", filters={"dispatch_case": case.name, "task_kind": "Write-off Approval"}, fields=["name", "custom_assigned_to", "status"], limit_page_length=0)
        if len(appr) == 1:
            results.append(("TASK one Write-off Approval raised", "PASS", appr[0].name + " -> " + str(appr[0].custom_assigned_to)))
        else:
            results.append(("TASK one Write-off Approval raised", "FAIL", str(len(appr)) + " found"))
        # ---- 8. approval cannot complete without an outcome ---------------
        if appr:
            frappe.set_user("Administrator")
            frappe.db.set_value("Task", appr[0].name, {"custom_accepted_by": DIRECTOR_USER, "custom_assigned_to": DIRECTOR_USER, "status": "Working"})
            frappe.set_user(DIRECTOR_USER)
            try:
                a = frappe.get_doc("Task", appr[0].name)
                a.status = "Completed"
                a.flags.ignore_permissions = True
                a.save()
                results.append(("GATE approval needs an outcome", "FAIL", "completed without one"))
            except Exception as e:
                results.append(("GATE approval needs an outcome", "PASS", "blocked: " + str(e)[:90]))
        # ---- 9. Write Off empties the warehouse to Stock Adjustment -------
        if appr:
            frappe.set_user(DIRECTOR_USER)
            try:
                a = frappe.get_doc("Task", appr[0].name)
                a.writeoff_outcome = "Write Off"
                a.status = "Completed"
                a.flags.ignore_permissions = True
                a.save()
                frappe.set_user("Administrator")
                ld_after = float(frappe.db.get_value("Bin", {"item_code": item, "warehouse": LD_WH}, "actual_qty") or 0)
                # Located by the source_task stamp rather than "most recent
                # Material Issue", which could pick up an unrelated entry.
                ses = frappe.get_all("Stock Entry", filters={"source_task": appr[0].name, "docstatus": 1}, fields=["name"], limit_page_length=0)
                acct = ""
                amt = 0.0
                if ses:
                    det = frappe.db.get_value("Stock Entry Detail", {"parent": ses[0].name}, ["expense_account", "amount"], as_dict=True)
                    acct = (det.expense_account if det else "") or ""
                    amt = float((det.amount if det else 0) or 0)
                if ld_after < ld_qty:
                    results.append(("WRITEOFF empties Lost & Damaged", "PASS", str(ld_qty) + " -> " + str(ld_after)))
                else:
                    results.append(("WRITEOFF empties Lost & Damaged", "FAIL", "still " + str(ld_after)))
                if acct == "Stock Adjustment - Inmed":
                    results.append(("WRITEOFF posts to Stock Adjustment not COGS", "PASS", acct))
                else:
                    results.append(("WRITEOFF posts to Stock Adjustment not COGS", "FAIL", "expense_account=" + str(acct)))
                # A write-off whose value is zero has recognised nothing, which is
                # the failure mode item A2 would otherwise hide behind a success.
                if amt > 0:
                    results.append(("WRITEOFF books a non-zero loss", "PASS", "amount=" + str(amt)))
                else:
                    results.append(("WRITEOFF books a non-zero loss", "FAIL", "amount=" + str(amt)))
                # The stock movement is traceable back to the approval that caused
                # it; nothing connected the two before.
                if len(ses) == 1:
                    results.append(("TRACE resolution entry stamped with the task", "PASS", ses[0].name))
                else:
                    results.append(("TRACE resolution entry stamped with the task", "FAIL", str(len(ses)) + " stamped entries"))
            except Exception as e:
                results.append(("WRITEOFF empties Lost & Damaged", "FAIL", str(e)[:130]))
                results.append(("WRITEOFF posts to Stock Adjustment not COGS", "FAIL", "not reached"))
                results.append(("WRITEOFF books a non-zero loss", "FAIL", "not reached"))
                results.append(("TRACE resolution entry stamped with the task", "FAIL", "not reached"))
        # ---- 9a. re-completing cannot move the stock twice -----------------
        # Completed tasks are immutable, so the status is reverted by a direct db
        # write to force a second is_completing transition -- the only path by
        # which the guard could ever matter. Kept in its own try so a failure here
        # cannot re-report the checks above, and run as the ACCEPTER: completion is
        # reserved to them with no exemption, Administrator included.
        if appr:
            try:
                frappe.set_user("Administrator")
                frappe.db.set_value("Task", appr[0].name, "status", "Working")
                frappe.set_user(DIRECTOR_USER)
                a3 = frappe.get_doc("Task", appr[0].name)
                a3.status = "Completed"
                a3.flags.ignore_permissions = True
                a3.save()
                frappe.set_user("Administrator")
                ses2 = frappe.get_all("Stock Entry", filters={"source_task": appr[0].name, "docstatus": 1}, fields=["name"], limit_page_length=0)
                if len(ses2) == 1:
                    results.append(("WRITEOFF is idempotent on re-completion", "PASS", "still 1 entry"))
                else:
                    results.append(("WRITEOFF is idempotent on re-completion", "FAIL", str(len(ses2)) + " entries"))
            except Exception as e:
                results.append(("WRITEOFF is idempotent on re-completion", "FAIL", str(e)[:130]))
        # ---- 9b. the segregation transfer is stamped too -------------------
        frappe.set_user("Administrator")
        seg = frappe.get_all("Stock Entry", filters={"source_task": insp.name, "docstatus": 1}, fields=["name"], limit_page_length=0)
        if len(seg) == 1:
            results.append(("TRACE segregation entry stamped with the task", "PASS", seg[0].name))
        else:
            results.append(("TRACE segregation entry stamped with the task", "FAIL", str(len(seg)) + " stamped entries"))
        # ---- 9c. un-valued stock cannot be written off ---------------------
        # The whole point of a write-off is the amount. With A2's
        # allow_zero_valuation_rate this used to post zero and report success.
        frappe.set_user("Administrator")
        item2 = frappe.db.get_value("Item", {"is_stock_item": 1, "disabled": 0, "item_code": ["!=", item]}, "name")
        case4 = frappe.new_doc("Dispatch Case")
        case4.status = "Returns Received"
        case4.customer = cust
        case4.return_expected = 1
        case4.flags.ignore_permissions = True
        case4.flags.ignore_mandatory = True
        r4 = case4.append("case_items", {})
        r4.item_code = item2
        r4.item_name = item2
        r4.dispatched_qty = 1
        r4.returned_qty = 0
        r4.lost_damaged_qty = 1
        r4.used_qty = 0
        r4.lost_damaged_presence = "Lost - not recoverable"
        case4.insert()
        # Deliberately un-valued: no basic_rate, zero valuation allowed. This is
        # the state A2 lets through and that the write-off must now refuse.
        uom2 = frappe.db.get_value("Item", item2, "stock_uom") or "Nos"
        seed4 = frappe.get_doc({"doctype": "Stock Entry", "stock_entry_type": "Material Receipt", "purpose": "Material Receipt", "company": company, "items": [{"item_code": item2, "qty": 1, "transfer_qty": 1, "uom": uom2, "stock_uom": uom2, "conversion_factor": 1, "t_warehouse": LD_WH, "allow_zero_valuation_rate": 1, "basic_rate": 0, "cost_center": "Main - Inmed", "expense_account": "Stock Adjustment - Inmed"}]})
        seed4.flags.ignore_permissions = True
        seed4.flags.ignore_validate = True
        seed4.insert()
        seed4.submit()
        appr4 = frappe.get_doc({"doctype": "Task", "subject": "W12VERIFY unvalued", "task_kind": "Write-off Approval", "task_access_policy": "Write-off Approval", "customer": cust, "dispatch_case": case4.name, "status": "Working", "custom_assigned_to": DIRECTOR_USER, "custom_accepted_by": DIRECTOR_USER, "writeoff_outcome": "Write Off"})
        appr4.flags.ignore_permissions = True
        appr4.insert()
        frappe.set_user(DIRECTOR_USER)
        try:
            a4 = frappe.get_doc("Task", appr4.name)
            a4.status = "Completed"
            a4.flags.ignore_permissions = True
            a4.save()
            results.append(("WRITEOFF refuses un-valued stock", "FAIL", "booked a zero-value loss"))
        except Exception as e:
            results.append(("WRITEOFF refuses un-valued stock", "PASS", "blocked: " + str(e)[:80]))
        # ---- 9d. an unresolved outcome cannot strand the stock -------------
        # Two layers refuse this: the before-save gate (empty outcome) and the
        # after-save handler's final else (any other value). The handler exists
        # because it must not depend on another script having stayed correct --
        # W1 exists precisely because rules split across scripts drift apart.
        #
        # Only the GATE is reachable from here. Forcing an out-of-range value to
        # reach the handler's else would be caught first by Frappe's own Select
        # validation, so the test would pass without ever exercising the branch.
        # Asserting the behaviour -- completion is refused, stock is not stranded
        # -- and reporting which layer did it, rather than faking a deeper one.
        frappe.set_user("Administrator")
        appr5 = frappe.get_doc({"doctype": "Task", "subject": "W12VERIFY no outcome", "task_kind": "Write-off Approval", "task_access_policy": "Write-off Approval", "customer": cust, "dispatch_case": case4.name, "status": "Working", "custom_assigned_to": DIRECTOR_USER, "custom_accepted_by": DIRECTOR_USER})
        appr5.flags.ignore_permissions = True
        appr5.insert()
        frappe.set_user(DIRECTOR_USER)
        try:
            a5 = frappe.get_doc("Task", appr5.name)
            a5.status = "Completed"
            a5.flags.ignore_permissions = True
            a5.save()
            results.append(("OUTCOME an unresolved outcome cannot complete", "FAIL", "completed, stock stranded"))
        except Exception as e:
            layer = "gate" if "Write-off Outcome" in str(e) else "other"
            results.append(("OUTCOME an unresolved outcome cannot complete", "PASS", layer + ": " + str(e)[:70]))
        # No stock moved for the refused approval.
        frappe.set_user("Administrator")
        stray = frappe.get_all("Stock Entry", filters={"source_task": appr5.name}, fields=["name"], limit_page_length=0)
        if not stray:
            results.append(("OUTCOME refused approval moved no stock", "PASS", "none"))
        else:
            results.append(("OUTCOME refused approval moved no stock", "FAIL", str(len(stray)) + " entries"))
        # ---- 10. Bill Client raises exactly one invoice -------------------
        # Separate case so the write-off above does not interfere.
        frappe.set_user("Administrator")
        case2 = frappe.new_doc("Dispatch Case")
        case2.status = "Returns Received"
        case2.customer = cust
        case2.return_expected = 1
        case2.flags.ignore_permissions = True
        case2.flags.ignore_mandatory = True
        r2 = case2.append("case_items", {})
        r2.item_code = item
        r2.item_name = item
        r2.dispatched_qty = 4
        r2.returned_qty = 2
        r2.lost_damaged_qty = 2
        r2.used_qty = 0
        r2.unit_price = rate
        r2.lost_damaged_presence = "Lost - not recoverable"
        case2.insert()
        seed2 = frappe.get_doc({"doctype": "Stock Entry", "stock_entry_type": "Material Receipt", "purpose": "Material Receipt", "company": company, "items": [{"item_code": item, "qty": 2, "transfer_qty": 2, "uom": uom, "stock_uom": uom, "conversion_factor": 1, "t_warehouse": LD_WH, "basic_rate": 1000, "cost_center": "Main - Inmed", "expense_account": "Stock Adjustment - Inmed"}]})
        seed2.flags.ignore_permissions = True
        seed2.flags.ignore_validate = True
        seed2.insert()
        seed2.submit()
        appr2 = frappe.get_doc({"doctype": "Task", "subject": "W12VERIFY bill", "task_kind": "Write-off Approval", "task_access_policy": "Write-off Approval", "customer": cust, "dispatch_case": case2.name, "status": "Working", "custom_assigned_to": DIRECTOR_USER, "custom_accepted_by": DIRECTOR_USER, "writeoff_outcome": "Bill Client"})
        appr2.flags.ignore_permissions = True
        appr2.insert()
        frappe.set_user(DIRECTOR_USER)
        try:
            a2 = frappe.get_doc("Task", appr2.name)
            a2.status = "Completed"
            a2.flags.ignore_permissions = True
            a2.save()
            frappe.set_user("Administrator")
            invs = frappe.get_all("Sales Invoice", filters={"source_task": appr2.name, "docstatus": 1}, fields=["name", "grand_total", "total_taxes_and_charges", "due_date", "posting_date"], limit_page_length=0)
            if len(invs) == 1:
                tax_ok = float(invs[0].total_taxes_and_charges or 0) > 0
                due_ok = str(invs[0].due_date) != str(invs[0].posting_date)
                results.append(("BILL raises one invoice for the loss", "PASS", invs[0].name + " total=" + str(invs[0].grand_total)))
                results.append(("BILL invoice carries VAT and terms", "PASS" if (tax_ok and due_ok) else "FAIL", "vat=" + str(invs[0].total_taxes_and_charges) + " due=" + str(invs[0].due_date)))
            else:
                results.append(("BILL raises one invoice for the loss", "FAIL", str(len(invs)) + " invoices"))
                results.append(("BILL invoice carries VAT and terms", "FAIL", "not reached"))
        except Exception as e:
            results.append(("BILL raises one invoice for the loss", "FAIL", str(e)[:130]))
            results.append(("BILL invoice carries VAT and terms", "FAIL", "not reached"))
        # ---- 11. the used-items invoice is still independent --------------
        # task_commit_invoice keys its guard on an empty source_task, so the
        # lost/damaged invoice above must not block it.
        frappe.set_user("Administrator")
        frappe.db.set_value("Dispatch Case Item", {"parent": case2.name}, "used_qty", 1)
        inv_task = frappe.get_doc({"doctype": "Task", "subject": "W12VERIFY used invoice", "task_kind": "Invoice preparation / create invoice", "task_access_policy": "Invoice preparation / create invoice", "customer": cust, "dispatch_case": case2.name, "status": "Working", "custom_assigned_to": ACCOUNTING_USER, "custom_accepted_by": ACCOUNTING_USER})
        inv_task.flags.ignore_permissions = True
        inv_task.insert()
        commit = frappe.get_doc("Server Script", "task_commit_invoice")
        frappe.set_user(ACCOUNTING_USER)
        frappe.form_dict.clear()
        frappe.form_dict["task_name"] = inv_task.name
        try:
            frappe.response.pop("message", None)
            commit.execute_method()
            m = frappe.response.get("message") or {}
            results.append(("INV used-items invoice unaffected", "PASS", str(m.get("sales_invoice"))))
        except Exception as e:
            results.append(("INV used-items invoice unaffected", "FAIL", str(e)[:130]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("W12VERIFY_RESULTS_START")
    for name, verdict, detail in results:
        print("W12VERIFY | {0:<44} | {1:<4} | {2}".format(name, verdict, detail))
    print("W12VERIFY_RESULTS_END")
    print("W12VERIFY NOTE: every create_se movement now runs with ERPNext validation intact -- no")
    print("W12VERIFY NOTE: ignore_validate, no ignore_stock_validation, no allow_zero_valuation_rate.")
    print("W12VERIFY NOTE: This path proved why it mattered: ignore_validate skips set_basic_rate, so")
    print("W12VERIFY NOTE: the segregation transfer arrived at ZERO value and the write-off had nothing")
    print("W12VERIFY NOTE: to write off. A2 did not merely make amounts wrong here -- it made the")
    print("W12VERIFY NOTE: feature impossible.")
    print("W12VERIFY NOTE:")
    print("W12VERIFY NOTE: A2 is CLOSED as of Group 1 D1: the strict parameter is gone and all ten call")
    print("W12VERIFY NOTE: sites are validated. The earlier note here said the other seven kept lenient")
    print("W12VERIFY NOTE: flags -- no longer true. Remaining residue is tracked as Group 1 D9")
    print("W12VERIFY NOTE: (Stock Settings.allow_negative_stock = 1, which validation cannot overrule)")
    print("W12VERIFY NOTE: and D10 (372 pre-existing malformed Stock Entries, not repaired).")
w12_verify("e2e.returns@test.erpnext.am", "e2e.directors@test.erpnext.am", "e2e.accounting@test.erpnext.am")
