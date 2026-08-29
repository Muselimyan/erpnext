# Name: Telegram Task Status Update
# Type: DocType Event
# DocType: Task
# Event: After Save
# Disabled: 0
# ---

# Triggers on Task (After Save)
# SAFEGUARD 1: Do not run on initial creation (only on updates)
before_doc = doc.get_doc_before_save()

if before_doc and doc.has_value_changed("status"):
    current_status = doc.status

    # SAFEGUARD 2: Only notify on key milestone statuses
    NOTIFIABLE_STATUSES = ["Working", "Completed", "Cancelled"]

    if current_status in NOTIFIABLE_STATUSES:
        current_user = frappe.session.user

        # Use task owner as the notification target (the person who created/delegated this task)
        assigner = doc.owner

        # SAFEGUARD 3: Prevent self-notifications
        if assigner and assigner != current_user:

            telegram_settings = frappe.get_doc("Telegram Settings")
            raw_token = telegram_settings.get_password("bot_token") or ""
            bot_token = raw_token.strip()
            if bot_token.lower().startswith("bot"):
                bot_token = bot_token[3:]

            if not bot_token:
                print(f"[TgStatus] {frappe.utils.now()} task={doc.name} SKIPPED: reason=no_token")
            else:
                # Read chat ID from User custom field
                chat_id = frappe.db.get_value("User", assigner, "telegram_chat_id")

                if chat_id:
                    status_icons = {
                        "Working": "Working",
                        "Completed": "Completed",
                        "Cancelled": "Cancelled"
                    }
                    status_display = status_icons.get(current_status, current_status)

                    updater_name = frappe.db.get_value("User", current_user, "full_name") or current_user
                    task_url = f"https://test.erpnext.am/app/task/{doc.name}"

                    message = (
                        f"Task Status Updated!\n\n"
                        f"*Task:* {doc.name}\n"
                        f"*New Status:* {status_display}\n"
                        f"*Updated By:* {updater_name}\n\n"
                        f"View Task: {task_url}"
                    )

                    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
                    payload = {
                        "chat_id": chat_id,
                        "text": message,
                        "parse_mode": "Markdown"
                    }
                    try:
                        frappe.make_post_request(url, json=payload)
                        print(f"[TgStatus] {frappe.utils.now()} task={doc.name} sent_to={assigner} status={current_status}")
                    except Exception as e:
                        frappe.log_error(
                            title="Status Notification Failed",
                            message=f"Error sending status update to {assigner}: {str(e)}"
                        )
                        print(f"[TgStatus] {frappe.utils.now()} task={doc.name} FAILED: user={assigner} error={str(e)}")
                else:
                    print(f"[TgStatus] {frappe.utils.now()} task={doc.name} SKIPPED: reason=no_chat_id user={assigner}")
        else:
            print(f"[TgStatus] {frappe.utils.now()} task={doc.name} SKIPPED: reason=self_notification user={current_user}")
    else:
        print(f"[TgStatus] {frappe.utils.now()} task={doc.name} status={current_status} SKIPPED: reason=not_notifiable")
