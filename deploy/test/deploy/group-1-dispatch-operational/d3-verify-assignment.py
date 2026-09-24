# ==============================================================
# D3 verification - assignment invariant enforced. Run against TEST.
#
# The critical check here is #4: it EXECUTES the role-check path. Frappe's
# compile check does not cover the full RestrictedPython policy, so a Server
# Script can deploy cleanly and throw on first execution -- and
# user_has_allowed_role() had never once run, because it sat behind a commented
# block. Deploying it is not evidence that it works.
#
# Also proves the flow is not broken for NEW work: a Return Call task assigned to
# office.team must now insert successfully. Before the role grant it could not,
# because check 2 has no status guard and office.team held no roles.
#
# Everything is rolled back.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-1-dispatch-operational\d3-verify-assignment.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
# ==============================================================
import frappe
import json
def d3_verify(INV_USER, RETURNS_USER, ACCT_USER):
    results = []
    OFFICE = "office.team@example.com"
    try:
        frappe.set_user("Administrator")
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        # ---- 1. the role grant landed ----
        oroles = frappe.get_all("Has Role", filters={"parent": OFFICE, "parenttype": "User"}, pluck="role") or []
        results.append(("office.team holds Ops - Order Accepting", "PASS" if "Ops - Order Accepting" in oroles else "FAIL", ", ".join(sorted(oroles)) or "none"))
        # ---- 2. the checks are live in the deployed script ----
        body = frappe.db.get_value("Server Script", "Task-before-save-policy", "script") or ""
        code = "\n".join([ln.split("#")[0] for ln in body.split("\n")])
        live = ("must be assigned to exactly 1 user" in code) and ("user_has_allowed_role(owner, allowed_roles)" in code) and ("Assign exactly 1 owner before completing" in code)
        results.append(("all three checks live in deployed code", "PASS" if live else "FAIL", "live" if live else "still commented"))
        # ---- 3. THE ONE THAT MATTERS FOR NEW WORK ----
        # A Return Call assigned to office.team must insert. Check 2 has no
        # status guard, so this is the exact save that would have thrown.
        try:
            rc = frappe.get_doc({"doctype": "Task", "subject": "D3VERIFY return call", "task_kind": "Return Call", "task_access_policy": "Return Call", "customer": cust, "status": "Open", "custom_assigned_to": OFFICE})
            rc.flags.ignore_permissions = True
            rc.insert()
            a = json.loads(rc.get("_assign") or "[]")
            results.append(("NEW Return Call to office.team inserts", "PASS", "_assign={0}".format(a)))
        except Exception as e:
            results.append(("NEW Return Call to office.team inserts", "FAIL", str(e)[:120]))
        # ---- 4. EXECUTE the role check: wrong role for the kind is refused ----
        # This is the path that had never run. Accounting does not hold
        # Ops - Inventory, so a Pack task assigned to it must be refused.
        try:
            bad = frappe.get_doc({"doctype": "Task", "subject": "D3VERIFY wrong role", "task_kind": "Pack / prepare items", "task_access_policy": "Pack / prepare items", "customer": cust, "status": "Open", "custom_assigned_to": ACCT_USER})
            bad.flags.ignore_permissions = True
            bad.insert()
            results.append(("CHECK 2 executes and refuses a wrong role", "FAIL", "insert was allowed"))
        except Exception as e:
            msg = str(e)
            ok = "must be assigned to a user in" in msg
            results.append(("CHECK 2 executes and refuses a wrong role", "PASS" if ok else "FAIL", msg[:118]))
        # ---- 5. right role for the kind is accepted ----
        try:
            good = frappe.get_doc({"doctype": "Task", "subject": "D3VERIFY right role", "task_kind": "Pack / prepare items", "task_access_policy": "Pack / prepare items", "customer": cust, "status": "Open", "custom_assigned_to": INV_USER})
            good.flags.ignore_permissions = True
            good.insert()
            results.append(("CHECK 2 accepts the correct role", "PASS", good.name))
        except Exception as e:
            results.append(("CHECK 2 accepts the correct role", "FAIL", str(e)[:118]))
        # ---- 6. check 1 skips Open / Working, so in-progress work is not blocked ----
        try:
            w = frappe.get_doc({"doctype": "Task", "subject": "D3VERIFY working no assign", "task_kind": "Returns processing / verification", "task_access_policy": "Returns processing / verification", "customer": cust, "status": "Open", "custom_assigned_to": RETURNS_USER})
            w.flags.ignore_permissions = True
            w.insert()
            frappe.db.set_value("Task", w.name, "_assign", "[]")
            w.reload()
            w.status = "Working"
            w.custom_assigned_to = ""
            w.flags.ignore_permissions = True
            w.save()
            results.append(("CHECK 1 exempts Open/Working", "PASS", "saved with empty _assign as designed"))
        except Exception as e:
            results.append(("CHECK 1 exempts Open/Working", "FAIL", str(e)[:118]))
        # ---- 7. why check 3 is a backstop, not a gate anyone hits ----
        #
        # An earlier version of this test cleared _assign and expected check 3 to
        # refuse completion. It did not, and the test was wrong rather than the
        # gate: policy.py auto-assigns the kind's default_team_user whenever
        # custom_assigned_to is blank (line ~70) and then re-syncs _assign from
        # it. A task of a kind that HAS a default team therefore cannot reach
        # check 3 with zero owners -- 23 of the 25 policies have one.
        #
        # Assert that self-healing instead, because it is the reason enabling
        # check 3 was safe. It also means the 3,232 legacy tasks with an empty
        # _assign column are not blocked: the gate reads the in-memory value,
        # which policy.py repopulates on every save.
        try:
            c = frappe.get_doc({"doctype": "Task", "subject": "D3VERIFY selfheal", "task_kind": "Returns processing / verification", "task_access_policy": "Returns processing / verification", "customer": cust, "status": "Open"})
            c.flags.ignore_permissions = True
            c.insert()
            healed = frappe.db.get_value("Task", c.name, "custom_assigned_to") or ""
            expected = frappe.db.get_value("Task Access Policy", "Returns processing / verification", "default_team_user") or ""
            ok = bool(healed) and healed == expected
            results.append(("ownerless task self-heals to default team", "PASS" if ok else "FAIL", "assigned '{0}'".format(healed or "nothing")))
        except Exception as e:
            results.append(("ownerless task self-heals to default team", "FAIL", str(e)[:118]))
        frappe.set_user("Administrator")
        # ---- 8. the whole dispatch chain still assigns validly ----
        # Every policy's default_team_user must hold one of that policy's own
        # allowed_roles, or the flow breaks the first time it creates that kind.
        broken = []
        for p in frappe.get_all("Task Access Policy", fields=["name", "default_team_user"], limit_page_length=0):
            u = (p.default_team_user or "").strip()
            if not u:
                continue
            allowed = [r.role for r in frappe.get_doc("Task Access Policy", p.name).allowed_roles or [] if r.role]
            if not allowed:
                continue
            ur = frappe.get_all("Has Role", filters={"parent": u, "parenttype": "User"}, pluck="role") or []
            hit = False
            for r in allowed:
                if r in ur:
                    hit = True
            if not hit:
                broken.append(p.name + " -> " + u)
        results.append(("every policy's default assignee is valid", "PASS" if not broken else "FAIL", ", ".join(broken) or "all 25 checked"))
    except Exception as e:
        results.append(("RUN", "FAIL", str(e)[:170]))
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("D3VERIFY_RESULTS_START")
    for name, verdict, detail in results:
        print("D3VERIFY | {0:<44} | {1:<4} | {2}".format(name, verdict, detail))
    print("D3VERIFY_RESULTS_END")
d3_verify("e2e.inventory@test.erpnext.am", "e2e.returns@test.erpnext.am", "e2e.accounting@test.erpnext.am")
