# ==============================================================
# W1 verification - run against TEST via bench console.
#
# Reproduces the C1 collision and checks the D2 admin policy, as a genuinely
# non-privileged user. This must be run as Ops - Accounting and NOT as
# Administrator or System Manager: the defect is exempt for privileged users,
# which is exactly why it survived the Group 3 smoke tests and why the
# Playwright Layer 1 suite (which authenticates as Administrator) cannot see it.
#
# Everything is rolled back; no records survive the run.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-11-financial-tail\w1-verify-access-control.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
#
# Expected BEFORE W1:  C1 = FAIL (blocked), D2 checks = as noted
# Expected AFTER  W1:  C1 = PASS (allowed), D2 checks = PASS
#
# NOTE: written as a single function with no blank lines inside the body,
# because IPython treats a blank line as end-of-block when code is piped in.
# ==============================================================
import frappe
# Users are passed as parameters rather than read from module globals: when this
# file is piped into `bench console`, IPython does not expose top-level names to
# the function body, so global lookups raise NameError.
def w1_verify(ACCOUNTING_USER, FINANCE_USER, DIRECTOR_USER):
    results = []
    try:
        frappe.set_user("Administrator")
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        # ---- fixture: an OPEN, UNACCEPTED Debt Collection task ----------
        dc_task = frappe.get_doc({"doctype": "Task", "subject": "W1VERIFY debt collection", "task_kind": "Debt Collection", "task_access_policy": "Debt Collection", "customer": cust, "status": "Open", "custom_assigned_to": "finance.team@example.com", "total_outstanding": 1000})
        dc_task.flags.ignore_permissions = True
        dc_task.insert()
        frappe.db.set_value("Task", dc_task.name, "custom_accepted_by", "")
        # ---- fixture: a task accepted by SOMEONE ELSE -------------------
        other = frappe.get_doc({"doctype": "Task", "subject": "W1VERIFY other-owned", "task_kind": "Other: Entry", "task_access_policy": "Other: Entry", "status": "Working", "custom_assigned_to": FINANCE_USER, "custom_accepted_by": FINANCE_USER})
        other.flags.ignore_permissions = True
        other.insert()
        # ---- C1: end-to-end. An Ops - Accounting user completes Invoice
        # Preparation for a customer who ALREADY has an open Debt Collection
        # task. This is the exact scenario that was impossible: the flow's
        # follow-up touched that debt task, and the accountant was judged
        # against Debt Collection's roles and refused.
        #
        # Note this check was originally written against the task's
        # `open_invoices` child table. W2 deleted that table -- debt is read
        # from the ledger now -- so the check exercises the real task
        # completion instead, which is a better test of the same defect.
        company = frappe.db.get_single_value("Global Defaults", "default_company") or "InMED"
        item = frappe.db.get_value("Item", {"disabled": 0, "is_stock_item": 1}, "name")
        si = frappe.get_doc({"doctype": "Sales Invoice", "customer": cust, "company": company, "currency": "AMD", "update_stock": 0, "items": [{"item_code": item, "qty": 1, "rate": 4000}]})
        si.flags.ignore_permissions = True
        si.insert()
        si.submit()
        case = frappe.new_doc("Dispatch Case")
        case.status = "Invoice Pending"
        case.customer = cust
        case.flags.ignore_permissions = True
        case.flags.ignore_mandatory = True
        case.insert()
        frappe.db.set_value("Dispatch Case", case.name, "sales_invoice", si.name)
        inv_task = frappe.get_doc({"doctype": "Task", "subject": "W1VERIFY invoice prep", "task_kind": "Invoice preparation / create invoice", "task_access_policy": "Invoice preparation / create invoice", "customer": cust, "dispatch_case": case.name, "status": "Working", "custom_assigned_to": ACCOUNTING_USER, "custom_accepted_by": ACCOUNTING_USER})
        inv_task.flags.ignore_permissions = True
        inv_task.insert()
        frappe.set_user(ACCOUNTING_USER)
        try:
            t = frappe.get_doc("Task", inv_task.name)
            t.status = "Completed"
            t.flags.ignore_permissions = True
            t.save()
            results.append(("C1  Ops-Accounting completes invoice prep", "PASS", "allowed with debt task open"))
        except Exception as e:
            results.append(("C1  Ops-Accounting completes invoice prep", "FAIL", str(e)[:160]))
        # ---- D2a: non-owner must NOT complete another user's task -------
        frappe.set_user(ACCOUNTING_USER)
        try:
            t2 = frappe.get_doc("Task", other.name)
            t2.status = "Completed"
            t2.flags.ignore_permissions = True
            t2.save()
            results.append(("D2a non-owner completing other's task", "FAIL", "was allowed - should be blocked"))
        except Exception as e:
            results.append(("D2a non-owner completing other's task", "PASS", "blocked: " + str(e)[:110]))
        # ---- D2b: privileged user MAY edit a task they do not own --------
        frappe.set_user(DIRECTOR_USER)
        try:
            t3 = frappe.get_doc("Task", other.name)
            t3.description = "W1VERIFY privileged edit"
            t3.flags.ignore_permissions = True
            t3.save()
            results.append(("D2b director editing other's task", "PASS", "allowed"))
        except Exception as e:
            results.append(("D2b director editing other's task", "FAIL", str(e)[:160]))
        # ---- D2c: privileged user must NOT complete another's task ------
        frappe.set_user(DIRECTOR_USER)
        try:
            t4 = frappe.get_doc("Task", other.name)
            t4.status = "Completed"
            t4.flags.ignore_permissions = True
            t4.save()
            results.append(("D2c director completing other's task", "FAIL", "was allowed - should be blocked"))
        except Exception as e:
            results.append(("D2c director completing other's task", "PASS", "blocked: " + str(e)[:110]))
        # ---- Regression: a user edit on an unaccepted task is blocked ----
        frappe.set_user(ACCOUNTING_USER)
        try:
            t5 = frappe.get_doc("Task", dc_task.name)
            t5.description = "W1VERIFY user field edit"
            t5.flags.ignore_permissions = True
            t5.save()
            results.append(("REG user edit on unaccepted task", "FAIL", "was allowed - should be blocked"))
        except Exception as e:
            results.append(("REG user edit on unaccepted task", "PASS", "blocked: " + str(e)[:110]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("W1VERIFY_RESULTS_START")
    for name, verdict, detail in results:
        print("W1VERIFY | {0:<42} | {1:<4} | {2}".format(name, verdict, detail))
    print("W1VERIFY_RESULTS_END")
w1_verify("e2e.accounting@test.erpnext.am", "e2e.finance@test.erpnext.am", "e2e.directors@test.erpnext.am")
