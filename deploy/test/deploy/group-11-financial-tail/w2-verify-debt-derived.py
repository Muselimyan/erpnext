# ==============================================================
# W2 verification - run against TEST via bench console.
#
# Proves that debt is read from the ledger rather than stored on the Task, that
# payment allocation works against live invoices, and that an advance now
# reaches the general ledger.
#
# Everything is rolled back; no records survive the run.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-11-financial-tail\w2-verify-debt-derived.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
#
# NOTE: single function, no blank lines in the body, users/params passed in --
# IPython treats a blank line as end-of-block and does not expose module globals
# to the function when code is piped in.
# ==============================================================
import frappe
def w2_verify(FINANCE_USER, ACCOUNTING_USER):
    results = []
    try:
        frappe.set_user("Administrator")
        company = frappe.db.get_single_value("Global Defaults", "default_company") or "InMED"
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        item = frappe.db.get_value("Item", {"disabled": 0, "is_stock_item": 1}, "name")
        # ---- fixture: a submitted invoice so there is real debt -----------
        si = frappe.get_doc({"doctype": "Sales Invoice", "customer": cust, "company": company, "currency": "AMD", "update_stock": 0, "items": [{"item_code": item, "qty": 1, "rate": 5000}]})
        si.flags.ignore_permissions = True
        si.insert()
        si.submit()
        # ---- 1. the panel API reads the ledger ----------------------------
        dt = frappe.get_doc({"doctype": "Task", "subject": "W2VERIFY debt", "task_kind": "Debt Collection", "task_access_policy": "Debt Collection", "customer": cust, "status": "Open", "custom_assigned_to": "finance.team@example.com"})
        dt.flags.ignore_permissions = True
        dt.insert()
        frappe.form_dict["task_name"] = dt.name
        panel = frappe.get_doc("Server Script", "task_debt_panel")
        try:
            frappe.response.pop("message", None)
            panel.execute_method()
            msg = frappe.response.get("message") or {}
            found = False
            for row in (msg.get("invoices") or []):
                if row.get("sales_invoice") == si.name:
                    found = True
            if found and float(msg.get("totals", {}).get("outstanding") or 0) >= 5000:
                results.append(("PANEL reads invoice from ledger", "PASS", "outstanding=" + str(msg["totals"]["outstanding"])))
            else:
                results.append(("PANEL reads invoice from ledger", "FAIL", "invoice not in panel output"))
        except Exception as e:
            results.append(("PANEL reads invoice from ledger", "FAIL", str(e)[:150]))
        # ---- 2. no stored debt fields remain on the Task ------------------
        meta = frappe.get_meta("Task")
        leftovers = []
        for fn in ["open_invoices", "payment_history", "total_outstanding", "available_advance_credit", "custom_total_amount_paid"]:
            if meta.get_field(fn):
                leftovers.append(fn)
        if leftovers:
            results.append(("SCHEMA stored debt fields removed", "PEND", "still present: " + ",".join(leftovers)))
        else:
            results.append(("SCHEMA stored debt fields removed", "PASS", "all five gone"))
        # ---- 3. payment allocates against the live invoice ---------------
        frappe.set_user("Administrator")
        frappe.db.set_value("Task", dt.name, "custom_accepted_by", FINANCE_USER)
        frappe.db.set_value("Task", dt.name, "custom_assigned_to", FINANCE_USER)
        frappe.db.set_value("Task", dt.name, "status", "Working")
        frappe.set_user(FINANCE_USER)
        try:
            t = frappe.get_doc("Task", dt.name)
            t.new_payment_amount = 2000
            t.payment_method_dc = "Cash"
            t.payment_reference_dc = "W2VERIFY-CASH"
            t.flags.ignore_permissions = True
            t.save()
            frappe.set_user("Administrator")
            outstanding_now = frappe.db.get_value("Sales Invoice", si.name, "outstanding_amount")
            if float(outstanding_now or 0) == 3000:
                results.append(("PAY allocates to live invoice", "PASS", "invoice outstanding 5000 -> 3000"))
            else:
                results.append(("PAY allocates to live invoice", "FAIL", "outstanding=" + str(outstanding_now)))
        except Exception as e:
            results.append(("PAY allocates to live invoice", "FAIL", str(e)[:150]))
        # ---- 4. overpayment is refused -----------------------------------
        frappe.set_user(FINANCE_USER)
        try:
            t2 = frappe.get_doc("Task", dt.name)
            t2.new_payment_amount = 999999
            t2.payment_method_dc = "Cash"
            t2.flags.ignore_permissions = True
            t2.save()
            results.append(("PAY overpayment refused", "FAIL", "was allowed"))
        except Exception as e:
            results.append(("PAY overpayment refused", "PASS", "blocked: " + str(e)[:100]))
        # ---- 5. an advance now reaches the general ledger ----------------
        frappe.set_user("Administrator")
        adv = frappe.get_doc({"doctype": "Task", "subject": "W2VERIFY advance", "task_kind": "Payment Received", "task_access_policy": "Payment Received", "customer": cust, "status": "Working", "custom_assigned_to": FINANCE_USER, "custom_accepted_by": FINANCE_USER, "new_payment_amount": 1500, "payment_method_dc": "Cash"})
        adv.flags.ignore_permissions = True
        adv.insert()
        frappe.set_user(FINANCE_USER)
        try:
            a = frappe.get_doc("Task", adv.name)
            a.status = "Completed"
            a.flags.ignore_permissions = True
            a.save()
            frappe.set_user("Administrator")
            pes = frappe.get_all("Payment Entry", filters={"party": cust, "reference_no": "", "docstatus": 1, "payment_type": "Receive"}, fields=["name", "docstatus", "paid_amount"], order_by="creation desc", limit_page_length=5)
            advpe = None
            for p in pes:
                if float(p.paid_amount or 0) == 1500:
                    advpe = p
            if advpe:
                gl = frappe.db.count("GL Entry", {"voucher_no": advpe.name, "is_cancelled": 0})
                if gl > 0:
                    results.append(("ADV advance posts to the ledger", "PASS", advpe.name + " gl_rows=" + str(gl)))
                else:
                    results.append(("ADV advance posts to the ledger", "FAIL", advpe.name + " has no GL entries"))
            else:
                results.append(("ADV advance posts to the ledger", "FAIL", "no submitted 1500 Payment Entry found"))
        except Exception as e:
            results.append(("ADV advance posts to the ledger", "FAIL", str(e)[:150]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("W2VERIFY_RESULTS_START")
    for name, verdict, detail in results:
        print("W2VERIFY | {0:<36} | {1:<4} | {2}".format(name, verdict, detail))
    print("W2VERIFY_RESULTS_END")
w2_verify("e2e.finance@test.erpnext.am", "e2e.accounting@test.erpnext.am")
