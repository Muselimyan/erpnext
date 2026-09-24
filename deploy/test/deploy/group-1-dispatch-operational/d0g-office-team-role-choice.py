# ==============================================================
# D0g - which single role satisfies every policy office.team is default for?
# READ ONLY. Confirms the D3 pre-requisite before granting anything.
# ==============================================================
import frappe
def d0g():
    lines = []
    target = "office.team@example.com"
    pols = frappe.get_all("Task Access Policy", filters={"default_team_user": target}, fields=["name"], limit_page_length=0)
    sets = []
    for p in sorted([x.name for x in pols]):
        allowed = [r.role for r in frappe.get_doc("Task Access Policy", p).allowed_roles or [] if r.role]
        sets.append(set(allowed))
        lines.append("D0G | policy {0:<22} | allowed: {1}".format(p, ", ".join(sorted(allowed))))
    common = set.intersection(*sets) if sets else set()
    lines.append("D0G | " + "-" * 88)
    lines.append("D0G | policies defaulting to {0}: {1}".format(target, len(pols)))
    lines.append("D0G | roles common to ALL of them: {0}".format(", ".join(sorted(common)) or "NONE - one role cannot fix all four"))
    held = frappe.get_all("Has Role", filters={"parent": target, "parenttype": "User"}, pluck="role") or []
    lines.append("D0G | {0} currently holds: {1}".format(target, ", ".join(sorted(held)) or "NO ROLES AT ALL"))
    # Sanity: do the other team placeholders hold roles? If office.team is the
    # only one without, granting is clearly the right fix rather than editing
    # four policies.
    others = frappe.get_all("User", filters={"name": ["like", "%.team@example.com"]}, pluck="name") or []
    for u in sorted(others):
        ur = frappe.get_all("Has Role", filters={"parent": u, "parenttype": "User"}, pluck="role") or []
        ops = [r for r in ur if r.startswith("Ops")]
        lines.append("D0G | placeholder {0:<32} | {1}".format(u, ", ".join(sorted(ops)) or "NO Ops-* ROLE"))
    print("D0G_RESULTS_START")
    for ln in lines:
        print(ln)
    print("D0G_RESULTS_END")
    frappe.db.rollback()
d0g()
