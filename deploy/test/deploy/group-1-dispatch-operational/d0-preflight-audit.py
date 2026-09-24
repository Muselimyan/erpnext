# ==============================================================
# D0 - Group 1 pre-flight audit. READ ONLY.
#
# Produces the go/no-go for D1 (restore stock validation), D3 (re-enable
# assignment validation) and D4 (retire legacy task kinds), and closes the last
# two V-01 items that are master data and therefore absent from the schema
# export.
#
# Writes nothing. Ends with an explicit rollback as a belt-and-braces guard.
#
# Run as Administrator: this is an inventory of state, not a permission test.
# The permission tests in d1..d6-verify-*.py run as the e2e role users, which is
# exactly what section 1 below checks the existence of.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-1-dispatch-operational\d0-preflight-audit.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
#
# NOTE: single function, no blank lines in the body. IPython treats a blank line
# as end-of-block when code is piped in, and does not expose module globals to
# the function body. Comment lines are fine.
# ==============================================================
import frappe
import json
def d0_preflight():
    MAIN = "Main - Inmed"
    OPWH = ["Delivery In-Transit - Inmed", "Return Pickup In-Transit - Inmed", "Returns - Inmed", "Lost & Damaged - Inmed"]
    HOLDING_STATUSES = ["Packed", "In Transit", "Awaiting Return Pickup", "Return Pickup Scheduled", "Return In Transit", "Returns Received"]
    RETIRING_KINDS = ["Order accepting", "Dispatch picking / hand-off"]
    HOLDING_KINDS = ["Order accepting", "Dispatch picking / hand-off", "Return drop-off at warehouse", "Return to warehouse (aborted delivery / cancelled order)"]
    lines = []
    def emit(section, label, value, note=""):
        lines.append("D0 | {0:<10} | {1:<46} | {2:<8} | {3}".format(section, label, str(value), note))
    # ---------- 1. e2e role users (gates ALL verification) ----------
    e2e_users = frappe.get_all("User", filters={"name": ["like", "e2e.%"]}, fields=["name", "enabled"], limit_page_length=0)
    emit("USERS", "e2e.* users found", len(e2e_users), "verification is impossible without these")
    for u in e2e_users:
        uroles = frappe.get_all("Has Role", filters={"parent": u.name, "parenttype": "User"}, pluck="role") or []
        ops = [r for r in uroles if r.startswith("Ops")]
        emit("USERS", "  " + u.name, "en" if u.enabled else "DISABLED", ", ".join(sorted(ops)) or "NO Ops-* ROLE")
    all_ops_roles = sorted([r.name for r in frappe.get_all("Role", filters={"name": ["like", "Ops%"]}, fields=["name"], limit_page_length=0)])
    for r in all_ops_roles:
        holders = frappe.get_all("Has Role", filters={"role": r, "parenttype": "User"}, pluck="parent") or []
        live = [h for h in holders if frappe.db.get_value("User", h, "enabled")]
        emit("USERS", "  role " + r, len(live), ", ".join(sorted(live)[:6]))
    # ---------- 2. V-01 remainder (master data, not in the export) ----------
    emit("V01", "Warehouse 'Lost & Damaged - Inmed'", "YES" if frappe.db.exists("Warehouse", "Lost & Damaged - Inmed") else "MISSING")
    wo_policy = frappe.db.get_value("Task Access Policy", "Write-off Approval", "default_team_user")
    emit("V01", "TAP 'Write-off Approval'.default_team_user", wo_policy or "MISSING", "w12 pre-flight requires this")
    # ---------- 3. D1: stock sitting in operational warehouses ----------
    opbins = frappe.get_all("Bin", filters={"warehouse": ["in", OPWH], "actual_qty": ["!=", 0]}, fields=["warehouse", "item_code", "actual_qty", "valuation_rate"], limit_page_length=0)
    emit("D1-STOCK", "rows with stock in operational warehouses", len(opbins))
    for w in OPWH:
        rows = [b for b in opbins if b.warehouse == w]
        zero = [b for b in rows if not b.valuation_rate or float(b.valuation_rate) <= 0]
        emit("D1-STOCK", "  " + w, len(rows), "{0} of them zero-valued".format(len(zero)))
    # ---------- 4. D1: Main - Inmed health ----------
    negbins = frappe.get_all("Bin", filters={"warehouse": MAIN, "actual_qty": ["<", 0]}, fields=["item_code", "actual_qty"], limit_page_length=0)
    emit("D1-MAIN", "items at NEGATIVE stock in Main", len(negbins), "sum {0}".format(sum([float(b.actual_qty) for b in negbins]) if negbins else 0))
    posbins = frappe.get_all("Bin", filters={"warehouse": MAIN, "actual_qty": [">", 0]}, fields=["item_code", "actual_qty", "valuation_rate"], limit_page_length=0)
    unvalued = [b for b in posbins if not b.valuation_rate or float(b.valuation_rate) <= 0]
    emit("D1-MAIN", "items with stock in Main", len(posbins))
    emit("D1-MAIN", "  of which UN-VALUED", len(unvalued), "these refuse to be consumed under strict rules")
    # ---------- 5. D1: can Main be re-valued? (needs purchase history) ----------
    no_history = []
    for b in unvalued:
        pr = frappe.db.sql("""select 1 from `tabPurchase Receipt Item` pri join `tabPurchase Receipt` pr on pr.name=pri.parent where pr.docstatus=1 and pri.item_code=%s limit 1""", (b.item_code,))
        if not pr:
            no_history.append(b.item_code)
    emit("D1-MAIN", "  un-valued AND no purchase history", len(no_history), "cannot be defensibly valued: " + ", ".join(sorted(no_history)[:8]))
    # ---------- 6. D1: phantom Stock Entries (submitted, posted nothing) ----------
    phantom_rows = frappe.db.sql("""select se.name, se.stock_entry_type, count(*) as rows_bad from `tabStock Entry Detail` sed join `tabStock Entry` se on se.name=sed.parent where se.docstatus=1 and ((se.purpose='Material Issue' and ifnull(sed.s_warehouse,'')='') or (se.purpose='Material Receipt' and ifnull(sed.t_warehouse,'')='') or (se.purpose='Material Transfer' and (ifnull(sed.s_warehouse,'')='' or ifnull(sed.t_warehouse,'')=''))) group by se.name, se.stock_entry_type""", as_dict=True)
    emit("D1-PHANT", "submitted SEs with warehouse-less rows", len(phantom_rows), "sum rows {0}".format(sum([r.rows_bad for r in phantom_rows])))
    nosle = frappe.db.sql("""select se.name from `tabStock Entry` se where se.docstatus=1 and not exists (select 1 from `tabStock Ledger Entry` sle where sle.voucher_type='Stock Entry' and sle.voucher_no=se.name and sle.is_cancelled=0)""", as_dict=True)
    emit("D1-PHANT", "submitted SEs that produced NO ledger entry", len(nosle), "the original symptom")
    # ---------- 7. D1: Dispatch Case warehouse data errors ----------
    cases = frappe.get_all("Dispatch Case", filters={"docstatus": ["!=", 2]}, fields=["name", "status", "docstatus", "client_location_warehouse", "return_expected"], limit_page_length=0)
    blank_wh = [c for c in cases if not (c.client_location_warehouse or "").strip()]
    main_wh = [c for c in cases if (c.client_location_warehouse or "") == MAIN]
    emit("D1-CASE", "cases total (not cancelled)", len(cases))
    emit("D1-CASE", "  client_location_warehouse BLANK", len(blank_wh), "blocks strict mode if they move again")
    emit("D1-CASE", "  client_location_warehouse = Main", len(main_wh), "data error: " + ", ".join([c.name for c in main_wh][:8]))
    # ---------- 8. D1: which cases actually hold operational stock ----------
    open_restock = frappe.get_all("Task", filters={"task_kind": "Returns restocking", "status": ["not in", ["Completed", "Cancelled"]], "dispatch_case": ["!=", ""]}, pluck="dispatch_case", limit_page_length=0) or []
    open_writeoff = frappe.get_all("Task", filters={"task_kind": "Write-off Approval", "status": ["not in", ["Completed", "Cancelled"]], "dispatch_case": ["!=", ""]}, pluck="dispatch_case", limit_page_length=0) or []
    by_status = {}
    for c in cases:
        by_status[c.status] = by_status.get(c.status, 0) + 1
    for s in sorted(by_status.keys()):
        flag = "HOLDS STOCK" if s in HOLDING_STATUSES else ""
        emit("D1-FLIGHT", "  status " + s, by_status[s], flag)
    holding = set([c.name for c in cases if c.status in HOLDING_STATUSES])
    holding = holding | set(open_restock) | set(open_writeoff)
    emit("D1-FLIGHT", "open Returns restocking tasks", len(set(open_restock)), "stock parked in Returns - Inmed")
    emit("D1-FLIGHT", "open Write-off Approval tasks", len(set(open_writeoff)), "stock parked in Lost & Damaged")
    emit("D1-FLIGHT", "STOCK-HOLDING IN-FLIGHT CASES", len(holding), "<=15 -> Path A drive forward; >15 -> Path B reconcile+abandon")
    resting_delivered = [c.name for c in cases if c.status == "Delivered"]
    emit("D1-FLIGHT", "cases RESTING in 'Delivered'", len(resting_delivered), "ANY is a hard stop: partial handler failure. " + ", ".join(resting_delivered[:8]))
    # ---------- 9. D3: Task Access Policy completeness ----------
    policies = frappe.get_all("Task Access Policy", fields=["name", "default_team_user"], limit_page_length=0)
    blank_team = [p.name for p in policies if not (p.default_team_user or "").strip()]
    emit("D3-TAP", "Task Access Policy records", len(policies))
    emit("D3-TAP", "  with BLANK default_team_user", len(blank_team), ", ".join(sorted(blank_team)[:10]))
    # ---------- 10. D3: assignment invariant violations on open tasks ----------
    opentasks = frappe.get_all("Task", filters={"status": ["not in", ["Completed", "Cancelled"]]}, fields=["name", "task_kind", "status", "_assign", "custom_assigned_to"], limit_page_length=0)
    bad_count = []
    bad_role = []
    rolecache = {}
    polcache = {}
    for t in opentasks:
        try:
            assigned = json.loads(t.get("_assign") or "[]") or []
        except Exception:
            assigned = []
        if len(assigned) != 1:
            bad_count.append((t.name, t.task_kind, len(assigned)))
            continue
        owner = assigned[0]
        if not t.task_kind:
            continue
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
            bad_role.append((t.name, t.task_kind, owner))
    emit("D3-ASSIGN", "open tasks", len(opentasks))
    emit("D3-ASSIGN", "  with _assign != exactly 1 user", len(bad_count), "D3 BLOCKS these. " + ", ".join([b[0] for b in bad_count][:6]))
    emit("D3-ASSIGN", "  whose owner lacks the kind's role", len(bad_role), "D3 BLOCKS these. " + ", ".join([b[0] + "/" + b[2] for b in bad_role][:4]))
    # ---------- 11. D4: tasks in the kinds we want to retire ----------
    for k in HOLDING_KINDS:
        n = frappe.db.count("Task", {"task_kind": k})
        nopen = frappe.db.count("Task", {"task_kind": k, "status": ["not in", ["Completed", "Cancelled"]]})
        retiring = "RETIRING - must be 0" if k in RETIRING_KINDS else "holding, not retired yet"
        emit("D4-KIND", "  " + k, n, "{0} open. {1}".format(nopen, retiring))
    # ---------- 12. verdicts ----------
    v = []
    v.append(("D1 path", "Path A (drive forward)" if len(holding) <= 15 else "Path B (reconcile+abandon)", "{0} stock-holding cases".format(len(holding))))
    v.append(("D1 hard stop", "BLOCKED" if resting_delivered else "clear", "{0} cases resting in Delivered".format(len(resting_delivered))))
    v.append(("D3 gate", "BLOCKED" if (bad_count or bad_role or blank_team) else "GO", "{0} assign / {1} role / {2} blank TAP".format(len(bad_count), len(bad_role), len(blank_team))))
    retiring_open = sum([frappe.db.count("Task", {"task_kind": k}) for k in RETIRING_KINDS])
    v.append(("D4 gate", "BLOCKED" if retiring_open else "GO", "{0} tasks in retiring kinds".format(retiring_open)))
    v.append(("verification", "BLOCKED" if not e2e_users else "GO", "{0} e2e users".format(len(e2e_users))))
    print("D0_RESULTS_START")
    for ln in lines:
        print(ln)
    print("D0 | " + "-" * 92)
    for name, verdict, detail in v:
        print("D0 VERDICT | {0:<14} | {1:<26} | {2}".format(name, verdict, detail))
    print("D0_RESULTS_END")
    frappe.db.rollback()
d0_preflight()
