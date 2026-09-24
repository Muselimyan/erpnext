# ==============================================================
# D0b - drill-down on the two D0 findings that were far worse than the plan
# assumed. READ ONLY.
#
#   1. 3,233 of 4,696 open tasks have _assign != exactly 1 user (D3 gate)
#   2. 372 submitted Stock Entries carry warehouse-less rows (D1 migration)
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-1-dispatch-operational\d0b-drilldown.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
# ==============================================================
import frappe
import json
def d0b():
    lines = []
    def emit(section, label, value, note=""):
        lines.append("D0B | {0:<9} | {1:<52} | {2:<7} | {3}".format(section, label, str(value), note))
    # ---------- 1. why do 3233 open tasks fail the assignment check ----------
    opentasks = frappe.get_all("Task", filters={"status": ["not in", ["Completed", "Cancelled"]]}, fields=["name", "task_kind", "status", "_assign", "custom_assigned_to"], limit_page_length=0)
    zero_assign = []
    multi_assign = []
    by_kind = {}
    blank_cat = 0
    for t in opentasks:
        try:
            assigned = json.loads(t.get("_assign") or "[]") or []
        except Exception:
            assigned = []
        if len(assigned) == 1:
            continue
        k = t.task_kind or "(no kind)"
        by_kind[k] = by_kind.get(k, 0) + 1
        if len(assigned) == 0:
            zero_assign.append(t)
            if not (t.custom_assigned_to or "").strip():
                blank_cat += 1
        else:
            multi_assign.append(t)
    emit("ASSIGN", "open tasks failing the exactly-1 check", len(zero_assign) + len(multi_assign))
    emit("ASSIGN", "  _assign EMPTY (0 users)", len(zero_assign))
    emit("ASSIGN", "    of those, custom_assigned_to also blank", blank_cat, "policy had no default_team_user to apply")
    emit("ASSIGN", "    of those, custom_assigned_to IS set", len(zero_assign) - blank_cat, "_assign never synced - repairable by resave")
    emit("ASSIGN", "  _assign has MORE than 1 user", len(multi_assign))
    for k in sorted(by_kind, key=lambda x: -by_kind[x])[:14]:
        emit("ASSIGN", "  kind " + k, by_kind[k])
    # is the empty-_assign population concentrated in the 2 blank-TAP kinds?
    policies = frappe.get_all("Task Access Policy", fields=["name", "default_team_user"], limit_page_length=0)
    blankpol = [p.name for p in policies if not (p.default_team_user or "").strip()]
    inblank = len([t for t in zero_assign if (t.task_kind or "") in blankpol])
    emit("ASSIGN", "  empty-_assign tasks in a blank-TAP kind", inblank, "kinds: " + ", ".join(blankpol))
    # how many are repairable purely by re-syncing _assign from custom_assigned_to
    emit("ASSIGN", "  REPAIRABLE by _assign resync", len(zero_assign) - blank_cat, "policy.py already does this on save")
    # ---------- 2. the 701 role violations ----------
    polcache = {}
    rolecache = {}
    bad_role_kind = {}
    bad_role_user = {}
    for t in opentasks:
        try:
            assigned = json.loads(t.get("_assign") or "[]") or []
        except Exception:
            assigned = []
        if len(assigned) != 1 or not t.task_kind:
            continue
        owner = assigned[0]
        if t.task_kind not in polcache:
            allowed = []
            if frappe.db.exists("Task Access Policy", t.task_kind):
                pol = frappe.get_doc("Task Access Policy", t.task_kind)
                allowed = [r.role for r in (pol.allowed_roles or []) if r.role]
            polcache[t.task_kind] = allowed
        allowed = polcache[t.task_kind]
        if not allowed:
            continue
        if owner not in rolecache:
            rolecache[owner] = frappe.get_all("Has Role", filters={"parent": owner, "parenttype": "User"}, pluck="role") or []
        if not any(r in rolecache[owner] for r in allowed):
            bad_role_kind[t.task_kind] = bad_role_kind.get(t.task_kind, 0) + 1
            bad_role_user[owner] = bad_role_user.get(owner, 0) + 1
    for k in sorted(bad_role_kind, key=lambda x: -bad_role_kind[x])[:10]:
        emit("ROLE", "  kind " + k, bad_role_kind[k], "allowed: " + ", ".join(polcache.get(k, []))[:60])
    for u in sorted(bad_role_user, key=lambda x: -bad_role_user[x])[:10]:
        emit("ROLE", "  owner " + u, bad_role_user[u])
    # ---------- 3. e2e.delivery has no Ops role - what does it have ----------
    dl = frappe.get_all("Has Role", filters={"parent": "e2e.delivery@test.erpnext.am", "parenttype": "User"}, pluck="role") or []
    emit("E2E", "e2e.delivery roles", len(dl), ", ".join(sorted(dl)) or "NONE AT ALL")
    dp = frappe.db.get_value("Task Access Policy", "Delivery", "default_team_user")
    dpr = []
    if frappe.db.exists("Task Access Policy", "Delivery"):
        dpr = [r.role for r in frappe.get_doc("Task Access Policy", "Delivery").allowed_roles or [] if r.role]
    emit("E2E", "TAP 'Delivery' allowed_roles", len(dpr), ", ".join(dpr))
    # ---------- 4. the 372 phantom Stock Entries - what and when ----------
    ph = frappe.db.sql("""select se.name, se.purpose, se.creation, se.owner from `tabStock Entry` se where se.docstatus=1 and exists (select 1 from `tabStock Entry Detail` sed where sed.parent=se.name and ((se.purpose='Material Issue' and ifnull(sed.s_warehouse,'')='') or (se.purpose='Material Receipt' and ifnull(sed.t_warehouse,'')='') or (se.purpose='Material Transfer' and (ifnull(sed.s_warehouse,'')='' or ifnull(sed.t_warehouse,'')='')))) order by se.creation""", as_dict=True)
    bypurpose = {}
    for r in ph:
        bypurpose[r.purpose] = bypurpose.get(r.purpose, 0) + 1
    for p in sorted(bypurpose, key=lambda x: -bypurpose[x]):
        emit("PHANTOM", "  purpose " + p, bypurpose[p])
    if ph:
        emit("PHANTOM", "  earliest", str(ph[0].creation)[:19], ph[0].name)
        emit("PHANTOM", "  latest", str(ph[-1].creation)[:19], ph[-1].name)
    linked = frappe.db.sql("""select count(distinct dc.name) from `tabDispatch Case` dc where dc.dispatch_stock_entry in (select se.name from `tabStock Entry` se where se.docstatus=1) or dc.delivery_stock_entry in (select se.name from `tabStock Entry` se where se.docstatus=1) or dc.consumption_stock_entry in (select se.name from `tabStock Entry` se where se.docstatus=1)""")
    emit("PHANTOM", "cases linked to any submitted SE", linked[0][0] if linked else 0)
    # ---------- 5. do the 77 stock-holding cases overlap the blank-warehouse 1230 ----------
    HOLD = ["Packed", "In Transit", "Awaiting Return Pickup", "Return Pickup Scheduled", "Return In Transit", "Returns Received"]
    holdcases = frappe.get_all("Dispatch Case", filters={"docstatus": ["!=", 2], "status": ["in", HOLD]}, fields=["name", "status", "client_location_warehouse"], limit_page_length=0)
    hblank = [c for c in holdcases if not (c.client_location_warehouse or "").strip()]
    hmain = [c for c in holdcases if (c.client_location_warehouse or "") == "Main - Inmed"]
    emit("OVERLAP", "stock-holding cases", len(holdcases))
    emit("OVERLAP", "  with BLANK client warehouse", len(hblank), "these cannot move forward even today")
    emit("OVERLAP", "  with warehouse = Main", len(hmain))
    emit("OVERLAP", "  with a usable client warehouse", len(holdcases) - len(hblank) - len(hmain), "Path A could drive only these")
    print("D0B_RESULTS_START")
    for ln in lines:
        print(ln)
    print("D0B_RESULTS_END")
    frappe.db.rollback()
d0b()
