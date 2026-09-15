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
        # ---- C1: system bookkeeping write by an Ops - Accounting user ----
        # This is precisely what create_or_update_debt_task() does when a second
        # invoice is raised for a customer who already has an open debt task.
        frappe.set_user(ACCOUNTING_USER)
        try:
            t = frappe.get_doc("Task", dc_task.name)
            t.append("open_invoices", {"invoice_amount": 500, "paid_amount": 0, "outstanding_amount": 500})
            t.total_outstanding = 1500
            t.flags.ignore_permissions = True
            t.save()
            results.append(("C1  system debt write as Ops-Accounting", "PASS", "allowed"))
        except Exception as e:
            results.append(("C1  system debt write as Ops-Accounting", "FAIL", str(e)[:160]))
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
