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
        # ---- 0. schema present -------------------------------------------
        if frappe.db.exists("Warehouse", LD_WH):
            results.append(("SCHEMA Lost & Damaged warehouse", "PASS", LD_WH))
        else:
            results.append(("SCHEMA Lost & Damaged warehouse", "FAIL", "missing -- deploy w12 first"))
        meta_ok = frappe.get_meta("Dispatch Case Item").get_field("lost_damaged_presence") is not None
        results.append(("SCHEMA lost_damaged_presence field", "PASS" if meta_ok else "FAIL", "present" if meta_ok else "missing"))
        # ---- fixture: a submitted return-expected case, 10 dispatched -----
        # 6 used, 3 returned, 1 lost/damaged -- so Returns must end at zero.
        case = frappe.new_doc("Dispatch Case")
        case.status = "Returns Received"
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
        # Put the dispatched stock into Returns, as the pickup flow would.
        seed = frappe.get_doc({"doctype": "Stock Entry", "stock_entry_type": "Material Receipt", "purpose": "Material Receipt", "company": company, "items": [{"item_code": item, "qty": 10, "t_warehouse": RET_WH, "allow_zero_valuation_rate": 1, "cost_center": "Main - Inmed"}]})
        seed.flags.ignore_permissions = True
        seed.flags.ignore_validate = True
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
        frappe.form_dict["item_idx"] = 0
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
        frappe.form_dict["item_idx"] = 0
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
        frappe.form_dict["item_idx"] = 0
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
        frappe.form_dict["item_idx"] = 0
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
                ses = frappe.get_all("Stock Entry", filters={"docstatus": 1, "purpose": "Material Issue"}, fields=["name"], order_by="creation desc", limit_page_length=1)
                acct = ""
                if ses:
                    acct = frappe.db.get_value("Stock Entry Detail", {"parent": ses[0].name}, "expense_account") or ""
                if ld_after < ld_qty:
                    results.append(("WRITEOFF empties Lost & Damaged", "PASS", str(ld_qty) + " -> " + str(ld_after)))
                else:
                    results.append(("WRITEOFF empties Lost & Damaged", "FAIL", "still " + str(ld_after)))
                if acct == "Stock Adjustment - Inmed":
                    results.append(("WRITEOFF posts to Stock Adjustment not COGS", "PASS", acct))
                else:
                    results.append(("WRITEOFF posts to Stock Adjustment not COGS", "FAIL", "expense_account=" + str(acct)))
            except Exception as e:
                results.append(("WRITEOFF empties Lost & Damaged", "FAIL", str(e)[:130]))
                results.append(("WRITEOFF posts to Stock Adjustment not COGS", "FAIL", "not reached"))
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
        seed2 = frappe.get_doc({"doctype": "Stock Entry", "stock_entry_type": "Material Receipt", "purpose": "Material Receipt", "company": company, "items": [{"item_code": item, "qty": 2, "t_warehouse": LD_WH, "allow_zero_valuation_rate": 1, "cost_center": "Main - Inmed"}]})
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
    print("W12VERIFY NOTE: create_se still sets ignore_validate and allow_zero_valuation_rate (item A2),")
    print("W12VERIFY NOTE: so a write-off of un-valued stock posts a ZERO-value expense and still looks fine.")
    print("W12VERIFY NOTE: the stock movement is correct; the GL amount is only trustworthy once A2 is fixed.")
w12_verify("e2e.returns@test.erpnext.am", "e2e.directors@test.erpnext.am", "e2e.accounting@test.erpnext.am")
