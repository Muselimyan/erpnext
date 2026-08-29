# Name: Telegram Task Assignment Notification
# Type: DocType Event
# DocType: Task
# Event: After Save
# Disabled: 0
# ---

# Triggers on Task (After Save) — sends Telegram when custom_assigned_to changes
before = doc.get_doc_before_save()

if doc.is_new():
    old_assignee = ""
else:
    old_assignee = (before.custom_assigned_to or "") if before else ""
new_assignee = doc.custom_assigned_to or ""

print(f"[TgAssign] {frappe.utils.now()} task={doc.name} old={old_assignee} new={new_assignee} changed={new_assignee != old_assignee}")

# Only proceed if there is a new assignee and it changed
if new_assignee and new_assignee != old_assignee:
    # Skip notification on acceptance (user accepting for themselves)
    is_acceptance = (not doc.is_new() and before
        and doc.has_value_changed("custom_accepted_by")
        and doc.custom_accepted_by)
    if is_acceptance:
        print(f"[TgAssign] {frappe.utils.now()} task={doc.name} SKIPPED: reason=acceptance")
    else:
        telegram_settings = frappe.get_doc("Telegram Settings")
        raw_token = telegram_settings.get_password("bot_token") or ""

        bot_token = raw_token.strip()
        if bot_token.lower().startswith("bot"):
            bot_token = bot_token[3:]

        if not bot_token:
            print(f"[TgAssign] {frappe.utils.now()} task={doc.name} SKIPPED: reason=no_token")
        else:
            task_kind = doc.get("task_kind") or "N/A"

            # Priority mapping
            priority = doc.get("priority") or "Medium"
            priority_emojis = {
                "Low": "Low",
                "Medium": "Medium",
                "High": "High",
                "Urgent": "Urgent"
            }
            priority_display = priority_emojis.get(priority, priority)

            GENERIC_ROLES = [
                "System Manager", "All", "Guest", "Employee", "Stock User",
                "Sales User", "Purchase User", "Accounts User", "Item Manager"
            ]

            target_users = set()
            is_team = "example" in new_assignee.lower()

            if is_team:
                # Team placeholder: find all real users with matching Ops-* roles
                user_roles = frappe.get_all(
                    "Has Role",
                    filters={"parent": new_assignee, "parenttype": "User"},
                    fields=["role"]
                )
                for r in user_roles:
                    role_name = r.role
                    if role_name not in GENERIC_ROLES and "Ops" in role_name:
                        role_members = frappe.get_all(
                            "Has Role",
                            filters={"role": role_name, "parenttype": "User"},
                            fields=["parent"]
                        )
                        for rm in role_members:
                            member_email = rm.parent
                            if "example" not in member_email.lower() and frappe.db.get_value("User", member_email, "enabled"):
                                target_users.add(member_email)
            else:
                # Real user: notify only them
                if frappe.db.exists("User", new_assignee) and frappe.db.get_value("User", new_assignee, "enabled"):
                    target_users.add(new_assignee)

            target_users_list = list(target_users)
            print(f"[TgAssign] {frappe.utils.now()} task={doc.name} is_team={is_team} target_users={len(target_users_list)} users={target_users_list}")

            # Format display names for the message
            assignee_names = []
            for email in target_users_list:
                full_name = frappe.db.get_value("User", email, "full_name") or email
                assignee_names.append(full_name)

            assignees_str = ", ".join(assignee_names) if assignee_names else new_assignee

            is_team_task = is_team and len(target_users_list) > 1
            header_text = "New Team Task Assigned!" if is_team_task else "New Task Assigned!"
            assign_label = "*Assigned To (Team):*" if is_team_task else "*Assigned To:*"

            assigned_by_name = frappe.db.get_value("User", frappe.session.user, "full_name") or frappe.session.user
            task_url = f"https://test.erpnext.am/app/task/{doc.name}"

            message = (
                f"{header_text}\n\n"
                f"*Task:* {doc.name}\n"
                f"*Kind:* {task_kind}\n"
                f"*Priority:* {priority_display}\n"
                f"*Assigned By:* {assigned_by_name}\n"
                f"{assign_label} {assignees_str}\n\n"
                f"Go To Task: {task_url}"
            )

            # Send Telegram message to target users
            for user_email in target_users_list:
                chat_id = frappe.db.get_value("User", user_email, "telegram_chat_id")

                if chat_id:
                    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
                    payload = {
                        "chat_id": chat_id,
                        "text": message,
                        "parse_mode": "Markdown"
                    }
                    try:
                        frappe.make_post_request(url, json=payload)
                        print(f"[TgAssign] {frappe.utils.now()} task={doc.name} sent_to={user_email} chat_id=yes")
                    except Exception as e:
                        frappe.log_error(
                            title="Telegram Task Notification Failed",
                            message=f"Error sending to {user_email}: {str(e)}"
                        )
                        print(f"[TgAssign] {frappe.utils.now()} task={doc.name} FAILED: user={user_email} error={str(e)}")
                else:
                    print(f"[TgAssign] {frappe.utils.now()} task={doc.name} sent_to={user_email} chat_id=MISSING")
else:
    if not new_assignee:
        print(f"[TgAssign] {frappe.utils.now()} task={doc.name} SKIPPED: reason=no_assignee")
    else:
        print(f"[TgAssign] {frappe.utils.now()} task={doc.name} SKIPPED: reason=no_change")
