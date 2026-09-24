# ==============================================================
# D3b - two questions the first verify run raised. READ ONLY except for
# rolled-back fixtures.
#
# Q1. A Return Call inserted with custom_assigned_to set came back with
#     _assign = []. Does policy.py's sync actually persist on insert, or is
#     _assign recalculated by the framework from ToDo afterwards? This matters:
#     check 3 blocks completion when _assign does not hold exactly one user, so
#     if the sync does not persist, tasks created outside make_task() cannot be
#     completed.
#
# Q2. CHECK 3 reported "completion was allowed" when _assign was cleared. The
#     suspicion is that the test was wrong, not the gate: policy.py re-syncs
#     _assign from custom_assigned_to on EVERY save, so clearing only _assign
#     leaves the gate seeing one owner again. Clear BOTH and re-test.
#
# If Q2 confirms self-healing, that is good news for the 3,231 legacy tasks with
# an empty _assign but custom_assigned_to set -- they repair themselves on their
# next save rather than needing a backfill.
# ==============================================================
import frappe
import json
def d3b(RETURNS_USER):
    out = []
    def emit(k, v, note=""):
        out.append("D3B | {0:<44} | {1:<6} | {2}".format(k, str(v), note))
    try:
        frappe.set_user("Administrator")
        cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
        # ---- Q1: does the before_save sync persist through insert? ----
        t = frappe.get_doc({"doctype": "Task", "subject": "D3B persistence", "task_kind": "Returns processing / verification", "task_access_policy": "Returns processing / verification", "customer": cust, "status": "Open", "custom_assigned_to": RETURNS_USER})
        t.flags.ignore_permissions = True
        t.insert()
        inmem = t.get("_assign")
        indb = frappe.db.get_value("Task", t.name, "_assign")
        emit("Q1 _assign in memory after insert", json.dumps(inmem))
        emit("Q1 _assign in DB after insert", json.dumps(indb))
        emit("Q1 sync persists", "YES" if (indb and indb != "[]") else "NO", "if NO, tasks made outside make_task cannot complete")
        # ---- does a plain resave repair it? ----
        frappe.db.set_value("Task", t.name, "_assign", "[]")
        t.reload()
        t.flags.ignore_permissions = True
        t.save()
        after = frappe.db.get_value("Task", t.name, "_assign")
        emit("Q1 resave repairs a cleared _assign", "YES" if (after and after != "[]") else "NO", json.dumps(after))
        # ---- Q2: check 3 with BOTH fields cleared ----
        c = frappe.get_doc({"doctype": "Task", "subject": "D3B check3", "task_kind": "Returns processing / verification", "task_access_policy": "Returns processing / verification", "customer": cust, "status": "Open", "custom_assigned_to": RETURNS_USER, "custom_accepted_by": RETURNS_USER})
        c.flags.ignore_permissions = True
        c.insert()
        frappe.db.set_value("Task", c.name, {"_assign": "[]", "custom_assigned_to": ""})
        frappe.set_user(RETURNS_USER)
        c.reload()
        c.status = "Completed"
        try:
            c.save()
            emit("Q2 check 3 refuses completion, no owner at all", "FAIL", "completion was allowed")
        except Exception as e:
            msg = str(e)
            ok = ("Assign exactly 1 owner" in msg) or ("assigned to exactly 1 user" in msg)
            emit("Q2 check 3 refuses completion, no owner at all", "PASS" if ok else "FAIL", msg[:92])
        frappe.set_user("Administrator")
        # ---- how many legacy tasks would self-heal on a resave? ----
        n = 0
        healable = 0
        for x in frappe.get_all("Task", filters={"status": ["not in", ["Completed", "Cancelled"]]}, fields=["name", "_assign", "custom_assigned_to"], limit_page_length=0):
            try:
                a = json.loads(x.get("_assign") or "[]") or []
            except Exception:
                a = []
            if len(a) != 1:
                n += 1
                if (x.custom_assigned_to or "").strip():
                    healable += 1
        emit("legacy open tasks failing the count check", n)
        emit("  of those, self-heal on next save", healable, "custom_assigned_to is set, so policy.py repopulates _assign")
        emit("  of those, genuinely orphaned", n - healable, "no assignee recorded anywhere")
    except Exception as e:
        emit("RUN", "FAIL", str(e)[:150])
    finally:
        frappe.set_user("Administrator")
        frappe.db.rollback()
    print("D3B_RESULTS_START")
    for ln in out:
        print(ln)
    print("D3B_RESULTS_END")
d3b("e2e.returns@test.erpnext.am")
