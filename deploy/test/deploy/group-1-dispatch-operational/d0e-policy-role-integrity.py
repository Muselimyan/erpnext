# ==============================================================
# D0e - Task Access Policy integrity. READ ONLY.
#
# The question this answers: if D3's role check is enforced, does the flow still
# work for NEW tasks? Every task the orchestrator creates is assigned to its
# policy's default_team_user. If that user does not hold one of the policy's own
# allowed_roles, check 2 throws on the very first save -- and check 2 has no
# status guard.
#
# That is not legacy test data. It is a live configuration defect that would
# block new work, so it has to be answered before D3 can be called safe.
#
# office.team@example.com is known to hold NO roles at all (D0b) and to own 399
# role failures, so the concern is concrete.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-1-dispatch-operational\d0e-policy-role-integrity.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
# ==============================================================
import frappe
def d0e():
    rows = []
    fails = []
    pols = frappe.get_all("Task Access Policy", fields=["name", "default_team_user"], limit_page_length=0)
    for p in sorted(pols, key=lambda x: x.name):
        u = (p.default_team_user or "").strip()
        allowed = [r.role for r in frappe.get_doc("Task Access Policy", p.name).allowed_roles or [] if r.role]
        if not u:
            rows.append((p.name, "(blank)", "NOASSIGN", ", ".join(allowed)[:44]))
            continue
        uroles = frappe.get_all("Has Role", filters={"parent": u, "parenttype": "User"}, pluck="role") or []
        if not allowed:
            rows.append((p.name, u, "NOROLES", "policy lists no allowed_roles"))
            continue
        ok = False
        for r in allowed:
            if r in uroles:
                ok = True
        rows.append((p.name, u, "OK" if ok else "FAILS", ", ".join(allowed)[:44]))
        if not ok:
            fails.append((p.name, u, ", ".join(sorted(uroles)[:4]) or "NO ROLES AT ALL"))
    print("D0E_RESULTS_START")
    for n, u, v, a in rows:
        print("D0E | {0:<42} | {1:<30} | {2:<8} | {3}".format(n, u, v, a))
    print("D0E | " + "-" * 96)
    print("D0E SUMMARY | policies checked            | {0}".format(len(rows)))
    print("D0E SUMMARY | default_team_user FAILS     | {0}  <- new tasks of these kinds break under D3 check 2".format(len(fails)))
    for n, u, ur in fails:
        print("D0E FAIL    | {0:<42} | {1:<30} | holds: {2}".format(n, u, ur))
    print("D0E_RESULTS_END")
    frappe.db.rollback()
d0e()
