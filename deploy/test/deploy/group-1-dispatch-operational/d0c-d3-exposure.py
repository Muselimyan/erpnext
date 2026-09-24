# ==============================================================
# D0c - D3 true exposure. READ ONLY.
#
# D0 measured the role check only over tasks that TODAY have exactly one
# assignee (1,463 of 4,696). The other 3,233 fail the assignee-count check first
# and never reach it. Backfilling _assign therefore does not just fix check 1 --
# it exposes 3,231 more tasks to check 2.
#
# This measures the real post-backfill number, so D3 is scoped against what it
# would actually block rather than what it blocks today.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-1-dispatch-operational\d0c-d3-exposure.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
# ==============================================================
import frappe
import json
def d0c():
    lines = []
    def emit(section, label, value, note=""):
        lines.append("D0C | {0:<8} | {1:<50} | {2:<7} | {3}".format(section, label, str(value), note))
    opentasks = frappe.get_all("Task", filters={"status": ["not in", ["Completed", "Cancelled"]]}, fields=["name", "task_kind", "status", "_assign", "custom_assigned_to", "creation"], limit_page_length=0)
    polcache = {}
    rolecache = {}
    def allowed_for(kind):
        if kind not in polcache:
            a = []
            if kind and frappe.db.exists("Task Access Policy", kind):
                a = [r.role for r in frappe.get_doc("Task Access Policy", kind).allowed_roles or [] if r.role]
            polcache[kind] = a
        return polcache[kind]
    def roles_of(u):
        if u not in rolecache:
            rolecache[u] = frappe.get_all("Has Role", filters={"parent": u, "parenttype": "User"}, pluck="role") or []
        return rolecache[u]
    now_fail = 0
    post_fail = 0
    post_fail_kind = {}
    post_fail_user = {}
    backfilled = 0
    for t in opentasks:
        try:
            assigned = json.loads(t.get("_assign") or "[]") or []
        except Exception:
            assigned = []
        effective = ""
        if len(assigned) == 1:
            effective = assigned[0]
        elif len(assigned) == 0 and (t.custom_assigned_to or "").strip():
            effective = t.custom_assigned_to.strip()
            backfilled += 1
        if not effective or not t.task_kind:
            continue
        a = allowed_for(t.task_kind)
        if not a:
            continue
        ok = any(r in roles_of(effective) for r in a)
        if not ok:
            post_fail += 1
            post_fail_kind[t.task_kind] = post_fail_kind.get(t.task_kind, 0) + 1
            post_fail_user[effective] = post_fail_user.get(effective, 0) + 1
            if len(assigned) == 1:
                now_fail += 1
    emit("D3", "open tasks", len(opentasks))
    emit("D3", "  would be backfilled from custom_assigned_to", backfilled)
    emit("D3", "role failures TODAY (1-assignee tasks only)", now_fail)
    emit("D3", "role failures AFTER backfill", post_fail, "this is the real D3 blocker count")
    for k in sorted(post_fail_kind, key=lambda x: -post_fail_kind[x])[:12]:
        emit("D3-KIND", "  " + k, post_fail_kind[k], "allowed: " + ", ".join(allowed_for(k))[:52])
    for u in sorted(post_fail_user, key=lambda x: -post_fail_user[x])[:10]:
        emit("D3-USER", "  " + u, post_fail_user[u], ", ".join(sorted(roles_of(u))[:3])[:52] or "NO ROLES")
    # the Administrator-owned population: are they real work or seed data?
    admin_tasks = [t for t in opentasks if (t.custom_assigned_to or "") == "Administrator" or (t.get("_assign") or "").find("Administrator") >= 0]
    emit("ADMIN", "open tasks owned by Administrator", len(admin_tasks))
    ak = {}
    for t in admin_tasks:
        ak[t.task_kind or "(none)"] = ak.get(t.task_kind or "(none)", 0) + 1
    for k in sorted(ak, key=lambda x: -ak[x])[:8]:
        emit("ADMIN", "  kind " + k, ak[k])
    if admin_tasks:
        ds = sorted([str(t.creation)[:10] for t in admin_tasks])
        emit("ADMIN", "  created between", ds[0], "and " + ds[-1])
    # confirm the no-SLE population is exactly the blank-source Material Issues
    mi_blank = frappe.db.sql("""select count(distinct se.name) from `tabStock Entry` se join `tabStock Entry Detail` sed on sed.parent=se.name where se.docstatus=1 and se.purpose='Material Issue' and ifnull(sed.s_warehouse,'')=''""")
    nosle = frappe.db.sql("""select count(*) from `tabStock Entry` se where se.docstatus=1 and not exists (select 1 from `tabStock Ledger Entry` sle where sle.voucher_type='Stock Entry' and sle.voucher_no=se.name and sle.is_cancelled=0)""")
    emit("PHANTOM", "Material Issues with blank source warehouse", mi_blank[0][0] if mi_blank else 0)
    emit("PHANTOM", "submitted SEs with no ledger entry at all", nosle[0][0] if nosle else 0, "if equal, the transfers DID post one-sided")
    mt_onesided = frappe.db.sql("""select count(distinct se.name) from `tabStock Entry` se join `tabStock Entry Detail` sed on sed.parent=se.name where se.docstatus=1 and se.purpose='Material Transfer' and (ifnull(sed.s_warehouse,'')='' or ifnull(sed.t_warehouse,'')='') and exists (select 1 from `tabStock Ledger Entry` sle where sle.voucher_no=se.name and sle.is_cancelled=0)""")
    emit("PHANTOM", "one-sided Material Transfers that DID post", mt_onesided[0][0] if mt_onesided else 0, "stock created or destroyed, not moved")
    print("D0C_RESULTS_START")
    for ln in lines:
        print(ln)
    print("D0C_RESULTS_END")
    frappe.db.rollback()
d0c()
