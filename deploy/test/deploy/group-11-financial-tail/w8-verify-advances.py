# ==============================================================
# W8 verification - run against TEST via bench console.
#
# Proves an advance is a submitted, unallocated Payment Entry carrying its own
# business intent; that nothing is written back to the Dispatch Case; and -- the
# point of the whole exercise -- that the order the money and the invoice arrive
# in no longer matters.
#
# Everything is rolled back; no records survive the run.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-11-financial-tail\w8-verify-advances.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
#
# NOTE: single function, no blank lines in the body, params not globals --
# IPython treats a blank line as end-of-block when code is piped in.
# ==============================================================
import frappe
def w8_verify(FINANCE_USER, ACCOUNTING_USER):
    results = []
    try:
        frappe.set_user("Administrator")
        cust = frappe.db.get_value("Customer", {"disabled": 0, "doctor_name": ["!=", ""]}, "name") or frappe.db.get_value("Customer", {"disabled": 0}, "name")
        priced = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, ["item_code", "price_list_rate"], as_dict=True)
        rate = float(priced.price_list_rate)
        # ---- fixture: a case ready to invoice, 2 units --------------------
        case = frappe.new_doc("Dispatch Case")
        case.status = "Invoice Pending"
        case.customer = cust
        case.flags.ignore_permissions = True
        case.flags.ignore_mandatory = True
        row = case.append("case_items", {})
        row.item_code = priced.item_code
        row.item_name = priced.item_code
        row.dispatched_qty = 2
        row.used_qty = 2
        row.unit_price = rate
        case.insert()
        # ---- 1. advance BEFORE the invoice, tagged to the case ------------
        adv_task = frappe.get_doc({"doctype": "Task", "subject": "W8VERIFY advance", "task_kind": "Payment Received", "task_access_policy": "Payment Received", "customer": cust, "dispatch_case": case.name, "status": "Working", "custom_assigned_to": FINANCE_USER, "custom_accepted_by": FINANCE_USER, "new_payment_amount": rate, "payment_method_dc": "Cash"})
        adv_task.flags.ignore_permissions = True
        adv_task.insert()
        frappe.set_user(FINANCE_USER)
        advpe = None
        try:
            a = frappe.get_doc("Task", adv_task.name)
            a.status = "Completed"
            a.flags.ignore_permissions = True
            a.save()
            frappe.set_user("Administrator")
            found = frappe.get_all("Payment Entry", filters={"source_task": adv_task.name}, fields=["name", "docstatus", "unallocated_amount", "dispatch_case", "source_task"], limit_page_length=0)
            if found:
                advpe = found[0]
                if advpe.docstatus == 1:
                    results.append(("ADV submitted, not draft", "PASS", advpe.name))
                else:
                    results.append(("ADV submitted, not draft", "FAIL", "docstatus=" + str(advpe.docstatus)))
                if advpe.dispatch_case == case.name and advpe.source_task == adv_task.name:
                    results.append(("ADV carries case + task intent", "PASS", advpe.dispatch_case))
                else:
                    results.append(("ADV carries case + task intent", "FAIL", "case=" + str(advpe.dispatch_case) + " task=" + str(advpe.source_task)))
                if abs(float(advpe.unallocated_amount or 0) - rate) < 0.01:
                    results.append(("ADV sits unallocated as credit", "PASS", str(advpe.unallocated_amount)))
                else:
                    results.append(("ADV sits unallocated as credit", "FAIL", "unallocated=" + str(advpe.unallocated_amount)))
            else:
                results.append(("ADV submitted, not draft", "FAIL", "no Payment Entry found by source_task"))
                results.append(("ADV carries case + task intent", "FAIL", "not reached"))
                results.append(("ADV sits unallocated as credit", "FAIL", "not reached"))
        except Exception as e:
            results.append(("ADV submitted, not draft", "FAIL", str(e)[:140]))
            results.append(("ADV carries case + task intent", "FAIL", "not reached"))
            results.append(("ADV sits unallocated as credit", "FAIL", "not reached"))
        # ---- 2. nothing written back to the Dispatch Case ----------------
        frappe.set_user("Administrator")
        c = frappe.get_doc("Dispatch Case", case.name)
        wrote_back = []
        for fn in ["prepaid_amount", "total_paid_amount"]:
            if c.get(fn):
                wrote_back.append(fn + "=" + str(c.get(fn)))
        if c.get("prepaid_payment_entry"):
            wrote_back.append("prepaid_payment_entry=" + str(c.get("prepaid_payment_entry")))
        if c.get("advance_payments"):
            wrote_back.append("advance_payments rows=" + str(len(c.get("advance_payments"))))
        if wrote_back:
            results.append(("ADV writes nothing to the case", "FAIL", ", ".join(wrote_back)))
        else:
            results.append(("ADV writes nothing to the case", "PASS", "case untouched"))
        # ---- 2b. credit earmarked for ANOTHER case must be left alone ----
        # Guards against the invoice quietly absorbing money the client paid
        # for a different case. Observed happening when allocation was
        # delegated to set_advances(), which ignores the recorded intent.
        other_case = frappe.new_doc("Dispatch Case")
        other_case.status = "Invoice Pending"
        other_case.customer = cust
        other_case.flags.ignore_permissions = True
        other_case.flags.ignore_mandatory = True
        other_case.insert()
        earmarked = frappe.get_doc({"doctype": "Payment Entry", "payment_type": "Receive", "party_type": "Customer", "party": cust, "paid_amount": 9999, "received_amount": 9999, "mode_of_payment": "Cash", "company": "InMED", "paid_to": "Cash - Inmed", "dispatch_case": other_case.name})
        earmarked.flags.ignore_permissions = True
        earmarked.insert()
        earmarked.submit()
        # ---- 3. the invoice consumes the advance automatically -----------
        inv_task = frappe.get_doc({"doctype": "Task", "subject": "W8VERIFY invoice", "task_kind": "Invoice preparation / create invoice", "task_access_policy": "Invoice preparation / create invoice", "customer": cust, "dispatch_case": case.name, "status": "Working", "custom_assigned_to": ACCOUNTING_USER, "custom_accepted_by": ACCOUNTING_USER})
        inv_task.flags.ignore_permissions = True
        inv_task.insert()
        commit = frappe.get_doc("Server Script", "task_commit_invoice")
        frappe.set_user(ACCOUNTING_USER)
        frappe.form_dict.clear()
        frappe.form_dict["task_name"] = inv_task.name
        try:
            frappe.response.pop("message", None)
            commit.execute_method()
            msg = frappe.response.get("message") or {}
            frappe.set_user("Administrator")
            si = frappe.get_doc("Sales Invoice", msg.get("sales_invoice"))
            # 2 units at `rate`, plus 20% VAT, less the one-unit advance.
            expected_gross = rate * 2 * 1.20
            adv_detail = []
            for adv in (si.advances or []):
                adv_detail.append(str(adv.reference_name) + ":" + str(adv.allocated_amount))
            pe_count = frappe.db.count("Payment Entry", {"source_task": adv_task.name, "docstatus": 1})
            if float(msg.get("advance_applied") or 0) > 0:
                results.append(("ADV consumed by the invoice", "PASS", "applied " + str(msg.get("advance_applied")) + " rows=[" + ", ".join(adv_detail) + "] pe_from_task=" + str(pe_count)))
            else:
                results.append(("ADV consumed by the invoice", "FAIL", "advance_applied=0, outstanding=" + str(si.outstanding_amount)))
            if float(si.outstanding_amount or 0) < expected_gross - 1:
                results.append(("ADV reduces invoice outstanding", "PASS", str(round(expected_gross, 2)) + " gross -> " + str(si.outstanding_amount) + " outstanding"))
            else:
                results.append(("ADV reduces invoice outstanding", "FAIL", "outstanding=" + str(si.outstanding_amount) + " gross=" + str(round(expected_gross, 2))))
            # The earmarked 9999 belongs to another case and must be untouched.
            still_earmarked = frappe.db.get_value("Payment Entry", earmarked.name, "unallocated_amount")
            used_names = []
            for adv in (si.advances or []):
                used_names.append(adv.reference_name)
            if earmarked.name not in used_names and abs(float(still_earmarked or 0) - 9999) < 0.01:
                results.append(("ADV other case's credit left alone", "PASS", "9999 still earmarked for " + other_case.name))
            else:
                results.append(("ADV other case's credit left alone", "FAIL", "unallocated=" + str(still_earmarked) + " used=" + str(used_names)))
        except Exception as e:
            results.append(("ADV consumed by the invoice", "FAIL", str(e)[:140]))
            results.append(("ADV reduces invoice outstanding", "FAIL", "not reached"))
        # ---- 4. a collection payment also records its source task --------
        frappe.set_user("Administrator")
        dtask = frappe.get_doc({"doctype": "Task", "subject": "W8VERIFY collection", "task_kind": "Debt Collection", "task_access_policy": "Debt Collection", "customer": cust, "status": "Working", "custom_assigned_to": FINANCE_USER, "custom_accepted_by": FINANCE_USER})
        dtask.flags.ignore_permissions = True
        dtask.insert()
        frappe.set_user(FINANCE_USER)
        try:
            d = frappe.get_doc("Task", dtask.name)
            d.new_payment_amount = 100
            d.payment_method_dc = "Cash"
            d.flags.ignore_permissions = True
            d.save()
            frappe.set_user("Administrator")
            pes = frappe.get_all("Payment Entry", filters={"source_task": dtask.name, "docstatus": 1}, fields=["name"], limit_page_length=0)
            if pes:
                results.append(("PAY collection records source_task", "PASS", pes[0].name))
            else:
                results.append(("PAY collection records source_task", "FAIL", "no Payment Entry tagged with the task"))
        except Exception as e:
            results.append(("PAY collection records source_task", "FAIL", str(e)[:140]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("W8VERIFY_RESULTS_START")
    for name, verdict, detail in results:
        print("W8VERIFY | {0:<38} | {1:<4} | {2}".format(name, verdict, detail))
    print("W8VERIFY_RESULTS_END")
w8_verify("e2e.finance@test.erpnext.am", "e2e.accounting@test.erpnext.am")
