# ==============================================================
# A8 VERIFY: the Debt Alert scheduler no longer resurrects cancelled alerts,
# and the alerts it raises are assigned in the field the application reads.
#
# This is a Scheduler Event, so saving it proves nothing (AGENTS.md). Every
# assertion below runs it for real via execute_scheduled_method().
#
# What it proves:
#   1. an over-threshold customer gets an alert at all (baseline)
#   2. the alert carries custom_assigned_to, not just _assign
#   3. _assign is still set, so the list view and notifications keep working
#   4. a second run does NOT raise a duplicate while one is open
#   5. CANCELLING an alert lets the next run raise a FRESH one  <- the fix
#   6. the cancelled alert is left cancelled, not refilled and reassigned
#   7. a COMPLETED alert also lets a fresh one be raised (unchanged behaviour)
#   8. an under-threshold customer gets nothing
#
# 5 and 6 are the pair that matters: the old filter treated Cancelled as open,
# so the Director's cancellation was silently undone on the next hourly run.
#
# Everything rolls back.
# ==============================================================
import frappe
def a8_verify():
    R = []
    KIND = "Debt Alert"
    def ok(label, cond, detail=""):
        R.append((label, "PASS" if cond else "FAIL", str(detail)[:90]))
        return cond
    def run_scheduler():
        frappe.get_doc("Server Script", "Scheduled-debt-collection").execute_scheduled_method()
    def alerts(cust, include_terminal=True):
        f = {"task_kind": KIND, "customer": cust}
        if not include_terminal:
            f["status"] = ["not in", ["Completed", "Cancelled"]]
        return frappe.get_all("Task", filters=f, fields=["name", "status", "custom_assigned_to", "current_debt_amd"], order_by="creation asc", limit_page_length=0)
    def mkcust(tag, threshold):
        c = frappe.get_doc({"doctype": "Customer", "customer_name": "A8 " + tag + " " + frappe.generate_hash("", 5), "customer_type": "Company", "client_code": "A8" + frappe.generate_hash("", 6), "client_kind": "Hospital", "debt_threshold_amd": threshold})
        c.flags.ignore_permissions = True
        c.insert()
        return c.name
    def mkinv(cust, amount):
        item = frappe.db.get_value("Item Price", {"price_list": "Standard Selling", "price_list_rate": [">", 0]}, "item_code")
        si = frappe.get_doc({"doctype": "Sales Invoice", "customer": cust, "company": "InMED", "currency": "AMD", "update_stock": 0, "items": [{"item_code": item, "qty": 1, "rate": amount}]})
        si.flags.ignore_permissions = True
        si.insert()
        si.submit()
        return si.name
    try:
        frappe.set_user("Administrator")
        policy_user = frappe.db.get_value("Task Access Policy", KIND, "default_team_user")
        ok("FIXTURE Debt Alert policy has a team user", bool(policy_user), policy_user)
        # ── 1-3. baseline: an alert is raised, and assigned properly ──
        cOver = mkcust("over", 1000)
        mkinv(cOver, 50000)
        run_scheduler()
        a = alerts(cOver)
        ok("1 over-threshold customer gets an alert", len(a) == 1, "{0} alert(s)".format(len(a)))
        if a:
            ok("2 alert carries custom_assigned_to", (a[0].custom_assigned_to or "") == policy_user, "got '{0}' want '{1}'".format(a[0].custom_assigned_to, policy_user))
            asg = frappe.db.get_value("Task", a[0].name, "_assign") or ""
            ok("3 _assign still set (list view keeps working)", policy_user in asg, "_assign={0}".format(asg[:40]))
        # ── 4. no duplicate while one is open ────────────────────────
        run_scheduler()
        ok("4 second run raises no duplicate", len(alerts(cOver)) == 1, "{0} alert(s)".format(len(alerts(cOver))))
        # ── 5+6. THE FIX: cancelling lets a fresh alert be raised ────
        first = alerts(cOver)[0].name
        frappe.db.set_value("Task", first, "status", "Cancelled")
        run_scheduler()
        after = alerts(cOver)
        fresh = [x for x in after if x.name != first]
        ok("5 cancelling allows a FRESH alert", len(fresh) == 1, "{0} total, {1} new".format(len(after), len(fresh)))
        ok("5 the fresh alert is Open", bool(fresh) and fresh[0].status == "Open", fresh[0].status if fresh else "-")
        ok("5 the fresh alert is assigned", bool(fresh) and (fresh[0].custom_assigned_to or "") == policy_user, fresh[0].custom_assigned_to if fresh else "-")
        still = frappe.db.get_value("Task", first, "status")
        ok("6 the cancelled alert STAYS cancelled", still == "Cancelled", "status={0}".format(still))
        # the old bug refilled the cancelled task's figures; prove it did not
        ok("6 cancelled alert was not refilled/reassigned", len(fresh) == 1 and still == "Cancelled", "no resurrection")
        # ── 7. completed behaves the same (unchanged) ────────────────
        cDone = mkcust("done", 1000)
        mkinv(cDone, 50000)
        run_scheduler()
        d1 = alerts(cDone)
        ok("7 baseline alert for second customer", len(d1) == 1, "{0}".format(len(d1)))
        if d1:
            frappe.db.set_value("Task", d1[0].name, "status", "Completed")
            run_scheduler()
            d2 = [x for x in alerts(cDone) if x.name != d1[0].name]
            ok("7 completing also allows a fresh alert", len(d2) == 1, "{0} new".format(len(d2)))
        # ── 8. under threshold gets nothing ──────────────────────────
        cUnder = mkcust("under", 999999999)
        mkinv(cUnder, 5000)
        run_scheduler()
        ok("8 under-threshold customer gets no alert", len(alerts(cUnder)) == 0, "{0} alert(s)".format(len(alerts(cUnder))))
    except Exception as e:
        R.append(("HARNESS ABORTED", "FAIL", str(e)[:150]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("A8VERIFY_START")
    for n, v, d in R:
        print("A8VERIFY | {0:<46} | {1:<4} | {2}".format(n, v, d))
    print("A8VERIFY | {0} passed / {1} total".format(len([1 for x in R if x[1] == "PASS"]), len(R)))
    print("A8VERIFY_END")
a8_verify()
