# ==============================================================
# D0d - D3 real impact if we deploy WITHOUT fixing data. READ ONLY.
#
# The three disabled checks have different trigger conditions, so the blast
# radius is not the raw violation count:
#
#   check 1 (exactly-1 assignee)  guarded by: status NOT IN (Cancelled, Open,
#                                Working) AND not becoming Working
#   check 2 (owner holds role)    NO status guard -- fires on EVERY save of a
#                                task that has exactly one assignee
#   check 3 (1 assignee to close) fires only when completing
#
# So tasks with an EMPTY _assign skip check 2 entirely, and are only caught by
# check 1 if they sit outside Open/Working. This measures what would actually
# break on day one.
#
# Also picks safe items for D1 verification.
#
# Usage (from repo root):
#   Get-Content deploy\test\deploy\group-1-dispatch-operational\d0d-d3-real-impact.py |
#     ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156
#       "docker exec -i frappe-test-backend-1 bench --site test.erpnext.am console"
# ==============================================================
import frappe
import json
def d0d():
    lines = []
    def emit(section, label, value, note=""):
        lines.append("D0D | {0:<9} | {1:<48} | {2:<7} | {3}".format(section, label, str(value), note))
    opentasks = frappe.get_all("Task", filters={"status": ["not in", ["Completed", "Cancelled"]]}, fields=["name", "task_kind", "status", "_assign", "custom_assigned_to"], limit_page_length=0)
    polcache = {}
    rolecache = {}
    c1_blocked = 0
    c1_exempt = 0
    c2_blocked = 0
    c3_only = 0
    c1_by_status = {}
    for t in opentasks:
        try:
            assigned = json.loads(t.get("_assign") or "[]") or []
        except Exception:
            assigned = []
        n = len(assigned)
        # check 1: only bites outside Open / Working
        if n != 1:
            if t.status not in ("Cancelled", "Open", "Working"):
                c1_blocked += 1
                c1_by_status[t.status] = c1_by_status.get(t.status, 0) + 1
            else:
                c1_exempt += 1
                c3_only += 1
        # check 2: no status guard, but only applies when exactly 1 assignee
        if n == 1 and t.task_kind:
            if t.task_kind not in polcache:
                a = []
                if frappe.db.exists("Task Access Policy", t.task_kind):
                    a = [r.role for r in frappe.get_doc("Task Access Policy", t.task_kind).allowed_roles or [] if r.role]
                polcache[t.task_kind] = a
            allowed = polcache[t.task_kind]
            if allowed:
                owner = assigned[0]
                if owner not in rolecache:
                    rolecache[owner] = frappe.get_all("Has Role", filters={"parent": owner, "parenttype": "User"}, pluck="role") or []
                if not any(r in rolecache[owner] for r in allowed):
                    c2_blocked += 1
    emit("IMPACT", "open tasks", len(opentasks))
    emit("IMPACT", "CHECK 1 blocks on any save", c1_blocked, "status outside Open/Working with _assign != 1")
    for s in sorted(c1_by_status, key=lambda x: -c1_by_status[x]):
        emit("IMPACT", "   status " + s, c1_by_status[s])
    emit("IMPACT", "CHECK 1 exempt (Open/Working)", c1_exempt, "editable, but check 3 blocks COMPLETION")
    emit("IMPACT", "CHECK 2 blocks on any save", c2_blocked, "no status guard - this is the harsh one")
    emit("IMPACT", "CHECK 3 blocks completion only", c3_only, "these can be edited but never completed")
    emit("IMPACT", "TOTAL immediately unsaveable", c1_blocked + c2_blocked, "check1 + check2")
    # what fraction of ALL open tasks is that
    tot = len(opentasks) or 1
    emit("IMPACT", "  as pct of open tasks", "{0:.1f}%".format(100.0 * (c1_blocked + c2_blocked) / tot))
    # ---------- safe items for D1 verification ----------
    MAIN = "Main - Inmed"
    bins = frappe.get_all("Bin", filters={"warehouse": MAIN, "actual_qty": [">", 5]}, fields=["item_code", "actual_qty", "valuation_rate"], order_by="actual_qty desc", limit_page_length=40)
    good = [b for b in bins if b.valuation_rate and float(b.valuation_rate) > 0]
    emit("D1-ITEMS", "Main items with qty>5 and valuation>0", len(good), "sample pool for verification")
    for b in good[:8]:
        pr = frappe.db.get_value("Item Price", {"item_code": b.item_code, "price_list": "Standard Selling", "price_list_rate": [">", 0]}, "price_list_rate")
        emit("D1-ITEMS", "   " + b.item_code, "{0:.0f} @ {1:.2f}".format(float(b.actual_qty), float(b.valuation_rate)), "sell price: " + (str(pr) if pr else "NONE - unusable, order entry will refuse"))
    negitems = frappe.get_all("Bin", filters={"warehouse": MAIN, "actual_qty": ["<", 0]}, pluck="item_code", limit_page_length=0)
    emit("D1-ITEMS", "items NEGATIVE in Main (avoid these)", len(negitems), ", ".join(sorted(negitems)[:6]))
    print("D0D_RESULTS_START")
    for ln in lines:
        print(ln)
    print("D0D_RESULTS_END")
    frappe.db.rollback()
d0d()
