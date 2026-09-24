# ==============================================================
# D8 - establish the _assign mechanism FROM FRAPPE'S SOURCE, not from the state
# of existing records. READ ONLY.
#
# The earlier D8 note leaned on two different kinds of evidence and did not
# distinguish them:
#
#   - a controlled experiment (create a task, observe _assign) -- sound
#   - a count of 3,232 existing tasks with an empty column -- worthless, the
#     test data is junk and proves nothing about the code
#
# and it asserted a MECHANISM ("the framework overwrites it") that was inferred,
# never verified. This reads the actual framework source and the actual field
# definition to settle it.
# ==============================================================
import frappe
import inspect
import json
def d8():
    out = []
    def emit(k, v):
        out.append("D8 | {0:<42} | {1}".format(k, v))
    # ---- 1. is _assign even a real column on Task? ----
    meta = frappe.get_meta("Task")
    df = meta.get_field("_assign")
    emit("_assign is a defined DocField", "YES" if df else "NO - it is a framework column, not a DocField")
    cols = frappe.db.get_table_columns("Task")
    emit("_assign exists as a DB column", "_assign" in cols)
    # ---- 2. is it in the list of columns a document actually writes? ----
    doc = frappe.new_doc("Task")
    valid = doc.get_valid_columns()
    emit("_assign in Document.get_valid_columns()", "_assign" in valid)
    emit("  (if NO, doc.set() can never persist it)", "")
    # ---- 3. what does Frappe say the default/permitted columns are ----
    try:
        from frappe.model import default_fields, optional_fields
        emit("_assign in frappe.model.default_fields", "_assign" in default_fields)
        emit("_assign in frappe.model.optional_fields", "_assign" in optional_fields)
    except Exception as e:
        emit("frappe.model import", str(e)[:70])
    # ---- 4. who writes it legitimately, per the framework ----
    try:
        from frappe.desk.form import assign_to
        src = inspect.getsource(assign_to)
        writes = []
        for ln in src.split("\n"):
            if "_assign" in ln and ("set_value" in ln or "update" in ln or "=" in ln):
                writes.append(ln.strip()[:120])
        emit("assign_to module writes _assign at", "{0} site(s)".format(len(writes)))
        for w in writes[:6]:
            emit("   ", w)
    except Exception as e:
        emit("assign_to inspect", str(e)[:70])
    # ---- 5. the decisive experiment, stated precisely ----
    # Not "do old records have it" -- that is data. This is: given a FRESH task
    # with custom_assigned_to set, does policy.py's doc.set() survive insert?
    cust = frappe.db.get_value("Customer", {"disabled": 0}, "name")
    t = frappe.get_doc({"doctype": "Task", "subject": "D8 probe", "task_kind": "Returns processing / verification", "task_access_policy": "Returns processing / verification", "customer": cust, "status": "Open", "custom_assigned_to": "e2e.returns@test.erpnext.am"})
    t.flags.ignore_permissions = True
    t.insert()
    emit("fresh task: _assign in memory post-insert", json.dumps(t.get("_assign")))
    emit("fresh task: _assign in DB post-insert", json.dumps(frappe.db.get_value("Task", t.name, "_assign")))
    emit("fresh task: custom_assigned_to in DB", json.dumps(frappe.db.get_value("Task", t.name, "custom_assigned_to")))
    # and does the framework's own API persist it?
    try:
        from frappe.desk.form.assign_to import add as assign_add
        assign_add({"doctype": "Task", "name": t.name, "assign_to": ["e2e.returns@test.erpnext.am"]})
        emit("after assign_to.add(), _assign in DB", json.dumps(frappe.db.get_value("Task", t.name, "_assign")))
    except Exception as e:
        emit("assign_to.add()", str(e)[:90])
    # ---- 6. does a ToDo exist for tasks the FLOW created? ----
    # make_task writes _assign by db.set_value AND creates a ToDo. If the column
    # is derived from ToDo, the ToDo is the real source of truth.
    flowtask = frappe.db.sql("""select t.name from `tabTask` t where ifnull(t._assign,'[]') not in ('','[]') limit 1""", as_dict=True)
    if flowtask:
        fn = flowtask[0].name
        td = frappe.db.count("ToDo", {"reference_type": "Task", "reference_name": fn})
        emit("a task WITH _assign has ToDo rows", "{0} (task {1})".format(td, fn))
    notd = frappe.db.sql("""select t.name from `tabTask` t where ifnull(t._assign,'[]') in ('','[]') and ifnull(t.custom_assigned_to,'')<>'' limit 1""", as_dict=True)
    if notd:
        nn = notd[0].name
        td2 = frappe.db.count("ToDo", {"reference_type": "Task", "reference_name": nn})
        emit("a task WITHOUT _assign has ToDo rows", "{0} (task {1})".format(td2, nn))
    print("D8_RESULTS_START")
    for ln in out:
        print(ln)
    print("D8_RESULTS_END")
    frappe.db.rollback()
d8()
