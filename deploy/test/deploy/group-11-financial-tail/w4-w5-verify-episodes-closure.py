# ==============================================================
# W4 + W5 verification - run against TEST via bench console.
#
# W4: a collection episode cannot be closed without an outcome; a promise needs
#     a date; the scheduler raises an episode only when something is actually
#     overdue, never more than one per customer, and never before a promised
#     follow-up date arrives.
# W5: paying in full closes the case and raises exactly one Debt Closure
#     Approval, with profit computed once over the cases that settlement closed.
#
# Everything is rolled back; no records survive the run.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-11-financial-tail\w4-w5-verify-episodes-closure.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
#
# NOTE: single function, no blank lines in the body, params not globals --
# IPython treats a blank line as end-of-block when code is piped in.
# ==============================================================
import frappe
def w45_verify(FINANCE_USER, ACCOUNTING_USER):
    results = []
    try:
        frappe.set_user("Administrator")
        company = frappe.db.get_single_value("Global Defaults", "default_company") or "InMED"
        cust = frappe.db.get_value("Customer", {"disabled": 0, "doctor_name": ["!=", ""]}, "name") or frappe.db.get_value("Customer", {"disabled": 0}, "name")
        priced = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, ["item_code", "price_list_rate"], as_dict=True)
        rate = float(priced.price_list_rate)
        today = frappe.utils.nowdate()
        # ---- W4: episode completion gates -------------------------------
        ep = frappe.get_doc({"doctype": "Task", "subject": "W45VERIFY episode", "task_kind": "Debt Collection", "task_access_policy": "Debt Collection", "customer": cust, "status": "Working", "custom_assigned_to": FINANCE_USER, "custom_accepted_by": FINANCE_USER})
        ep.flags.ignore_permissions = True
        ep.insert()
        frappe.set_user(FINANCE_USER)
        try:
            e = frappe.get_doc("Task", ep.name)
            e.status = "Completed"
            e.flags.ignore_permissions = True
            e.save()
            results.append(("W4 episode needs an outcome", "FAIL", "completed with no outcome"))
        except Exception as ex:
            results.append(("W4 episode needs an outcome", "PASS", "blocked: " + str(ex)[:80]))
        try:
            e = frappe.get_doc("Task", ep.name)
            e.collection_outcome = "Promised"
            e.status = "Completed"
            e.flags.ignore_permissions = True
            e.save()
            results.append(("W4 promise needs a follow-up date", "FAIL", "completed with no date"))
        except Exception as ex:
            results.append(("W4 promise needs a follow-up date", "PASS", "blocked: " + str(ex)[:80]))
        try:
            e = frappe.get_doc("Task", ep.name)
            e.collection_outcome = "Promised"
            e.collection_follow_up_date = frappe.utils.add_days(today, 5)
            e.collection_note = "W45VERIFY: promised to pay Friday"
            e.status = "Completed"
            e.flags.ignore_permissions = True
            e.save()
            results.append(("W4 episode closes with outcome + date", "PASS", "outcome=Promised follow-up=+5d"))
        except Exception as ex:
            results.append(("W4 episode closes with outcome + date", "FAIL", str(ex)[:130]))
        # ---- W4: scheduler respects the promised date -------------------
        frappe.set_user("Administrator")
        sched = frappe.get_doc("Server Script", "Scheduled-debt-collection-episodes")
        # Overdue invoice for this customer, so only the promise holds it back.
        si_old = frappe.get_doc({"doctype": "Sales Invoice", "customer": cust, "company": company, "currency": "AMD", "update_stock": 0, "items": [{"item_code": priced.item_code, "qty": 1, "rate": rate}]})
        si_old.flags.ignore_permissions = True
        si_old.insert()
        frappe.db.set_value("Sales Invoice", si_old.name, "due_date", frappe.utils.add_days(today, -30), update_modified=False)
        si_old.reload()
        si_old.submit()
        frappe.db.set_value("Sales Invoice", si_old.name, "due_date", frappe.utils.add_days(today, -30), update_modified=False)
        before_count = frappe.db.count("Task", {"task_kind": "Debt Collection", "customer": cust, "status": ["not in", ["Completed", "Cancelled"]]})
        try:
            sched.execute_scheduled_method()
        except Exception as ex:
            results.append(("W4 scheduler runs", "FAIL", str(ex)[:130]))
        after_count = frappe.db.count("Task", {"task_kind": "Debt Collection", "customer": cust, "status": ["not in", ["Completed", "Cancelled"]]})
        if after_count == before_count:
            results.append(("W4 waits for the promised date", "PASS", "no new episode while follow-up is +5d"))
        else:
            results.append(("W4 waits for the promised date", "FAIL", str(before_count) + " -> " + str(after_count)))
        # Move the promise into the past: now an episode is due.
        frappe.db.set_value("Task", ep.name, "collection_follow_up_date", frappe.utils.add_days(today, -1))
        try:
            sched.execute_scheduled_method()
        except Exception as ex:
            pass
        due_count = frappe.db.count("Task", {"task_kind": "Debt Collection", "customer": cust, "status": ["not in", ["Completed", "Cancelled"]]})
        if due_count > before_count:
            results.append(("W4 raises an episode when due", "PASS", str(before_count) + " -> " + str(due_count)))
        else:
            results.append(("W4 raises an episode when due", "FAIL", "still " + str(due_count)))
        # Running again must not stack a second open episode.
        try:
            sched.execute_scheduled_method()
        except Exception as ex:
            pass
        dup_count = frappe.db.count("Task", {"task_kind": "Debt Collection", "customer": cust, "status": ["not in", ["Completed", "Cancelled"]]})
        if dup_count == due_count:
            results.append(("W4 one open episode per customer", "PASS", "still " + str(dup_count) + " after a second run"))
        else:
            results.append(("W4 one open episode per customer", "FAIL", str(due_count) + " -> " + str(dup_count)))
        # ---- W4: a settling payment auto-closes the episode as Paid -----
        # Guards an order-dependent hazard: payment recording and the
        # completion gate both run in before_save with no defined order, so
        # auto-completing without an outcome would either lose the payment or
        # slip past the gate depending on which ran first.
        frappe.set_user("Administrator")
        for old in frappe.get_all("Sales Invoice", filters={"customer": cust, "docstatus": 1, "outstanding_amount": [">", 0]}, fields=["name"], limit_page_length=0):
            frappe.db.set_value("Sales Invoice", old.name, "outstanding_amount", 0, update_modified=False)
        si_pay = frappe.get_doc({"doctype": "Sales Invoice", "customer": cust, "company": company, "currency": "AMD", "update_stock": 0, "items": [{"item_code": priced.item_code, "qty": 1, "rate": rate}]})
        si_pay.flags.ignore_permissions = True
        si_pay.insert()
        si_pay.submit()
        ep2 = frappe.get_doc({"doctype": "Task", "subject": "W45VERIFY settle episode", "task_kind": "Debt Collection", "task_access_policy": "Debt Collection", "customer": cust, "status": "Working", "custom_assigned_to": FINANCE_USER, "custom_accepted_by": FINANCE_USER})
        ep2.flags.ignore_permissions = True
        ep2.insert()
        frappe.set_user(FINANCE_USER)
        try:
            e2 = frappe.get_doc("Task", ep2.name)
            e2.new_payment_amount = float(si_pay.grand_total or 0)
            e2.payment_method_dc = "Cash"
            e2.flags.ignore_permissions = True
            e2.save()
            frappe.set_user("Administrator")
            st = frappe.db.get_value("Task", ep2.name, ["status", "collection_outcome"], as_dict=True)
            if st.status == "Completed" and st.collection_outcome == "Paid":
                results.append(("W4 settling payment closes as Paid", "PASS", "status=Completed outcome=Paid"))
            else:
                results.append(("W4 settling payment closes as Paid", "FAIL", "status=" + str(st.status) + " outcome=" + str(st.collection_outcome)))
        except Exception as ex:
            results.append(("W4 settling payment closes as Paid", "FAIL", str(ex)[:130]))
        # ---- W5: paying in full closes the case and raises approval -----
        frappe.set_user("Administrator")
        # Clear the customer's slate so "settled" is reachable in this test.
        for old in frappe.get_all("Sales Invoice", filters={"customer": cust, "docstatus": 1, "outstanding_amount": [">", 0]}, fields=["name"], limit_page_length=0):
            frappe.db.set_value("Sales Invoice", old.name, "outstanding_amount", 0, update_modified=False)
        case = frappe.new_doc("Dispatch Case")
        case.status = "Payment Pending"
        case.customer = cust
        case.flags.ignore_permissions = True
        case.flags.ignore_mandatory = True
        crow = case.append("case_items", {})
        crow.item_code = priced.item_code
        crow.item_name = priced.item_code
        crow.dispatched_qty = 1
        crow.used_qty = 1
        crow.unit_price = rate
        case.insert()
        si = frappe.get_doc({"doctype": "Sales Invoice", "customer": cust, "company": company, "currency": "AMD", "update_stock": 0, "dispatch_case": case.name, "items": [{"item_code": priced.item_code, "qty": 1, "rate": rate}]})
        si.flags.ignore_permissions = True
        si.insert()
        si.submit()
        gross = float(si.grand_total or 0)
        approvals_before = frappe.db.count("Task", {"task_kind": "Debt Closure Approval", "customer": cust, "status": ["not in", ["Completed", "Cancelled"]]})
        pe = frappe.get_doc({"doctype": "Payment Entry", "payment_type": "Receive", "party_type": "Customer", "party": cust, "paid_amount": gross, "received_amount": gross, "mode_of_payment": "Cash", "company": company, "paid_to": "Cash - Inmed", "dispatch_case": case.name, "references": [{"reference_doctype": "Sales Invoice", "reference_name": si.name, "allocated_amount": gross}]})
        pe.flags.ignore_permissions = True
        pe.insert()
        pe.submit()
        case_status = frappe.db.get_value("Dispatch Case", case.name, "status")
        if case_status == "Closed":
            results.append(("W5 payment closes the case", "PASS", case.name + " -> Closed"))
        else:
            results.append(("W5 payment closes the case", "FAIL", "status=" + str(case_status)))
        approvals = frappe.get_all("Task", filters={"task_kind": "Debt Closure Approval", "customer": cust, "status": ["not in", ["Completed", "Cancelled"]]}, fields=["name", "custom_case_profit", "payment_entry", "dispatch_case"], limit_page_length=0)
        if len(approvals) == approvals_before + 1:
            results.append(("W5 raises one approval", "PASS", approvals[0].name + " profit=" + str(approvals[0].custom_case_profit)))
        else:
            results.append(("W5 raises one approval", "FAIL", "before=" + str(approvals_before) + " now=" + str(len(approvals))))
        # A second settling payment must not raise a duplicate approval.
        pe2 = frappe.get_doc({"doctype": "Payment Entry", "payment_type": "Receive", "party_type": "Customer", "party": cust, "paid_amount": 50, "received_amount": 50, "mode_of_payment": "Cash", "company": company, "paid_to": "Cash - Inmed"})
        pe2.flags.ignore_permissions = True
        pe2.insert()
        pe2.submit()
        approvals_after = frappe.db.count("Task", {"task_kind": "Debt Closure Approval", "customer": cust, "status": ["not in", ["Completed", "Cancelled"]]})
        if approvals_after == approvals_before + 1:
            results.append(("W5 no duplicate approval", "PASS", "still " + str(approvals_after)))
        else:
            results.append(("W5 no duplicate approval", "FAIL", "now " + str(approvals_after)))
        # The retired script must not have run.
        retired = frappe.db.get_value("Server Script", "Task-after-save-debt-closure", "disabled")
        if retired == 1:
            results.append(("W5 old closure script retired", "PASS", "disabled=1"))
        else:
            results.append(("W5 old closure script retired", "FAIL", "disabled=" + str(retired)))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("W45VERIFY_RESULTS_START")
    for name, verdict, detail in results:
        print("W45VERIFY | {0:<38} | {1:<4} | {2}".format(name, verdict, detail))
    print("W45VERIFY_RESULTS_END")
w45_verify("e2e.finance@test.erpnext.am", "e2e.accounting@test.erpnext.am")
