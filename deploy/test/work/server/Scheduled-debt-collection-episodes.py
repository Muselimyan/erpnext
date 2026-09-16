# Name: Scheduled-debt-collection-episodes
# Type: Scheduler Event
# DocType: 
# Event: Daily
# Disabled: 0
# ---

# ═══════════════════════════════════════════════════════════════════════
# Raises Debt Collection tasks as EPISODES of chasing work.
#
# THE MODEL
# ---------
# A Debt Collection task used to be created the moment an invoice was raised,
# and then lived forever: it accumulated every subsequent invoice for that
# customer, so it could not be completed while the customer still owed
# anything. Completing it was therefore never truthful -- a task means "this
# work is done", and the work of chasing a debt is done when the call has been
# made, not when the customer eventually pays.
#
# So the debt is not the task. The debt lives in the ledger (task_debt_panel
# reads it live). A task is one attempt at collecting it: assigned, accepted,
# worked, and closed with an outcome. When the follow-up date arrives, a new
# episode is raised.
#
# WHEN AN EPISODE IS RAISED
#   1. An invoice is overdue by more than GRACE_DAYS, or
#   2. the customer's net receivable exceeds their debt threshold, or
#   3. a previous episode promised a follow-up and that date has arrived, or
#   4. a previous episode closed without a follow-up date and
#      DEFAULT_FOLLOW_UP_DAYS have passed since.
#
# Never more than ONE open episode per customer, and never any episode for a
# customer with nothing unpaid. Both are dedup rules, not storage: no balance is
# written to the task.
#
# Note this runs DAILY, not hourly like the Debt Alert scheduler. Chasing is a
# human activity on a human cadence; the alert is a tripwire.
#
# Log tag: [Episode]
# ═══════════════════════════════════════════════════════════════════════

COLLECTION_KIND = "Debt Collection"
GRACE_DAYS = 3
DEFAULT_FOLLOW_UP_DAYS = 7

today = frappe.utils.nowdate()

company = frappe.db.get_single_value("Global Defaults", "default_company")
if not company:
    companies = frappe.get_all("Company", pluck="name")
    company = companies[0] if companies else None

assignee = ""
if company:
    policy = frappe.get_doc("Task Access Policy", COLLECTION_KIND)
    assignee = policy.default_team_user or ""

if not company or not assignee:
    print(f"[Episode] {frappe.utils.now()} skipped: company={company} assignee={assignee}")
else:
    # Customers with at least one unpaid submitted invoice. Everything is keyed
    # off the ledger; no customer with a clean account is ever considered.
    unpaid = frappe.get_all(
        "Sales Invoice",
        filters={"docstatus": 1, "outstanding_amount": [">", 0]},
        fields=["customer", "name", "due_date", "outstanding_amount"],
        limit_page_length=0,
    )

    # NOTE: augmented assignment to a subscript -- by_customer[c]["x"] += n --
    # is rejected by RestrictedPython ("Augmented assignment of object items and
    # slices is not allowed"), so every accumulation below is an explicit
    # read-modify-write. This is a compile-level restriction that Frappe's
    # save-time check does NOT catch: the script saves cleanly and then fails
    # the first time the scheduler runs it.
    by_customer = {}
    for inv in (unpaid or []):
        cust = inv.customer
        if not cust:
            continue
        if cust not in by_customer:
            by_customer[cust] = {"outstanding": 0, "max_overdue": -99999, "oldest_due": ""}
        entry = by_customer[cust]
        entry["outstanding"] = entry["outstanding"] + float(inv.outstanding_amount or 0)
        if inv.due_date:
            overdue_days = frappe.utils.date_diff(today, inv.due_date)
            if overdue_days > entry["max_overdue"]:
                entry["max_overdue"] = overdue_days
                entry["oldest_due"] = str(inv.due_date)

    raised = 0
    skipped_open = 0
    waiting = 0

    for cust in by_customer:
        info = by_customer[cust]

        # ── One open episode per customer ──────────────────────────────
        open_episodes = frappe.get_all(
            "Task",
            filters={"task_kind": COLLECTION_KIND, "customer": cust,
                     "status": ["not in", ["Completed", "Cancelled"]]},
            fields=["name"],
            limit_page_length=1,
        )
        if open_episodes:
            skipped_open += 1
            continue

        # ── Should a new episode be raised? ────────────────────────────
        reason = ""
        overdue_days = info["max_overdue"]
        if overdue_days > GRACE_DAYS:
            reason = "overdue by " + str(overdue_days) + " days (since " + str(info["oldest_due"]) + ")"

        if not reason:
            threshold = float(frappe.db.get_value("Customer", cust, "debt_threshold_amd") or 0)
            if threshold > 0 and info["outstanding"] > threshold:
                reason = "outstanding " + str(info["outstanding"]) + " exceeds threshold " + str(threshold)

        # A previous episode's own decision takes precedence over the clock.
        last_closed = frappe.get_all(
            "Task",
            filters={"task_kind": COLLECTION_KIND, "customer": cust, "status": "Completed"},
            fields=["name", "collection_outcome", "collection_follow_up_date", "completed_at", "modified"],
            order_by="modified desc",
            limit_page_length=1,
        )
        if last_closed:
            prev = last_closed[0]
            follow_up = prev.collection_follow_up_date
            if follow_up:
                # Promised a call back on a specific date: wait for it.
                if frappe.utils.date_diff(today, follow_up) < 0:
                    waiting += 1
                    continue
                reason = "follow-up due (" + str(follow_up) + ", previous outcome: " + str(prev.collection_outcome or "none") + ")"
            else:
                closed_on = prev.completed_at or prev.modified
                if closed_on:
                    days_since = frappe.utils.date_diff(today, str(closed_on)[:10])
                    if days_since < DEFAULT_FOLLOW_UP_DAYS:
                        waiting += 1
                        continue
                    if not reason:
                        reason = "no follow-up date set, " + str(days_since) + " days since the last attempt"

        if not reason:
            continue

        subject_name = frappe.db.get_value("Customer", cust, "customer_name") or cust
        task = frappe.new_doc("Task")
        task.subject = "Collect debt: " + str(subject_name)
        task.status = "Open"
        task.task_kind = COLLECTION_KIND
        task.task_access_policy = COLLECTION_KIND
        task.customer = cust
        task.custom_assigned_to = assignee
        # exp_end_date drives the existing doc15_task_auto_escalation job, so an
        # ignored episode escalates without any new machinery.
        task.exp_end_date = frappe.utils.add_days(today, DEFAULT_FOLLOW_UP_DAYS)
        task.description = ("Chase the outstanding balance for " + str(subject_name) + ".\n\n"
                            + "Raised because: " + reason + ".\n\n"
                            + "The live balance and unpaid invoices are shown on this task. "
                            + "Record any payment here, then set an outcome and a follow-up date before completing.")
        task.insert(ignore_permissions=True)

        frappe.db.set_value("Task", task.name, "_assign", json.dumps([assignee]), update_modified=False)
        if not frappe.db.exists("ToDo", {"reference_type": "Task", "reference_name": task.name, "allocated_to": assignee, "status": "Open"}):
            todo = frappe.new_doc("ToDo")
            todo.status = "Open"
            todo.allocated_to = assignee
            todo.reference_type = "Task"
            todo.reference_name = task.name
            todo.description = task.subject
            todo.assigned_by = frappe.session.user
            todo.insert(ignore_permissions=True)

        raised += 1
        print(f"[Episode] {frappe.utils.now()} raised {task.name} for {cust}: {reason}")

    print(f"[Episode] {frappe.utils.now()} customers_with_debt={len(by_customer)} raised={raised} already_open={skipped_open} waiting_for_follow_up={waiting}")
